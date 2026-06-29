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
}
