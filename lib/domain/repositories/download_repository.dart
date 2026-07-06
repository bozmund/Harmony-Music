import 'package:audio_service/audio_service.dart';

abstract class DownloadRepository {
  Future<bool> containsDownload(String songId);
  Future<dynamic> getDownloadJson(String songId);
  Future<Map<dynamic, dynamic>> getAllDownloadJsonEntries();
  Future<MediaItem?> getDownloadedSong(String songId);
  Future<void> saveDownloadedSong(MediaItem song);
  Future<void> saveDownloadedSongJson(String songId, Map<String, dynamic> json);
  Future<void> deleteDownloadedSong(String songId);
  Future<List<String>> getDownloadedSongFilePaths();
  Future<void> updateDownloadedSongJson(
    String songId,
    Map<String, dynamic> json,
  );
}
