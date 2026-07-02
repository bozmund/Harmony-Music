import 'dart:io';

import '../../domain/repositories/download_repository.dart';
import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/playback_session_repository.dart';
import '../../domain/repositories/playlist_repository.dart';
import '../../utils/helper.dart';
import '../constant.dart';
import 'backup_manifest.dart';

/// Resolves a source install's file paths to this install's Music directory
/// using the backup manifest: first by exact match against the manifest's
/// audio entry map (which also covers entries the backup renamed to avoid
/// name collisions), then by swapping the source Music-directory prefix.
/// Comparisons are separator-normalized so backups made on Windows resolve
/// elsewhere and vice versa.
class RestorePathResolver {
  RestorePathResolver({
    required BackupManifest manifest,
    required String supportDirPath,
  }) : _musicDirPath = "$supportDirPath/Music",
       _entryNameByOriginalPath = {
         for (final entry in manifest.audioEntries.entries)
           _normalizeSeparators(entry.value): entry.key,
       },
       _sourceMusicPrefixes = {
         for (final prefix in [
           manifest.sourceMusicDir,
           if (manifest.sourceSupportDir != null)
             "${manifest.sourceSupportDir}/Music",
         ])
           if (prefix != null && prefix.isNotEmpty)
             _normalizeSeparators(prefix),
       }.toList();

  final String _musicDirPath;
  final Map<String, String> _entryNameByOriginalPath;
  final List<String> _sourceMusicPrefixes;

  /// Returns where [originalPath] should live on this install, or null when
  /// the manifest says nothing about it.
  String? resolveCandidate(String originalPath) {
    final normalized = _normalizeSeparators(originalPath);

    final entryName = _entryNameByOriginalPath[normalized];
    if (entryName != null) return "$_musicDirPath/$entryName";

    for (final prefix in _sourceMusicPrefixes) {
      if (normalized.startsWith("$prefix/")) {
        return "$_musicDirPath${normalized.substring(prefix.length)}";
      }
    }
    return null;
  }

  static String _normalizeSeparators(String path) =>
      path.replaceAll('\\', '/');
}

Future<void> rewriteRestoredDownloadPaths({
  required String supportDirPath,
  required DownloadRepository downloadRepository,
  RestorePathResolver? resolver,
}) async {
  final entries = await downloadRepository.getAllDownloadJsonEntries();
  for (final entry in entries.entries) {
    final rewrittenSong = rewriteRestoredDownloadSongWithResolver(
      entry.value,
      supportDirPath,
      resolver,
    );
    if (rewrittenSong == null) continue;

    await downloadRepository.updateDownloadedSongJson(
      entry.key.toString(),
      Map<String, dynamic>.from(rewrittenSong),
    );
  }
}

/// Manifest-aware variant of [rewriteRestoredDownloadSong]: when the
/// resolver knows the file's new location and the file is actually there,
/// the entry is rewritten to it exactly; anything else falls back to the
/// legacy heuristics, which are also the whole path for manifest-less
/// (pre-manifest) backups.
Map<dynamic, dynamic>? rewriteRestoredDownloadSongWithResolver(
  dynamic song,
  String supportDirPath,
  RestorePathResolver? resolver, {
  bool Function(String path)? fileExists,
}) {
  final resolved = _resolveWithManifest(song, resolver, fileExists);
  if (resolved != null) return resolved.songOrNullWhenUnchanged;

  return rewriteRestoredDownloadSong(
    song,
    supportDirPath,
    fileExists: fileExists,
  );
}

/// Manifest-aware variant of [rewriteRestoredLibrarySong]; same contract.
Map<dynamic, dynamic>? rewriteRestoredLibrarySongWithResolver(
  dynamic song,
  String supportDirPath,
  RestorePathResolver? resolver, {
  bool Function(String path)? fileExists,
}) {
  final resolved = _resolveWithManifest(song, resolver, fileExists);
  if (resolved != null) return resolved.songOrNullWhenUnchanged;

  return rewriteRestoredLibrarySong(
    song,
    supportDirPath,
    fileExists: fileExists,
  );
}

class _ManifestResolution {
  const _ManifestResolution(this.songOrNullWhenUnchanged);

  /// The rewritten song map, or null when the entry already pointed at the
  /// resolved file and nothing needs to be written back.
  final Map<dynamic, dynamic>? songOrNullWhenUnchanged;
}

