import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:harmonymusic/data/repositories/hive_download_retry_repository.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory hiveDir;
  late HiveDownloadRetryRepository store;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('download_retry_test_');
    Hive.init(hiveDir.path);
    await Hive.openBox(BoxNames.downloadFailures);
    store = HiveDownloadRetryRepository();
  });

  tearDown(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  test('keeps failed songs until their retry succeeds', () async {
    final song = MediaItem(
      id: 'jNQXAC9IVRw',
      title: 'Retry me',
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

    await store.remember(song);

    expect(store.count, 1);
    expect(store.getAll().single.id, song.id);

    await store.remove(song.id);
    expect(store.count, 0);
  });
}
