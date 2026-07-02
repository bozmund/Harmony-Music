import 'dart:math';

import 'package:audio_service/audio_service.dart';

class PlaybackQueueOrder {
  const PlaybackQueueOrder._();

  static List<MediaItem> shuffledFromCurrent(
    List<MediaItem> queue,
    int currentIndex, {
    Random? random,
  }) {
    if (queue.isEmpty || currentIndex < 0 || currentIndex >= queue.length) {
      return List<MediaItem>.from(queue);
    }

    final reorderedQueue = List<MediaItem>.from(queue);
    final currentItem = reorderedQueue.removeAt(currentIndex);
    reorderedQueue.shuffle(random);
    return <MediaItem>[currentItem, ...reorderedQueue];
  }

  static int indexOfSongId(List<MediaItem> queue, String songId) {
    return queue.indexWhere((item) => item.id == songId);
  }
}