_ManifestResolution? _resolveWithManifest(
  dynamic song,
  RestorePathResolver? resolver,
  bool Function(String path)? fileExists,
) {
  if (resolver == null || song is! Map) return null;

  final originalPath = restoredDownloadPathFromSong(song);
  if (originalPath == null ||
      originalPath.startsWith('http://') ||
      originalPath.startsWith('https://')) {
    return null;
  }

  final candidate = resolver.resolveCandidate(originalPath);
  if (candidate == null) return null;

  final exists = fileExists ?? ((path) => File(path).existsSync());
  if (!exists(candidate)) return null;

  if (song["url"] == candidate) return const _ManifestResolution(null);
  return _ManifestResolution(_songWithRewrittenUrl(song, candidate));
}

/// Rewrites a restored download JSON map so its file path points at this
/// install's Music directory. Returns the updated map, or null when the
/// entry should stay unchanged.
///
/// When the audio file exists neither at the restored nor the original path
/// (e.g. the backup was made without downloaded files, or by another
/// package whose private storage this install can't read), the entry is
/// kept and only its dead path is stripped: the song must stay visible in
/// the library, house keeping skips url-less entries instead of deleting
/// them, and playback falls back to online streaming.
Map<dynamic, dynamic>? rewriteRestoredDownloadSong(
  dynamic song,
  String supportDirPath, {
  bool Function(String path)? fileExists,
}) {
  if (song is! Map) return null;

  final updatedSong = Map<dynamic, dynamic>.from(song);
  final originalPath = restoredDownloadPathFromSong(updatedSong);
  final fileName = restoredFileName(originalPath);
  if (fileName == null) return null;

  final exists = fileExists ?? ((path) => File(path).existsSync());
  final restoredPath = "$supportDirPath/Music/$fileName";
  final usablePath = exists(restoredPath)
      ? restoredPath
      : originalPath != null && exists(originalPath)
      ? originalPath
      : null;

  if (usablePath == null) {
    printWarning(
      "Restored download has no local file, keeping it for streaming: "
      "$fileName",
      tag: LogTags.backup,
    );
    updatedSong.remove("url");
    updatedSong.remove("streamInfo");
    return updatedSong;
  }

  return _songWithRewrittenUrl(updatedSong, usablePath);
}

/// Rewrites the file paths persisted in every non-download song copy
/// (favorites, recently played, import review/duplicates, per-playlist boxes,
/// saved session queue) after a restore, so a backup made by another install
/// (e.g. the prod package) doesn't leave them pointing at inaccessible paths.
Future<void> rewriteRestoredLibraryPaths({
  required String supportDirPath,
  required LibraryRepository libraryRepository,
  required PlaylistRepository playlistRepository,
  required PlaybackSessionRepository playbackSessionRepository,
  RestorePathResolver? resolver,
}) async {
  Map<dynamic, dynamic>? transform(Map<dynamic, dynamic> song) =>
      rewriteRestoredLibrarySongWithResolver(song, supportDirPath, resolver);

  await libraryRepository.rewriteSongEntries(transform);
  await playlistRepository.rewritePlaylistSongEntries(transform);
  await playbackSessionRepository.rewriteQueueEntries(transform);
}

/// Rewrites a restored library/playlist/session song JSON map so its local
/// file path points at this install's Music directory. Returns the updated
/// map, or null when the entry should stay unchanged.
///
/// Like [rewriteRestoredDownloadSong], a missing file never drops the entry:
/// the stale local path is removed instead and playback falls back to online
/// streaming.
Map<dynamic, dynamic>? rewriteRestoredLibrarySong(
  dynamic song,
  String supportDirPath, {
  bool Function(String path)? fileExists,
}) {
  if (song is! Map) return null;

  final originalPath = restoredDownloadPathFromSong(song);
  if (originalPath == null ||
      originalPath.startsWith('http://') ||
      originalPath.startsWith('https://')) {
    return null;
  }

  final fileName = restoredFileName(originalPath);
  if (fileName == null) return null;

  final exists = fileExists ?? ((path) => File(path).existsSync());
  final restoredPath = "$supportDirPath/Music/$fileName";

  if (exists(restoredPath)) {
    if (song["url"] == restoredPath) return null;
    return _songWithRewrittenUrl(song, restoredPath);
  }

  if (exists(originalPath)) return null;

  // File is gone on this install: keep the entry but drop the dead local
  // path (and any stream info built around it) so playback streams online.
  final updatedSong = Map<dynamic, dynamic>.from(song);
  updatedSong.remove("url");
  updatedSong.remove("streamInfo");
  return updatedSong;
}

