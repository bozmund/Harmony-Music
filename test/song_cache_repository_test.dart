import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/data/repositories/hive_song_cache_repository.dart';
import 'package:harmonymusic/models/hm_streaming_data.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:harmonymusic/services/stream_service.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory hiveDir;
  late HiveSongCacheRepository repository;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('song_cache_repo_test_');
    Hive.init(hiveDir.path);
    await Hive.openBox(BoxNames.songsCache);
    await Hive.openBox(BoxNames.songsUrlCache);
    repository = HiveSongCacheRepository();
  });

  tearDown(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  test('reads map-shaped stream cache entries', () async {
    await repository.saveStreamCacheEntry(
      'song-1',
      HMStreamingData(
        playable: true,
        statusMSG: 'OK',
        lowQualityAudio: _audio('https://example.test/low', bitrate: 64000),
        highQualityAudio: _audio('https://example.test/high', bitrate: 160000),
      ).toJson(),
    );

    final low = await repository.getStreamInfo('song-1', 0);
    final high = await repository.getStreamInfo('song-1', 1);

    expect(low, isNotNull);
    expect(low!.audio!.url, 'https://example.test/low');
    expect(low.audio!.bitrate, 64000);
    expect(high, isNotNull);
    expect(high!.audio!.url, 'https://example.test/high');
    expect(high.audio!.bitrate, 160000);
  });

  test('returns null for malformed stream cache entries', () async {
    await repository.saveStreamCacheEntry('song-1', {
      'playable': true,
      'statusMSG': 'OK',
      'lowQualityAudio': {'bitrate': 64000},
      'highQualityAudio': 'bad',
    });

    expect(await repository.getStreamInfo('song-1', 0), isNull);
    expect(await repository.getStreamInfo('song-1', 1), isNull);
  });

  test('keeps best-effort support for legacy list entries', () async {
    await repository.saveStreamCacheEntry('song-1', [
      _audio('https://example.test/low', bitrate: 64000).toJson(),
      _audio('https://example.test/high', bitrate: 160000).toJson(),
    ]);

    final streamInfo = await repository.getStreamInfo('song-1', 1);

    expect(streamInfo, isNotNull);
    expect(streamInfo!.audio!.url, 'https://example.test/high');
  });
}

Audio _audio(String url, {required int bitrate}) {
  return Audio(
    itag: bitrate == 64000 ? 249 : 251,
    audioCodec: Codec.opus,
    bitrate: bitrate,
    duration: 180000,
    loudnessDb: -3.2,
    url: url,
    size: 1024,
  );
}
