import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/backup/restore_path_rewriter.dart';

void main() {
  group('rewriteRestoredLibrarySong', () {
    const supportDirPath = '/app/support';

    test('rewrites cross-package path when restored file exists', () {
      final song = _librarySong(
          '/data/user/0/com.anandnet.harmonymusic.prod/files/Music/song.opus');

      final rewritten = rewriteRestoredLibrarySong(
        song,
        supportDirPath,
        fileExists: (path) => path == '/app/support/Music/song.opus',
      );

      expect(rewritten, isNotNull);
      expect(rewritten!['url'], '/app/support/Music/song.opus');
      expect(rewritten['videoId'], 'video-id');
    });

    test('rewrites streamInfo url too when present', () {
      final song = _librarySong('/home/me/Music/song.m4a')
        ..['streamInfo'] = [
          true,
          {'url': '/home/me/Music/song.m4a'}
        ];

      final rewritten = rewriteRestoredLibrarySong(
        song,
        supportDirPath,
        fileExists: (path) => path == '/app/support/Music/song.m4a',
      );

      expect(rewritten, isNotNull);
      expect(rewritten!['url'], '/app/support/Music/song.m4a');
      expect(rewritten['streamInfo'][1]['url'], '/app/support/Music/song.m4a');
    });

    test('leaves entry unchanged when original file still exists', () {
      final song = _librarySong('/home/me/Music/song.opus');

      final rewritten = rewriteRestoredLibrarySong(
        song,
        supportDirPath,
        fileExists: (path) => path == '/home/me/Music/song.opus',
      );

      expect(rewritten, isNull);
    });

    test('leaves entry unchanged when url already points at restored file',
        () {
      final song = _librarySong('/app/support/Music/song.opus');

      final rewritten = rewriteRestoredLibrarySong(
        song,
        supportDirPath,
        fileExists: (path) => path == '/app/support/Music/song.opus',
      );

      expect(rewritten, isNull);
    });

    test('keeps entry but strips dead local path when no file exists', () {
      final song = _librarySong(
          '/data/user/0/com.anandnet.harmonymusic.prod/files/Music/song.opus')
        ..['streamInfo'] = [
          true,
          {
            'url':
                '/data/user/0/com.anandnet.harmonymusic.prod/files/Music/song.opus'
          }
        ];

      final rewritten = rewriteRestoredLibrarySong(
        song,
        supportDirPath,
        fileExists: (_) => false,
      );

      expect(rewritten, isNotNull);
      expect(rewritten!.containsKey('url'), isFalse);
      expect(rewritten.containsKey('streamInfo'), isFalse);
      expect(rewritten['videoId'], 'video-id');
      expect(rewritten['title'], 'title');
    });

    test('leaves remote urls unchanged', () {
      final song = _librarySong('https://example.com/stream/song');

      final rewritten = rewriteRestoredLibrarySong(
        song,
        supportDirPath,
        fileExists: (_) => true,
      );

      expect(rewritten, isNull);
    });

    test('leaves entries without any url unchanged', () {
      final song = _librarySong('/home/me/Music/song.opus')..remove('url');

      final rewritten = rewriteRestoredLibrarySong(
        song,
        supportDirPath,
        fileExists: (_) => false,
      );

      expect(rewritten, isNull);
    });

    test('ignores non-map values', () {
      expect(
        rewriteRestoredLibrarySong('not-a-map', supportDirPath,
            fileExists: (_) => true),
        isNull,
      );
    });
  });

  group('restore pipeline source checks', () {
    late String restoreDialogSource;
    late String restoreServiceSource;
    late String rewriterSource;
    late String audioHandlerSource;
    late String houseKeepingSource;

    setUpAll(() {
      restoreDialogSource =
          File('lib/ui/widgets/restore_dialog.dart').readAsStringSync();
      restoreServiceSource =
          File('lib/services/backup/restore_service.dart').readAsStringSync();
      rewriterSource =
          File('lib/services/backup/restore_path_rewriter.dart')
              .readAsStringSync();
      audioHandlerSource =
          File('lib/services/audio_handler.dart').readAsStringSync();
      houseKeepingSource =
          File('lib/utils/house_keeping.dart').readAsStringSync();
    });

    test('restore never deletes download entries', () {
      for (final source in [
        restoreDialogSource,
        restoreServiceSource,
        rewriterSource,
      ]) {
        expect(
          source.contains('deleteDownloadedSong'),
          isFalse,
          reason: 'Restored downloads with missing files must be kept '
              '(with their dead path stripped), not deleted, so the library '
              'song list survives a cross-package restore.',
        );
      }
    });

    test('house keeping skips download entries without a url', () {
      // Stripped restore entries rely on this skip to survive house keeping.
      final skipIndex =
          houseKeepingSource.indexOf('if (songUrl is! String) continue;');
      final deleteIndex =
          houseKeepingSource.indexOf('deleteDownloadedSong(songKey)');

      expect(skipIndex, greaterThan(-1));
      expect(deleteIndex, greaterThan(skipIndex));
    });

    test('downloaded stream info falls back when the entry has no url', () {
      final methodStart = audioHandlerSource
          .indexOf('Future<HMStreamingData?> _downloadedStreamInfoForSong(');
      expect(methodStart, greaterThan(-1));

      final methodBody = audioHandlerSource.substring(
        methodStart,
        audioHandlerSource.indexOf('_isLocalSourceUrl(String url)',
            methodStart),
      );
      expect(
        methodBody,
        contains("if (path is! String || path.isEmpty) return null;"),
      );
    });

    test('restore rewrites library paths after download paths', () {
      final downloadRewriteIndex =
          restoreServiceSource.indexOf('await rewriteRestoredDownloadPaths(');
      final libraryRewriteIndex =
          restoreServiceSource.indexOf('await rewriteRestoredLibraryPaths(');

      expect(downloadRewriteIndex, greaterThan(-1));
      expect(libraryRewriteIndex, greaterThan(downloadRewriteIndex));
    });

    test('library rewrite covers library, playlist and session repositories',
        () {
      expect(
        rewriterSource,
        contains('libraryRepository.rewriteSongEntries(transform)'),
      );
      expect(
        rewriterSource,
        contains('playlistRepository.rewritePlaylistSongEntries(transform)'),
      );
      expect(
        rewriterSource,
        contains('playbackSessionRepository.rewriteQueueEntries(transform)'),
      );
    });

    test(
        '_offlineStreamInfoForSong checks file existence before building '
        'local stream info', () {
      final methodStart = audioHandlerSource
          .indexOf('Future<HMStreamingData?> _offlineStreamInfoForSong(');
      expect(methodStart, greaterThan(-1));

      final methodEnd = audioHandlerSource.indexOf(
        'Future<bool> _localSourceFileExists(',
        methodStart,
      );
      expect(methodEnd, greaterThan(methodStart));

      final methodBody = audioHandlerSource.substring(methodStart, methodEnd);
      final guardIndex = methodBody.indexOf('_localSourceFileExists(url)');
      final localStreamIndex =
          methodBody.indexOf('_streamInfoFromLocalUrl(song, url)');

      expect(guardIndex, greaterThan(-1));
      expect(localStreamIndex, greaterThan(guardIndex));
    });

    test('_localSourceFileExists resolves file:// urls and checks the disk',
        () {
      final helperStart =
          audioHandlerSource.indexOf('Future<bool> _localSourceFileExists(');
      expect(helperStart, greaterThan(-1));

      final helperBody = audioHandlerSource.substring(
        helperStart,
        audioHandlerSource.indexOf('}', helperStart) + 1,
      );
      expect(helperBody, contains('uri.toFilePath()'));
      expect(
        audioHandlerSource.substring(helperStart),
        contains('File(path).exists()'),
      );
    });
  });
}

Map<dynamic, dynamic> _librarySong(String path) {
  return {
    'videoId': 'video-id',
    'title': 'title',
    'url': path,
  };
}