/// Maps a restored location setting (download/export directory) from the
/// source install's support directory to this install's. Returns null when
/// the value is not under the source support directory (external paths are
/// validated as-is instead).
String? rewriteRestoredSettingPath(
  String value, {
  required String? sourceSupportDir,
  required String supportDirPath,
}) {
  if (sourceSupportDir == null || sourceSupportDir.isEmpty) return null;

  final normalizedValue = value.replaceAll('\\', '/');
  final normalizedPrefix = sourceSupportDir.replaceAll('\\', '/');
  if (normalizedValue == normalizedPrefix) return supportDirPath;
  if (normalizedValue.startsWith('$normalizedPrefix/')) {
    return '$supportDirPath${normalizedValue.substring(normalizedPrefix.length)}';
  }
  return null;
}

/// Validates one restored location setting: in-app paths from the source
/// install are first mapped onto this install, then whatever directory the
/// setting points at is probed. Unusable directories reset the setting so
/// the app's own default applies — a restored download location pointing
/// into another package's private storage would otherwise break every
/// future download.
Future<void> validateRestoredLocationSetting({
  required String? currentValue,
  required String? sourceSupportDir,
  required String supportDirPath,
  required Future<bool> Function(String path) isUsableDirectory,
  required Future<void> Function(String value) persist,
  required Future<void> Function() reset,
  String settingName = 'location',
}) async {
  if (currentValue == null || currentValue.isEmpty) return;

  final rewritten = rewriteRestoredSettingPath(
    currentValue,
    sourceSupportDir: sourceSupportDir,
    supportDirPath: supportDirPath,
  );
  final candidate = rewritten ?? currentValue;

  if (await isUsableDirectory(candidate)) {
    if (candidate != currentValue) {
      printINFO(
        "Restored $settingName mapped to this install: $candidate",
        tag: LogTags.backup,
      );
      await persist(candidate);
    }
    return;
  }

  printWarning(
    "Restored $settingName is not usable here ($candidate), "
    "resetting to default",
    tag: LogTags.backup,
  );
  await reset();
}

/// Returns a copy of [song] with its top-level url and (when present) the
/// selected-stream url pointing at [usablePath].
Map<dynamic, dynamic> _songWithRewrittenUrl(
  Map<dynamic, dynamic> song,
  String usablePath,
) {
  final updatedSong = Map<dynamic, dynamic>.from(song);
  updatedSong["url"] = usablePath;
  final streamInfo = updatedSong["streamInfo"];
  if (streamInfo is List && streamInfo.length > 1 && streamInfo[1] is Map) {
    final streamInfoData = Map<dynamic, dynamic>.from(streamInfo[1]);
    streamInfoData["url"] = usablePath;
    final updatedStreamInfo = List<dynamic>.from(streamInfo);
    updatedStreamInfo[1] = streamInfoData;
    updatedSong["streamInfo"] = updatedStreamInfo;
  }
  return updatedSong;
}

String? restoredDownloadPathFromSong(Map<dynamic, dynamic> song) {
  final topLevelPath = normalizeRestoredFilePath(song["url"]);
  if (topLevelPath != null) return topLevelPath;

  final streamInfo = song["streamInfo"];
  if (streamInfo is List && streamInfo.length > 1 && streamInfo[1] is Map) {
    return normalizeRestoredFilePath(streamInfo[1]["url"]);
  }

  return null;
}

String? normalizeRestoredFilePath(dynamic value) {
  if (value is! String || value.trim().isEmpty) return null;

  final path = value.trim();
  if (path.startsWith("file://")) {
    return Uri.parse(path).toFilePath();
  }
  return path;
}

String? restoredFileName(String? path) {
  if (path == null || path.isEmpty) return null;

  final fileName = path.split(RegExp(r'[\\/]')).last;
  if (fileName.isEmpty || fileName == "." || fileName == "..") {
    return null;
  }
  return fileName;
}
