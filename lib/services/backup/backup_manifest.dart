import 'dart:convert';

/// Archive entry name of the manifest inside a `.hmb` backup. Old app
/// versions restore this as a plain file into their database directory,
/// where it is harmless: it is not a `.hive` file, so Hive never opens it
/// and old backup scans never pick it up.
const backupManifestFileName = 'backup_manifest.json';

const backupManifestFormatVersion = 1;

/// Upper bound when reading the manifest entry into memory during restore.
/// The manifest is the only part of a backup that is ever buffered whole;
/// everything else streams. Even with an `audioEntries` map covering tens of
/// thousands of songs the manifest stays a few megabytes, so anything larger
/// is treated as invalid rather than risking a large allocation.
const backupManifestMaxBytes = 16 * 1024 * 1024;

/// Metadata embedded in a `.hmb` backup describing the environment that
/// created it, so restore can rewrite persisted absolute paths exactly
/// instead of guessing by file name. Backups made before this existed have
/// no manifest; [fromJsonString] returns null for anything unreadable and
/// restore then falls back to the legacy heuristics.
class BackupManifest {
  BackupManifest({
    this.formatVersion = backupManifestFormatVersion,
    this.createdAt,
    this.packageName,
    this.appVersion,
    this.buildNumber,
    this.platform,
    this.sourceSupportDir,
    this.sourceDbDir,
    this.sourceMusicDir,
    this.includesAudio = false,
    Map<String, String>? audioEntries,
  }) : audioEntries = audioEntries ?? const {};

  final int formatVersion;
  final String? createdAt;
  final String? packageName;
  final String? appVersion;
  final String? buildNumber;
  final String? platform;

  /// The source install's application support directory.
  final String? sourceSupportDir;

  /// The source install's Hive database directory.
  final String? sourceDbDir;

  /// The directory audio files were downloaded to at backup time (the
  /// user-chosen download location, or the in-app default Music directory).
  final String? sourceMusicDir;

  final bool includesAudio;

  /// Archive entry name -> original absolute file path, for every audio
  /// entry in the backup. Restore uses this for exact matching, which also
  /// resolves entries the backup had to rename to avoid name collisions
  /// (e.g. "song (2).m4a").
  final Map<String, String> audioEntries;

  Map<String, dynamic> toJson() => {
        'formatVersion': formatVersion,
        'createdAt': createdAt,
        'source': {
          'packageName': packageName,
          'appVersion': appVersion,
          'buildNumber': buildNumber,
          'platform': platform,
        },
        'sourceSupportDir': sourceSupportDir,
        'sourceDbDir': sourceDbDir,
        'sourceMusicDir': sourceMusicDir,
        'includesAudio': includesAudio,
        'audioEntries': audioEntries,
      };

  String toJsonString() => jsonEncode(toJson());

  /// Lenient parse: unknown keys are ignored (newer manifests stay readable)
  /// and wrong-typed values degrade to their defaults. Only a missing or
  /// non-integer formatVersion — or anything that isn't a JSON object at
  /// all — makes the manifest unusable, in which case null is returned and
  /// the caller treats the backup as legacy.
  static BackupManifest? fromJsonString(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map) return null;

      final formatVersion = decoded['formatVersion'];
      if (formatVersion is! int) return null;

      final source = decoded['source'];
      final sourceMap = source is Map ? source : const {};

      return BackupManifest(
        formatVersion: formatVersion,
        createdAt: _asString(decoded['createdAt']),
        packageName: _asString(sourceMap['packageName']),
        appVersion: _asString(sourceMap['appVersion']),
        buildNumber: _asString(sourceMap['buildNumber']),
        platform: _asString(sourceMap['platform']),
        sourceSupportDir: _asString(decoded['sourceSupportDir']),
        sourceDbDir: _asString(decoded['sourceDbDir']),
        sourceMusicDir: _asString(decoded['sourceMusicDir']),
        includesAudio: decoded['includesAudio'] == true,
        audioEntries: _asStringMap(decoded['audioEntries']),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _asString(dynamic value) => value is String ? value : null;

  static Map<String, String> _asStringMap(dynamic value) {
    if (value is! Map) return const {};
    final result = <String, String>{};
    for (final entry in value.entries) {
      final key = entry.key;
      final entryValue = entry.value;
      if (key is String && entryValue is String) {
        result[key] = entryValue;
      }
    }
    return result;
  }
}
