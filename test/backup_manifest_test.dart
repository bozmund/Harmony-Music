import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/backup/backup_manifest.dart';

void main() {
  group('BackupManifest', () {
    test('round-trips through JSON', () {
      final manifest = BackupManifest(
        createdAt: '2026-07-06T12:00:00.000Z',
        packageName: 'com.anandnet.harmonymusic.prod',
        appVersion: '1.2.3',
        buildNumber: '42',
        platform: 'android',
        sourceSupportDir: '/data/user/0/com.anandnet.harmonymusic.prod/files',
        sourceDbDir:
            '/data/user/0/com.anandnet.harmonymusic.prod/app_flutter',
        sourceMusicDir:
            '/data/user/0/com.anandnet.harmonymusic.prod/files/Music',
        includesAudio: true,
        audioEntries: {
          'song.m4a':
              '/data/user/0/com.anandnet.harmonymusic.prod/files/Music/song.m4a',
          'song (2).m4a': '/storage/emulated/0/Music/song.m4a',
        },
      );

      final parsed = BackupManifest.fromJsonString(manifest.toJsonString());

      expect(parsed, isNotNull);
      expect(parsed!.formatVersion, backupManifestFormatVersion);
      expect(parsed.createdAt, '2026-07-06T12:00:00.000Z');
      expect(parsed.packageName, 'com.anandnet.harmonymusic.prod');
      expect(parsed.appVersion, '1.2.3');
      expect(parsed.buildNumber, '42');
      expect(parsed.platform, 'android');
      expect(parsed.sourceSupportDir,
          '/data/user/0/com.anandnet.harmonymusic.prod/files');
      expect(parsed.sourceDbDir,
          '/data/user/0/com.anandnet.harmonymusic.prod/app_flutter');
      expect(parsed.sourceMusicDir,
          '/data/user/0/com.anandnet.harmonymusic.prod/files/Music');
      expect(parsed.includesAudio, isTrue);
      expect(parsed.audioEntries['song (2).m4a'],
          '/storage/emulated/0/Music/song.m4a');
    });

    test('returns null for malformed JSON', () {
      expect(BackupManifest.fromJsonString('not json at all'), isNull);
      expect(BackupManifest.fromJsonString('[1, 2, 3]'), isNull);
      expect(BackupManifest.fromJsonString('"a string"'), isNull);
    });

    test('returns null when formatVersion is missing or wrong-typed', () {
      expect(BackupManifest.fromJsonString('{}'), isNull);
      expect(
        BackupManifest.fromJsonString('{"formatVersion": "1"}'),
        isNull,
      );
    });

    test('ignores unknown keys and tolerates wrong-typed fields', () {
      final parsed = BackupManifest.fromJsonString(
        '{"formatVersion": 3, "futureFeature": {"a": 1}, '
        '"sourceMusicDir": 123, "includesAudio": "yes", '
        '"audioEntries": {"ok.m4a": "/music/ok.m4a", "bad": 5}, '
        '"source": "not-a-map"}',
      );

      expect(parsed, isNotNull);
      expect(parsed!.formatVersion, 3);
      expect(parsed.sourceMusicDir, isNull);
      expect(parsed.packageName, isNull);
      expect(parsed.includesAudio, isFalse);
      expect(parsed.audioEntries, {'ok.m4a': '/music/ok.m4a'});
    });

    test('manifest constants are sane', () {
      expect(backupManifestFileName, endsWith('.json'));
      // Must never look like a database or media file, or restore routing
      // and old app versions would treat it as one.
      expect(backupManifestFileName.endsWith('.hive'), isFalse);
      expect(backupManifestMaxBytes, greaterThan(1024 * 1024));
    });
  });
}
