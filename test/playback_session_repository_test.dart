import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/data/repositories/hive_playback_session_repository.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory hiveDir;
  late HivePlaybackSessionRepository repository;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('playback_session_test_');
    Hive.init(hiveDir.path);
    await Hive.openBox(BoxNames.prevSessionData);
    repository = HivePlaybackSessionRepository();
  });

  tearDown(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  test('returns empty state when nothing was saved', () async {
    expect(await repository.getQueue(), isEmpty);
    expect(await repository.getIndex(), isNull);
    expect(await repository.getPosition(), isNull);
  });

  test('saveSession round-trips queue, index, and position', () async {
    await repository.saveSession(
      queue: [_song('song-1'), _song('song-2'), _song('song-3')],
      index: 2,
      position: 45250,
    );

    final queue = await repository.getQueue();
    expect(queue.map((item) => item.id), ['song-1', 'song-2', 'song-3']);
    expect(queue[2].title, 'Title song-3');
    expect(await repository.getIndex(), 2);
    expect(await repository.getPosition(), 45250);
  });

  test(
    'savePosition updates index and position without touching the queue',
    () async {
      await repository.saveSession(
        queue: [_song('song-1'), _song('song-2'), _song('song-3')],
        index: 0,
        position: 0,
      );

      await repository.savePosition(index: 2, position: 91000);

      expect(await repository.getIndex(), 2);
      expect(await repository.getPosition(), 91000);
      final queue = await repository.getQueue();
      expect(queue.map((item) => item.id), ['song-1', 'song-2', 'song-3']);
    },
  );

  test('clearSession removes everything', () async {
    await repository.saveSession(
      queue: [_song('song-1')],
      index: 0,
      position: 5,
    );
    await repository.clearSession();

    expect(await repository.getQueue(), isEmpty);
    expect(await repository.getIndex(), isNull);
    expect(await repository.getPosition(), isNull);
  });
}

MediaItem _song(String id) => MediaItem(
  id: id,
  title: 'Title $id',
  artUri: Uri.parse('https://example.test/$id.jpg'),
  extras: {
    'url': 'https://example.test/$id.mp3',
    'length': null,
    'album': null,
    'artists': null,
    'date': null,
    'trackDetails': null,
    'year': null,
  },
);
