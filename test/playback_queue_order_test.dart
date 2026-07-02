import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/playback_queue_order.dart';

void main() {
  test('shuffle keeps current song first and preserves original list', () {
    final queue = [_song('a'), _song('b'), _song('c'), _song('d')];

    final shuffled = PlaybackQueueOrder.shuffledFromCurrent(
      queue,
      2,
      random: Random(1),
    );

    expect(shuffled.first.id, 'c');
    expect(shuffled.map((song) => song.id).toSet(), {'a', 'b', 'c', 'd'});
    expect(queue.map((song) => song.id), ['a', 'b', 'c', 'd']);
  });

  test('shuffle handles invalid indices by returning the original order', () {
    final queue = [_song('a'), _song('b')];

    final shuffled = PlaybackQueueOrder.shuffledFromCurrent(queue, 99);

    expect(shuffled.map((song) => song.id), ['a', 'b']);
    expect(identical(shuffled, queue), isFalse);
  });

  test('indexOfSongId finds current song in restored queue', () {
    final queue = [_song('a'), _song('b'), _song('c')];

    expect(PlaybackQueueOrder.indexOfSongId(queue, 'b'), 1);
    expect(PlaybackQueueOrder.indexOfSongId(queue, 'missing'), -1);
  });
}

MediaItem _song(String id) => MediaItem(id: id, title: 'Song $id');
