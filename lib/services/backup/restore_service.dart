import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/repositories/download_repository.dart';
import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/playback_session_repository.dart';
import '../../domain/repositories/playlist_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/repositories/storage_admin_repository.dart';
import '../../utils/helper.dart';
import '../constant.dart';
import 'backup_manifest.dart';
import 'restore_path_rewriter.dart';

class RestoreProgress {
  const RestoreProgress({required this.current, required this.total});

  final int current;
  final int total;
}

typedef RestoreProgressCallback = void Function(RestoreProgress progress);

/// Restores a `.hmb` backup archive: extracts every entry to its
/// environment-correct location and then rewrites the absolute file paths
/// persisted inside the restored databases so they point at this install.
class RestoreService {
  RestoreService({
    required DownloadRepository downloadRepository,
    required LibraryRepository libraryRepository,
    required PlaylistRepository playlistRepository,
    required PlaybackSessionRepository playbackSessionRepository,
    required SettingsRepository settingsRepository,
    required StorageAdminRepository storageAdminRepository,
    Future<String> Function()? supportDirPathProvider,
    Future<bool> Function(String path)? directoryWritableProbe,
  }) : _downloadRepository = downloadRepository,
       _libraryRepository = libraryRepository,
       _playlistRepository = playlistRepository,
       _playbackSessionRepository = playbackSessionRepository,
       _settingsRepository = settingsRepository,
       _storageAdminRepository = storageAdminRepository,
       _supportDirPathProvider =
           supportDirPathProvider ?? _defaultSupportDirPath,
       _directoryWritableProbe =
           directoryWritableProbe ?? _isWritableDirectory;

  final DownloadRepository _downloadRepository;
  final LibraryRepository _libraryRepository;
  final PlaylistRepository _playlistRepository;
  final PlaybackSessionRepository _playbackSessionRepository;
  final SettingsRepository _settingsRepository;
  final StorageAdminRepository _storageAdminRepository;
  final Future<String> Function() _supportDirPathProvider;
  final Future<bool> Function(String path) _directoryWritableProbe;

  static Future<String> _defaultSupportDirPath() async =>
      (await getApplicationSupportDirectory()).path;

