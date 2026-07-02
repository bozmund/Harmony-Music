import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/backup/restore_path_rewriter.dart';

void main() {
  group('rewriteRestoredDownloadSong', () {
    const supportDirPath = '/app/support';

    test('rewrites Android-style download path to restored Music path', () {
      final song = _song('/storage/emulated/0/Music/song.m4a');

      final rewritten = rewriteRestoredDownloadSong(
        song,
        supportDirPath,
        fileExists: (path) => path == '/app/support/Music/song.m4a',
      );

      expect(rewritten, isNotNull);
      expect(rewritten!['url'], '/app/support/Music/song.m4a');
      expect(rewritten['streamInfo'][1]['url'], '/app/support/Music/song.m4a');
    });

    test('rewrites Windows-style download path to restored Music path', () {
      final song = _song(r'C:\Users\me\Music\song.m4a');

      final rewritten = rewriteRestoredDownloadSong(
        song,
        supportDirPath,
        fileExists: (path) => path == '/app/support/Music/song.m4a',
      );

      expect(rewritten, isNotNull);
      expect(rewritten!['url'], '/app/support/Music/song.m4a');
      expect(rewritten['streamInfo'][1]['url'], '/app/support/Music/song.m4a');
    });

    test('rewrites Linux-style opus download path to restored Music path', () {
      final song = _song('/home/me/Music/song.opus');

      final rewritten = rewriteRestoredDownloadSong(
        song,
        supportDirPath,
        fileExists: (path) => path == '/app/support/Music/song.opus',
      );

      expect(rewritten, isNotNull);
      expect(rewritten!['url'], '/app/support/Music/song.opus');
      expect(rewritten['streamInfo'][1]['url'], '/app/support/Music/song.opus');
    });

    test(
        'keeps original path when restored file is missing but original exists',
        () {
      final song = _song('/home/me/Music/song.opus');

      final rewritten = rewriteRestoredDownloadSong(
        song,
        supportDirPath,
        fileExists: (path) => path == '/home/me/Music/song.opus',
      );

      expect(rewritten, isNotNull);
      expect(rewritten!['url'], '/home/me/Music/song.opus');
      expect(rewritten['streamInfo'][1]['url'], '/home/me/Music/song.opus');
    });

    test(
        'keeps entry but strips dead path when neither restored nor original '
        'file exists', () {
      final song = _song('/home/me/Music/song.opus');

      final rewritten = rewriteRestoredDownloadSong(
        song,
        supportDirPath,
        fileExists: (_) => false,
      );

      expect(rewritten, isNotNull);
      expect(rewritten!.containsKey('url'), isFalse);
      expect(rewritten.containsKey('streamInfo'), isFalse);
      expect(rewritten['videoId'], 'video-id');
    });

    test('leaves already-stripped entries unchanged', () {
      final song = _song('/home/me/Music/song.opus')
        ..remove('url')
        ..remove('streamInfo');

      final rewritten = rewriteRestoredDownloadSong(
        song,
        supportDirPath,
        fileExists: (_) => false,
      );

      expect(rewritten, isNull);
    });

    test('uses streamInfo url when top-level url is missing', () {
      final song = _song('/home/me/Music/song.opus')..remove('url');

      final rewritten = rewriteRestoredDownloadSong(
        song,
        supportDirPath,
        fileExists: (path) => path == '/app/support/Music/song.opus',
      );

      expect(rewritten, isNotNull);
      expect(rewritten!['url'], '/app/support/Music/song.opus');
      expect(rewritten['streamInfo'][1]['url'], '/app/support/Music/song.opus');
    });
  });

  group('restoredFileName', () {
    test('extracts names across platform path styles', () {
      expect(
          restoredFileName('/storage/emulated/0/Music/song.m4a'), 'song.m4a');
      expect(restoredFileName(r'C:\Users\me\Music\song.m4a'), 'song.m4a');
      expect(restoredFileName('/home/me/Music/song.opus'), 'song.opus');
    });
  });
}

Map<String, dynamic> _song(String path) {
  return {
    'videoId': 'video-id',
    'url': path,
    'streamInfo': [
      true,
      {'url': path}
    ],
  };
}
