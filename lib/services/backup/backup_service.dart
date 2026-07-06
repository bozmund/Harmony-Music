import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/repositories/download_repository.dart';
import '../../domain/repositories/playlist_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/repositories/storage_admin_repository.dart';
import '../../utils/helper.dart';
import '../app_contracts.dart';
import '../app_platform_service.dart';
import '../constant.dart';
import 'backup_manifest.dart';

class BackupProgress {
  const BackupProgress({
    required this.current,
    required this.total,
    required this.fileName,
  });

  final int current;
  final int total;
  final String fileName;
}

typedef BackupProgressCallback = void Function(BackupProgress progress);

/// A file selected for backup, with its archive entry name already assigned
/// so name collisions are resolved once and recorded in the manifest.
class BackupEntry {
  const BackupEntry({
    required this.sourcePath,
    required this.archiveName,
    required this.storeUncompressed,
    required this.isAudio,
  });

  final String sourcePath;
  final String archiveName;

  /// Audio and image formats are already compressed; storing them raw keeps
  /// the archive streamable instead of buffering deflate output per entry.
  final bool storeUncompressed;

  /// Audio entries are recorded in the manifest's entry-name -> original-path
  /// map so restore can rewrite their persisted paths exactly.
  final bool isAudio;
}

/// Creates `.hmb` backup archives: a manifest describing this install's
/// environment, every Hive database file, plus (when requested) the
/// downloaded audio files and their thumbnails.
class BackupService {
  BackupService({
    required DownloadRepository downloadRepository,
    required PlaylistRepository playlistRepository,
    required SettingsRepository settingsRepository,
    required StorageAdminRepository storageAdminRepository,
    Future<String> Function()? supportDirPathProvider,
    Future<AppPlatformInfo> Function()? appInfoProvider,
  }) : _downloadRepository = downloadRepository,
       _playlistRepository = playlistRepository,
       _settingsRepository = settingsRepository,
       _storageAdminRepository = storageAdminRepository,
       _supportDirPathProvider =
           supportDirPathProvider ?? _defaultSupportDirPath,
       _appInfoProvider = appInfoProvider ?? AppPlatformService.getAppInfo;

  final DownloadRepository _downloadRepository;
  final PlaylistRepository _playlistRepository;
  final SettingsRepository _settingsRepository;
  final StorageAdminRepository _storageAdminRepository;
  final Future<String> Function() _supportDirPathProvider;
  final Future<AppPlatformInfo> Function() _appInfoProvider;

  static Future<String> _defaultSupportDirPath() async =>
      (await getApplicationSupportDirectory()).path;

  /// Collects the files a backup would contain and assigns each its archive
  /// entry name. Flushes the open database boxes first so the `.hive` files
  /// on disk are current.
  Future<List<BackupEntry>> scanFilesToBackup({
    required bool includeAudio,
  }) async {
    final entries = <BackupEntry>[];
    final seenPaths = <String>{};
    // The manifest owns its entry name; no data file may claim it. Archive
    // names are reserved case-insensitively because the files may later be
    // extracted onto a case-insensitive filesystem.
    final usedArchiveNames = <String>{backupManifestFileName.toLowerCase()};
    var totalBackupBytes = 0;

    void addIfValid(String? path) {
      final normalizedPath = _normalizeFilePath(path);
      if (normalizedPath == null || normalizedPath.isEmpty) return;
      final file = File(normalizedPath);
      if (!file.existsSync()) {
        printWarning(
          "Skipping missing backup file: $normalizedPath",
          tag: LogTags.backup,
        );
        return;
      }
      final absolutePath = file.absolute.path;
      if (seenPaths.add(absolutePath)) {
        totalBackupBytes += file.lengthSync();
        entries.add(
          BackupEntry(
            sourcePath: absolutePath,
            archiveName: uniqueArchiveName(absolutePath, usedArchiveNames),
            storeUncompressed: _shouldStoreWithoutCompression(absolutePath),
            isAudio: _isAudioFile(absolutePath),
          ),
        );
      }
    }

    await _storageAdminRepository.flushBackupBoxes();
    // Per-playlist song boxes are dynamic (box name = playlist id), so the
    // static flush list above cannot cover them; without this their .hive
    // files may be backed up with unflushed writes missing.
    for (final playlist in await _playlistRepository.getPlaylists()) {
      await _storageAdminRepository.flushBox(playlist.playlistId);
    }

    final dbDir = await _storageAdminRepository.databaseDirectoryPath();
    for (final filePath in await processDirectoryInIsolate(dbDir)) {
      addIfValid(filePath);
    }

    if (includeAudio) {
      final supportDirPath = await _supportDirPathProvider();
      for (final filePath
          in await _downloadRepository.getDownloadedSongFilePaths()) {
        addIfValid(filePath);
      }
      try {
        for (final filePath in await processDirectoryInIsolate(
          "$supportDirPath/thumbnails",
          extensionFilter: ".png",
        )) {
          addIfValid(filePath);
        }
      } catch (e) {
        printERROR(e, tag: LogTags.backup);
      }
    }

    printINFO(
      "Found ${entries.length} files for backup ($totalBackupBytes bytes)",
      tag: LogTags.backup,
    );
    return entries;
  }

