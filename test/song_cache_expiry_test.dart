import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/domain/repositories/song_cache_repository.dart';
import 'package:harmonymusic/utils/house_keeping.dart';
import 'package:harmonymusic/utils/song_cache_storage.dart';

void main() {
  late Directory root;
  late _RecordingSongCache cache;

  setUp(() {
    root = Directory.systemTemp.createTempSync('song_cache_expiry');
    cache = _RecordingSongCache();
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File seed(String name, {required Duration age}) {
    final file = File('${root.path}/$name')..writeAsStringSync('audio');
    file.setLastModifiedSync(DateTime.now().subtract(age));
    return file;
  }

  group('removeExpiredCachedAudio', () {
    test('drops audio unplayed past the cutoff, entry and all', () async {
      final stale = seed('old.mp3', age: const Duration(days: 40));

      await removeExpiredCachedAudio(
        songCacheRepository: cache,
        cacheDirectory: root,
      );

      expect(stale.existsSync(), isFalse);
      // The Hive entry has to go with the file. Removing one without the other
      // is exactly what left entries pointing at audio that was no longer
      // there, which is the failure this whole pass exists to end.
      expect(cache.deleted, ['old']);
    });

    test('keeps audio played inside the cutoff', () async {
      final fresh = seed('recent.mp3', age: const Duration(days: 3));

      await removeExpiredCachedAudio(
        songCacheRepository: cache,
        cacheDirectory: root,
      );

      expect(fresh.existsSync(), isTrue);
      expect(cache.deleted, isEmpty);
    });

    test('a sidecar cannot outlive the audio it belongs to', () async {
      // LockCachingAudioSource leaves .part and .mime beside the .mp3. Ageing
      // them independently would strand a half-written part file forever.
      final audio = seed('song.mp3', age: const Duration(days: 40));
      final part = seed('song.part', age: const Duration(days: 40));
      final mime = seed('song.mime', age: const Duration(days: 40));

      await removeExpiredCachedAudio(
        songCacheRepository: cache,
        cacheDirectory: root,
      );

      expect(audio.existsSync(), isFalse);
      expect(part.existsSync(), isFalse);
      expect(mime.existsSync(), isFalse);
      expect(cache.deleted, ['song']);
    });

    test('a recently played song keeps its stale sidecar alive', () async {
      // Age is taken from the newest file in the group: the .mp3 is what gets
      // touched on playback, so a long-untouched sidecar must not drag a song
      // that is still in use out of the cache.
      final audio = seed('song.mp3', age: const Duration(days: 1));
      final part = seed('song.part', age: const Duration(days: 40));

      await removeExpiredCachedAudio(
        songCacheRepository: cache,
        cacheDirectory: root,
      );

      expect(audio.existsSync(), isTrue);
      expect(part.existsSync(), isTrue);
      expect(cache.deleted, isEmpty);
    });

    test('the cutoff is driven by maxAge', () async {
      final file = seed('song.mp3', age: const Duration(days: 10));

      await removeExpiredCachedAudio(
        songCacheRepository: cache,
        cacheDirectory: root,
        maxAge: const Duration(days: 7),
      );

      expect(file.existsSync(), isFalse);
    });

    test('a missing cache directory is not an error', () async {
      final absent = Directory('${root.path}/gone');

      await expectLater(
        removeExpiredCachedAudio(
          songCacheRepository: cache,
          cacheDirectory: absent,
        ),
        completes,
      );
    });
  });

  group('migrateLegacySongCache', () {
    late Directory from;
    late Directory to;

    setUp(() {
      from = Directory('${root.path}/legacy')..createSync();
      to = Directory('${root.path}/durable')..createSync();
    });

    test('carries cached audio across, then removes the old home', () async {
      File('${from.path}/song.mp3').writeAsStringSync('audio');
      File('${from.path}/song.mime').writeAsStringSync('audio/mpeg');

      final moved = await migrateLegacySongCache(from: from, to: to);

      expect(moved, 2);
      expect(File('${to.path}/song.mp3').existsSync(), isTrue);
      expect(File('${to.path}/song.mime').existsSync(), isTrue);
      // Without this the move itself would empty the Songs list on first
      // launch - the exact failure it exists to prevent.
      expect(from.existsSync(), isFalse);
    });

    test('running again moves nothing', () async {
      File('${from.path}/song.mp3').writeAsStringSync('audio');

      await migrateLegacySongCache(from: from, to: to);
      final second = await migrateLegacySongCache(from: from, to: to);

      expect(second, 0);
      expect(File('${to.path}/song.mp3').existsSync(), isTrue);
    });

    test('an interrupted run does not overwrite the copy in use', () async {
      File('${from.path}/song.mp3').writeAsStringSync('stale');
      File('${to.path}/song.mp3').writeAsStringSync('in use');

      await migrateLegacySongCache(from: from, to: to);

      expect(File('${to.path}/song.mp3').readAsStringSync(), 'in use');
      expect(File('${from.path}/song.mp3').existsSync(), isFalse);
    });

    test('no legacy directory is not an error', () async {
      final absent = Directory('${root.path}/never-existed');

      expect(await migrateLegacySongCache(from: absent, to: to), 0);
    });
  });

  group('cache reads keep a song alive', () {
    test('both cache-hit paths touch the file', () {
      final handler = File(
        'lib/services/audio_handler.dart',
      ).readAsStringSync();

      // LockCachingAudioSource writes the file once, so without this a song
      // played every day still expires 30 days after it was first cached.
      expect(
        '_markCachedAudioPlayed('.allMatches(handler).length,
        3,
        reason: 'the preload path, the playback path, and the declaration',
      );
      expect(handler, contains('file.setLastModified(DateTime.now())'));
    });

    test('cached audio no longer lives in the temporary directory', () {
      final handler = File(
        'lib/services/audio_handler.dart',
      ).readAsStringSync();
      final library = File(
        'lib/ui/screens/Library/library_controller.dart',
      ).readAsStringSync();

      expect(handler, isNot(contains(r'$_cacheDir/cachedSongs')));
      expect(library, isNot(contains('getTemporaryDirectory()).path;')));
      // Preload prefixes are re-fetched on demand and stay in temp.
      expect(handler, contains(r'Directory("$_cacheDir/preloadedSongs")'));
    });
  });
}

class _RecordingSongCache implements SongCacheRepository {
  final List<String> deleted = <String>[];

  @override
  Future<void> deleteCachedSong(String songId) async => deleted.add(songId);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}
