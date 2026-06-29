import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/data/repositories/hive_download_repository.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory hiveDir;
  late HiveDownloadRepository repository;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('download_repo_test_');
    Hive.init(hiveDir.path);
    await Hive.openBox(BoxNames.songDownloads);
    repository = HiveDownloadRepository();
  });

  tearDown(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  test('downloaded song stream info round trips with local file url', () async {
    const filePath = '/storage/emulated/0/Music/Song (Artist).m4a';
    final sourceSong = MediaItem(
      id: 'song-1',
      title: 'Song',
      artist: 'Artist',
      artUri: Uri.parse('https://example.test/art.jpg'),
      extras: const {
        'album': null,
        'artists': [
          {'name': 'Artist'},
        ],
        'length': '3:00',
        'date': 123,
        'url': 'https://example.test/stream.m4a',
      },
    );
    final songJson = MediaItemBuilder.toJson(sourceSong)
      ..['url'] = filePath
      ..['streamInfo'] = [
        true,
        {
          'itag': 140,
          'audioCodec': 'mp4a',
          'bitrate': 128000,
          'loudnessDb': -4.5,
          'duration': 180000,
          'size': 1000,
          'url': filePath,
        },
      ];

    await repository.saveDownloadedSongJson(sourceSong.id, songJson);

    final raw = await repository.getDownloadJson(sourceSong.id) as Map;
    final streamInfo = raw['streamInfo'] as List;
    expect(raw['url'], filePath);
    expect((streamInfo[1] as Map)['url'], filePath);

    final downloadedSong = await repository.getDownloadedSong(sourceSong.id);
    expect(downloadedSong, isNotNull);
    expect(downloadedSong!.id, sourceSong.id);
    expect(downloadedSong.extras!['url'], filePath);
  });
}