  /// Writes the backup archive: manifest first, then every entry. Audio and
  /// image entries stream straight from disk into the archive uncompressed;
  /// `.hive` files are gzip-compressed (their compressed form is buffered
  /// per entry, bounded by the largest database file).
  Future<void> createBackup(
    List<BackupEntry> entries,
    String outputPath,
    BackupProgressCallback onProgress,
  ) async {
    final manifest = await buildManifest(entries);
    final encoder = ZipFileEncoder();

    encoder.create(outputPath);
    try {
      encoder.addArchiveFile(
        ArchiveFile.string(backupManifestFileName, manifest.toJsonString())
          ..compression = CompressionType.none,
      );

      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final file = File(entry.sourcePath);
        if (!await file.exists()) {
          printWarning(
            "Skipping missing backup file: ${file.path}",
            tag: LogTags.backup,
          );
          continue;
        }

        onProgress(
          BackupProgress(
            current: i + 1,
            total: entries.length,
            fileName: entry.archiveName,
          ),
        );
        printINFO(
          "Adding ${entry.archiveName} to backup (${i + 1}/${entries.length})",
          tag: LogTags.backup,
        );
        try {
          if (entry.storeUncompressed) {
            await _addStoredFile(encoder, file, entry.archiveName);
          } else {
            await encoder.addFile(
              file,
              entry.archiveName,
              ZipFileEncoder.gzip,
            );
          }
        } catch (e) {
          if (!await file.exists()) {
            printWarning(
              "Skipping removed backup file: ${file.path}",
              tag: LogTags.backup,
            );
            continue;
          }
          rethrow;
        }
      }
    } finally {
      await encoder.close();
    }
  }

  /// Builds the manifest describing this install, so a restore elsewhere can
  /// rewrite the absolute paths persisted inside the backed-up databases.
  Future<BackupManifest> buildManifest(List<BackupEntry> entries) async {
    final appInfo = await _appInfoProvider();
    final sourceSupportDir = await _supportDirPathProvider();
    final sourceDbDir = await _storageAdminRepository.databaseDirectoryPath();
    final sourceMusicDir =
        _settingsRepository.getDownloadLocationPath() ??
        "$sourceSupportDir/Music";
    final audioEntries = <String, String>{
      for (final entry in entries)
        if (entry.isAudio) entry.archiveName: entry.sourcePath,
    };

    return BackupManifest(
      createdAt: DateTime.now().toUtc().toIso8601String(),
      packageName: appInfo.packageName,
      appVersion: appInfo.version,
      buildNumber: appInfo.buildNumber,
      platform: Platform.operatingSystem,
      sourceSupportDir: sourceSupportDir,
      sourceDbDir: sourceDbDir,
      sourceMusicDir: sourceMusicDir,
      includesAudio: audioEntries.isNotEmpty,
      audioEntries: audioEntries,
    );
  }

  /// Adds [file] to the archive without compression, streaming its content
  /// instead of buffering it: ZipFileEncoder's level-based addFile runs
  /// already-compressed audio through deflate, which holds the whole
  /// compressed entry in memory — fatal for multi-gigabyte Music folders.
  Future<void> _addStoredFile(
    ZipFileEncoder encoder,
    File file,
    String archiveName,
  ) async {
    final fileStream = InputFileStream(file.path);
    try {
      final archiveFile = ArchiveFile.stream(archiveName, fileStream)
        ..compression = CompressionType.none
        ..lastModTime =
            (await file.lastModified()).millisecondsSinceEpoch ~/ 1000
        ..mode = (await file.stat()).mode;
      encoder.addArchiveFile(archiveFile);
    } finally {
      await fileStream.close();
    }
  }
}

String? _normalizeFilePath(String? path) {
  if (path == null) return null;
  final trimmedPath = path.trim();
  if (trimmedPath.startsWith("file://")) {
    return Uri.parse(trimmedPath).toFilePath();
  }
  return trimmedPath;
}

bool _shouldStoreWithoutCompression(String path) {
  return _isAudioFile(path) || path.toLowerCase().endsWith(".png");
}

bool _isAudioFile(String path) {
  final lowerPath = path.toLowerCase();
  return lowerPath.endsWith(".m4a") || lowerPath.endsWith(".opus");
}

/// Returns a unique archive entry name for [filePath], renaming collisions
/// to "name (2).ext" style. [usedArchiveNames] holds the lower-cased names
/// already taken (extraction targets may be case-insensitive filesystems).
String uniqueArchiveName(String filePath, Set<String> usedArchiveNames) {
  final fileName = filePath.split(RegExp(r'[\\/]')).last;
  if (usedArchiveNames.add(fileName.toLowerCase())) return fileName;

  final extensionIndex = fileName.lastIndexOf('.');
  final baseName = extensionIndex == -1
      ? fileName
      : fileName.substring(0, extensionIndex);
  final extension = extensionIndex == -1
      ? ""
      : fileName.substring(extensionIndex);
  var counter = 2;
  while (true) {
    final candidate = "$baseName ($counter)$extension";
    if (usedArchiveNames.add(candidate.toLowerCase())) return candidate;
    counter++;
  }
}

Future<List<String>> processDirectoryInIsolate(
  String dbDir, {
  String extensionFilter = ".hive",
}) async {
  // Use Isolate.run to execute the function in a new isolate
  return await Isolate.run(() async {
    final dir = Directory(dbDir);
    if (!dir.existsSync()) return <String>[];

    // List files in the directory
    final filesEntityList = await dir.list(recursive: false).toList();

    // Filter out .hive files
    final filesPath = filesEntityList
        .whereType<File>() // Ensure we only work with files
        .map((entity) {
          if (extensionFilter.isEmpty ||
              entity.path.endsWith(extensionFilter)) {
            return entity.path;
          }
        })
        .whereType<String>()
        .toList();

    return filesPath;
  });
}
