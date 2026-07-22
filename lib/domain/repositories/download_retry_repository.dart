import 'package:audio_service/audio_service.dart';

abstract class DownloadRetryRepository {
  int get count;
  List<MediaItem> getAll();
  Future<void> remember(MediaItem song);
  Future<void> remove(String songId);
}
