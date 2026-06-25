import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/hm_streaming_data.dart';
import 'package:harmonymusic/services/playback_preload_manager.dart';
import 'package:harmonymusic/services/stream_service.dart';

void main() {
  group('isPreloadableNetworkUrl', () {
    test('accepts HTTP and HTTPS URLs with hosts', () {
      expect(isPreloadableNetworkUrl('https://example.com/song.opus'), isTrue);
      expect(isPreloadableNetworkUrl('http://example.com/song.opus'), isTrue);
    });

    test('rejects local, file, empty, and hostless URLs', () {
      expect(
        isPreloadableNetworkUrl('/data/user/0/app/files/Music/song.opus'),
        isFalse,
      );
      expect(
        isPreloadableNetworkUrl(
          'file:///data/user/0/app/files/Music/song.opus',
        ),
        isFalse,
      );
      expect(isPreloadableNetworkUrl(''), isFalse);
      expect(isPreloadableNetworkUrl('https:///song.opus'), isFalse);
      expect(isPreloadableNetworkUrl('relative/song.opus'), isFalse);
      expect(isPreloadableNetworkUrl('ftp://example.com/song.opus'), isFalse);
      expect(isPreloadableNetworkUrl('HTTPS://example.com/song.opus'), isTrue);
    });
  });

  group('PlaybackPreloadManager', () {
    late Directory preloadDirectory;

    setUp(() async {
      preloadDirectory = await Directory.systemTemp.createTemp(
        'harmony_preload_test_',
      );
    });

    tearDown(() async {
      if (await preloadDirectory.exists()) {
        await preloadDirectory.delete(recursive: true);
      }
    });

    test('skips local download paths without creating prefix files', () async {
      final manager = PlaybackPreloadManager(
        preloadDirectory: preloadDirectory,
        resolveStreamInfo:
            (
              songId, {
              generateNewUrl = false,
              offlineReplacementUrl = false,
            }) async => _streamInfo('/data/user/0/app/files/Music/song.opus'),
      );
      await manager.init();

      await manager.update(
        queue: const [MediaItem(id: 'local-song', title: 'Local song')],
        candidateIndices: const [0],
        range: 1,
        isPlaying: true,
        currentIndex: null,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await preloadDirectory.list().toList(), isEmpty);
    });

    test('does not resolve the currently playing song', () async {
      var resolveCount = 0;
      final manager = PlaybackPreloadManager(
        preloadDirectory: preloadDirectory,
        resolveStreamInfo:
            (
              songId, {
              generateNewUrl = false,
              offlineReplacementUrl = false,
            }) async {
              resolveCount++;
              return _streamInfo('https://example.test/$songId.opus');
            },
      );
      await manager.init();

      await manager.update(
        queue: const [MediaItem(id: 'current-song', title: 'Current song')],
        candidateIndices: const [0],
        range: 1,
        isPlaying: true,
        currentIndex: 0,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(resolveCount, 0);
      expect(await preloadDirectory.list().toList(), isEmpty);
    });

    test(
      'clears queued prefixes when disabled by range or playback state',
      () async {
        final stalePrefix = File('${preloadDirectory.path}/stale.prefix');
        await stalePrefix.writeAsString('stale');
        final manager = PlaybackPreloadManager(
          preloadDirectory: preloadDirectory,
          resolveStreamInfo:
              (
                songId, {
                generateNewUrl = false,
                offlineReplacementUrl = false,
              }) async => _streamInfo('https://example.test/$songId.opus'),
        );
        await manager.init();

        await manager.update(
          queue: const [MediaItem(id: 'song', title: 'Song')],
          candidateIndices: const [0],
          range: 0,
          isPlaying: true,
          currentIndex: null,
        );

        expect(await stalePrefix.exists(), isFalse);

        await stalePrefix.writeAsString('stale');
        await manager.update(
          queue: const [MediaItem(id: 'song', title: 'Song')],
          candidateIndices: const [0],
          range: 1,
          isPlaying: false,
          currentIndex: null,
        );

        expect(await stalePrefix.exists(), isFalse);
      },
    );

    test('does not create prefix files for non-playable stream info', () async {
      final manager = PlaybackPreloadManager(
        preloadDirectory: preloadDirectory,
        resolveStreamInfo:
            (
              songId, {
              generateNewUrl = false,
              offlineReplacementUrl = false,
            }) async => HMStreamingData(playable: false, statusMSG: 'Nope'),
      );
      await manager.init();

      await manager.update(
        queue: const [MediaItem(id: 'bad-song', title: 'Bad song')],
        candidateIndices: const [0],
        range: 1,
        isPlaying: true,
        currentIndex: null,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await preloadDirectory.list().toList(), isEmpty);
    });
  });
}

HMStreamingData _streamInfo(String url) {
  final audio = Audio(
    itag: 140,
    audioCodec: Codec.opus,
    bitrate: 160000,
    duration: 180000,
    loudnessDb: 0,
    url: url,
    size: 0,
  );

  return HMStreamingData(
    playable: true,
    statusMSG: 'OK',
    lowQualityAudio: audio,
    highQualityAudio: audio,
  );
}
