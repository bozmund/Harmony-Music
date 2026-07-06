import 'package:audio_service/audio_service.dart';

abstract class PlaybackSessionRepository {
  Future<List<MediaItem>> getQueue();
  Future<int?> getIndex();
  Future<int?> getPosition();
  Future<void> saveSession({
    required List<MediaItem> queue,
    required int index,
    required int position,
  });
  Future<void> clearSession();

  /// Applies [transform] to every song JSON map in the saved session queue.
  /// A null return leaves the entry unchanged. Used after a backup restore
  /// to fix absolute file paths persisted by another install.
  Future<void> rewriteQueueEntries(
    Map<dynamic, dynamic>? Function(Map<dynamic, dynamic> song) transform,
  );
}
