import 'package:audio_service/audio_service.dart';

import '../../models/hm_streaming_data.dart';

abstract class SongCacheRepository {
  Future<bool> containsCachedSong(String songId);
  Future<MediaItem?> getCachedSong(String songId);
  Future<dynamic> getCachedSongJson(String songId);
  Future<void> saveCachedSong(MediaItem song);
  Future<void> saveCachedSongJson(String songId, Map<String, dynamic> json);
  Future<void> deleteCachedSong(String songId);
  Future<dynamic> getStreamCacheEntry(String songId);
  Future<HMStreamingData?> getStreamInfo(String songId, int qualityIndex);
  Future<void> saveStreamCacheEntry(String songId, dynamic value);
  Future<void> deleteStreamCacheEntry(String songId);
  Future<void> clearStreamCache();
  Future<Map<String, dynamic>> getAllStreamCacheEntries();
}