  /// A directory is usable only if a file can actually be created in it —
  /// existence alone is not enough (another package's private storage can
  /// exist yet be unwritable to this app).
  static Future<bool> _isWritableDirectory(String path) async {
    try {
      if (!await Directory(path).exists()) return false;
      final probe = File(
        '$path/.harmony_write_probe_'
        '${DateTime.now().microsecondsSinceEpoch}',
      );
      await probe.writeAsBytes(const [0], flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Restores the backup at [archivePath]. Errors propagate to the caller;
  /// the archive and its input stream are always released.
  Future<void> restoreFromFile(
    String archivePath, {
    RestoreProgressCallback? onProgress,
  }) async {
    final supportDirPath = await _supportDirPathProvider();
    final dbDirPath = await _storageAdminRepository.databaseDirectoryPath();

    InputFileStream? input;
    Archive? archive;
    try {
      // Parse the archive before touching the live databases: a corrupt or
      // unreadable backup must not leave the app with its .hive files
      // already deleted.
      input = InputFileStream(archivePath);
      archive = ZipDecoder().decodeStream(input);

      // Read the manifest (new backups only) while nothing has been touched
      // yet. It is consumed in memory and never extracted to disk; legacy
      // backups without one restore through the filename heuristics instead.
      final manifest = _readManifest(archive);
      final filesToRestore = archive.files
          .where((file) => file.isFile && !_isManifestEntry(file.name))
          .length;

      await _storageAdminRepository.closeAll();

      // Delete all live database files before writing the backup copy.
      for (final file in Directory(dbDirPath).listSync()) {
        if (file is File && file.path.endsWith('.hive')) {
          await file.delete();
        }
      }

      var restoredFiles = 0;
      onProgress?.call(
        RestoreProgress(current: restoredFiles, total: filesToRestore),
      );

      for (final file in archive) {
        if (!file.isFile || _isManifestEntry(file.name)) continue;

        final filename = _safeArchiveFileName(file.name);
        if (filename == null) {
          printWarning(
            "Skipping invalid restore entry: ${file.name}",
            tag: LogTags.backup,
          );
          continue;
        }

        printINFO("Restoring $filename", tag: LogTags.backup);
        final targetFileDir = _restoreTargetDir(
          filename,
          supportDirPath,
          dbDirPath,
        );
        final outputFile = File('$targetFileDir/$filename');
        await outputFile.parent.create(recursive: true);
        await _writeArchiveFileToDisk(file, outputFile.path);
        restoredFiles++;
        onProgress?.call(
          RestoreProgress(current: restoredFiles, total: filesToRestore),
        );
      }

      // closeAll() shut every box, and some repositories resolve theirs
      // eagerly and throw while it is closed. Without reopening here the
      // path rewrites below never run.
      await _storageAdminRepository.reopenCoreBoxes();

      final resolver = manifest == null
          ? null
          : RestorePathResolver(
              manifest: manifest,
              supportDirPath: supportDirPath,
            );

      await rewriteRestoredDownloadPaths(
        supportDirPath: supportDirPath,
        downloadRepository: _downloadRepository,
        resolver: resolver,
      );

      await rewriteRestoredLibraryPaths(
        supportDirPath: supportDirPath,
        libraryRepository: _libraryRepository,
        playlistRepository: _playlistRepository,
        playbackSessionRepository: _playbackSessionRepository,
        resolver: resolver,
      );

      await _validateRestoredSettingsPaths(manifest, supportDirPath);
    } finally {
      await archive?.clear();
      await input?.close();
    }
  }

  /// The restored AppPrefs still hold the source install's download/export
  /// directories; a prod backup restored into dev would send every future
  /// download into prod's private storage. Keep each setting only when its
  /// directory is actually usable here, otherwise reset it to the default.
  Future<void> _validateRestoredSettingsPaths(
    BackupManifest? manifest,
    String supportDirPath,
  ) async {
    await validateRestoredLocationSetting(
      currentValue: _settingsRepository.getDownloadLocationPath(),
      sourceSupportDir: manifest?.sourceSupportDir,
      supportDirPath: supportDirPath,
      isUsableDirectory: _directoryWritableProbe,
      persist: _settingsRepository.setDownloadLocationPath,
      reset: _settingsRepository.resetDownloadLocationPath,
      settingName: 'download location',
    );
    await validateRestoredLocationSetting(
      currentValue: _settingsRepository.getExportLocationPath(),
      sourceSupportDir: manifest?.sourceSupportDir,
      supportDirPath: supportDirPath,
      isUsableDirectory: _directoryWritableProbe,
      persist: _settingsRepository.setExportLocationPath,
      reset: _settingsRepository.resetExportLocationPath,
      settingName: 'export location',
    );
  }

  bool _isManifestEntry(String archiveName) =>
      _safeArchiveFileName(archiveName) == backupManifestFileName;

  /// Reads the manifest entry into memory (it is tiny and bounded by
  /// [backupManifestMaxBytes]); anything unreadable degrades to null so the
  /// backup restores in legacy mode instead of failing.
  BackupManifest? _readManifest(Archive archive) {
    try {
      final entry = archive.find(backupManifestFileName);
      if (entry == null ||
          !entry.isFile ||
          entry.size > backupManifestMaxBytes) {
        return null;
      }
      final bytes = entry.readBytes();
      if (bytes == null) return null;
      final manifest = BackupManifest.fromJsonString(utf8.decode(bytes));
      if (manifest == null) {
        printWarning(
          "Backup manifest is unreadable, restoring in legacy mode",
          tag: LogTags.backup,
        );
      }
      return manifest;
    } catch (e) {
      printWarning(
        "Could not read backup manifest ($e), restoring in legacy mode",
        tag: LogTags.backup,
      );
      return null;
    }
  }
}

String? _safeArchiveFileName(String archiveName) {
  final normalizedName = archiveName.replaceAll('\\', '/');
  final parts = normalizedName
      .split('/')
      .where((part) => part.isNotEmpty)
      .toList();
  final fileName = parts.isEmpty ? null : parts.last;
  if (fileName == null || fileName == '.' || fileName == '..') {
    return null;
  }
  return fileName;
}

String _restoreTargetDir(
  String filename,
  String supportDirPath,
  String dbDirPath,
) {
  final lowerFilename = filename.toLowerCase();
  if (lowerFilename.endsWith(".m4a") || lowerFilename.endsWith(".opus")) {
    return "$supportDirPath/Music";
  }
  if (lowerFilename.endsWith(".png")) {
    return "$supportDirPath/thumbnails";
  }
  return dbDirPath;
}

Future<void> _writeArchiveFileToDisk(
  ArchiveFile file,
  String outputFilePath,
) async {
  final output = OutputFileStream(outputFilePath);
  try {
    file.writeContent(output);
  } finally {
    await output.close();
  }
}
