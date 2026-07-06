import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/backup/backup_manifest.dart';
import 'package:harmonymusic/services/backup/restore_path_rewriter.dart';

void main() {
  const supportDirPath = '/data/user/0/com.anandnet.harmonymusic.dev/files';
  const prodSupportDir = '/data/user/0/com.anandnet.harmonymusic.prod/files';
  const prodMusicDir = '$prodSupportDir/Music';

  BackupManifest prodManifest({Map<String, String>? audioEntries}) =>
      BackupManifest(
        packageName: 'com.anandnet.harmonymusic.prod',
        platform: 'android',
        sourceSupportDir: prodSupportDir,
        sourceMusicDir: prodMusicDir,
        includesAudio: true,
        audioEntries: audioEntries ?? const {},
      );

  RestorePathResolver resolverFor(BackupManifest manifest) =>
      RestorePathResolver(manifest: manifest, supportDirPath: supportDirPath);

  group('RestorePathResolver', () {
    test('resolves via the exact audio entry map, including renamed entries',
        () {
      final resolver = resolverFor(prodManifest(audioEntries: {
        'song.m4a': '$prodMusicDir/song.m4a',
        'song (2).m4a': '/storage/emulated/0/Music/song.m4a',
      }));

      expect(
        resolver.resolveCandidate('$prodMusicDir/song.m4a'),
        '$supportDirPath/Music/song.m4a',
      );
      // The external copy was renamed inside the archive; only the manifest
      // map knows that — filename guessing could never find it.
      expect(
        resolver.resolveCandidate('/storage/emulated/0/Music/song.m4a'),
        '$supportDirPath/Music/song (2).m4a',
      );
    });

    test('falls back to source Music-directory prefix swapping', () {
      final resolver = resolverFor(prodManifest());

      expect(
        resolver.resolveCandidate('$prodMusicDir/PLUTOSKI (Future).opus'),
        '$supportDirPath/Music/PLUTOSKI (Future).opus',
      );
      // Sibling directory sharing the prefix as a substring must not match.
      expect(
        resolver.resolveCandidate('${prodMusicDir}Videos/clip.m4a'),
        isNull,
      );
      expect(resolver.resolveCandidate('/unrelated/song.m4a'), isNull);
    });

    test('normalizes Windows separators from backups made on Windows', () {
      const winSupport = r'C:\Users\me\AppData\Roaming\harmonymusic';
      final resolver = resolverFor(BackupManifest(
        sourceSupportDir: winSupport,
        sourceMusicDir: '$winSupport\\Music',
        audioEntries: {'song.m4a': '$winSupport\\Music\\song.m4a'},
      ));

      expect(
        resolver.resolveCandidate('$winSupport\\Music\\song.m4a'),
        '$supportDirPath/Music/song.m4a',
      );
      expect(
        resolver.resolveCandidate('$winSupport\\Music\\other.opus'),
        '$supportDirPath/Music/other.opus',
      );
    });
  });

  group('manifest-aware download rewrite', () {
    test('rewrites via resolver when the resolved file exists', () {
      final song = _song('$prodMusicDir/song.opus');

      final rewritten = rewriteRestoredDownloadSongWithResolver(
        song,
        supportDirPath,
        resolverFor(prodManifest()),
        fileExists: (path) => path == '$supportDirPath/Music/song.opus',
      );

      expect(rewritten, isNotNull);
      expect(rewritten!['url'], '$supportDirPath/Music/song.opus');
      expect(
        rewritten['streamInfo'][1]['url'],
        '$supportDirPath/Music/song.opus',
      );
    });

    test('leaves entry unchanged when it already points at the resolved file',
        () {
      final song = _song('$supportDirPath/Music/song.opus');
      // Manifest of a backup made by THIS install (same-device restore).
      final manifest = BackupManifest(
        sourceSupportDir: supportDirPath,
        sourceMusicDir: '$supportDirPath/Music',
      );

      final rewritten = rewriteRestoredDownloadSongWithResolver(
        song,
        supportDirPath,
        resolverFor(manifest),
        fileExists: (path) => path == '$supportDirPath/Music/song.opus',
      );

      expect(rewritten, isNull);
    });

    test('falls back to legacy heuristics when the resolver has no answer',
        () {
      final song = _song('/some/unknown/place/song.opus');

      final withResolver = rewriteRestoredDownloadSongWithResolver(
        song,
        supportDirPath,
        resolverFor(prodManifest()),
        fileExists: (path) => path == '$supportDirPath/Music/song.opus',
      );
      final legacy = rewriteRestoredDownloadSong(
        _song('/some/unknown/place/song.opus'),
        supportDirPath,
        fileExists: (path) => path == '$supportDirPath/Music/song.opus',
      );

      expect(withResolver, legacy);
      expect(withResolver!['url'], '$supportDirPath/Music/song.opus');
    });

    test(
        'falls back to legacy keep-and-strip when the resolved file is '
        'missing everywhere', () {
      final song = _song('$prodMusicDir/song.opus');

      final rewritten = rewriteRestoredDownloadSongWithResolver(
        song,
        supportDirPath,
        resolverFor(prodManifest()),
        fileExists: (_) => false,
      );

      expect(rewritten, isNotNull);
      expect(rewritten!.containsKey('url'), isFalse);
      expect(rewritten.containsKey('streamInfo'), isFalse);
      expect(rewritten['videoId'], 'video-id');
    });

    test('behaves exactly like the legacy function without a manifest', () {
      final song = _song('$prodMusicDir/song.opus');

      final withoutResolver = rewriteRestoredDownloadSongWithResolver(
        song,
        supportDirPath,
        null,
        fileExists: (path) => path == '$supportDirPath/Music/song.opus',
      );
      final legacy = rewriteRestoredDownloadSong(
        _song('$prodMusicDir/song.opus'),
        supportDirPath,
        fileExists: (path) => path == '$supportDirPath/Music/song.opus',
      );

      expect(withoutResolver, legacy);
    });
  });

  group('manifest-aware library rewrite', () {
    test('rewrites via resolver when the resolved file exists', () {
      final song = <dynamic, dynamic>{
        'videoId': 'video-id',
        'url': '$prodMusicDir/song.opus',
      };

      final rewritten = rewriteRestoredLibrarySongWithResolver(
        song,
        supportDirPath,
        resolverFor(prodManifest()),
        fileExists: (path) => path == '$supportDirPath/Music/song.opus',
      );

      expect(rewritten, isNotNull);
      expect(rewritten!['url'], '$supportDirPath/Music/song.opus');
    });

    test('skips remote urls even with a resolver present', () {
      final song = <dynamic, dynamic>{
        'videoId': 'video-id',
        'url': 'https://example.com/watch?v=x',
      };

      final rewritten = rewriteRestoredLibrarySongWithResolver(
        song,
        supportDirPath,
        resolverFor(prodManifest()),
        fileExists: (_) => true,
      );

      expect(rewritten, isNull);
    });

    test('keeps entry and strips dead path when nothing resolves', () {
      final song = <dynamic, dynamic>{
        'videoId': 'video-id',
        'url': '$prodMusicDir/song.opus',
      };

      final rewritten = rewriteRestoredLibrarySongWithResolver(
        song,
        supportDirPath,
        resolverFor(prodManifest()),
        fileExists: (_) => false,
      );

      expect(rewritten, isNotNull);
      expect(rewritten!.containsKey('url'), isFalse);
      expect(rewritten['videoId'], 'video-id');
    });
  });

  group('restore service manifest wiring source checks', () {
    late String serviceSource;

    setUpAll(() {
      serviceSource =
          File('lib/services/backup/restore_service.dart').readAsStringSync();
    });

    test('manifest entry is consumed in memory and never extracted', () {
      expect(serviceSource, contains('_readManifest(archive)'));
      expect(serviceSource, contains('backupManifestMaxBytes'));
      // Skipped in both the progress total and the extraction loop.
      expect(
        serviceSource,
        contains('file.isFile && !_isManifestEntry(file.name)'),
      );
      expect(
        serviceSource,
        contains('if (!file.isFile || _isManifestEntry(file.name)) continue;'),
      );
    });

    test('both rewrite phases receive the resolver', () {
      final resolverIndex = serviceSource.indexOf('RestorePathResolver(');
      expect(resolverIndex, greaterThan(-1));
      expect(
        RegExp('resolver: resolver').allMatches(serviceSource).length,
        2,
      );
    });
  });
}

Map<dynamic, dynamic> _song(String path) {
  return {
    'videoId': 'video-id',
    'url': path,
    'streamInfo': [
      true,
      {'url': path}
    ],
  };
}
