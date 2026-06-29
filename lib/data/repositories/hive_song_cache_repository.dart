import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

import '../../domain/repositories/song_cache_repository.dart';
import '../../models/hm_streaming_data.dart';
import '../../models/media_Item_builder.dart';
import '../../services/constant.dart';
import '../../services/stream_service.dart' show Audio;

class HiveSongCacheRepository implements SongCacheRepository {
  Box get _songsBox => Hive.box(BoxNames.songsCache);

  Box get _streamsBox => Hive.box(BoxNames.songsUrlCache);

  @override
  Future<bool> containsCachedSong(String songId) async =>
      _songsBox.containsKey(songId);

  @override
  Future<MediaItem?> getCachedSong(String songId) async {
    final value = _songsBox.get(songId);
    return value == null ? null : MediaItemBuilder.fromJson(value);
  }

  @override
  Future<dynamic> getCachedSongJson(String songId) async =>
      _songsBox.get(songId);

  @override
  Future<void> saveCachedSong(MediaItem song) =>
      _songsBox.put(song.id, MediaItemBuilder.toJson(song));

  @override
  Future<void> saveCachedSongJson(String songId, Map<String, dynamic> json) =>
      _songsBox.put(songId, json);

  @override
  Future<void> deleteCachedSong(String songId) => _songsBox.delete(songId);

  @override
  Future<dynamic> getStreamCacheEntry(String songId) async =>
      _streamsBox.get(songId);

  @override
  Future<HMStreamingData?> getStreamInfo(
    String songId,
    int qualityIndex,
  ) async {
    final entry = _streamsBox.get(songId);
    final streamInfo = _streamInfoFromCacheEntry(entry, qualityIndex);
    return streamInfo?..setQualityIndex(qualityIndex);
  }

  @override
  Future<void> saveStreamCacheEntry(String songId, dynamic value) =>
      _streamsBox.put(songId, value);

  @override
  Future<void> deleteStreamCacheEntry(String songId) =>
      _streamsBox.delete(songId);

  @override
  Future<void> clearStreamCache() => _streamsBox.clear();

  @override
  Future<Map<String, dynamic>> getAllStreamCacheEntries() async =>
      Map<String, dynamic>.fromEntries(
        _streamsBox.keys.whereType<String>().map(
          (key) => MapEntry(key, _streamsBox.get(key)),
        ),
      );
}

HMStreamingData? _streamInfoFromCacheEntry(dynamic entry, int qualityIndex) {
  if (entry is Map) {
    final playable = entry['playable'] == true;
    if (!playable) {
      return HMStreamingData(
        playable: false,
        statusMSG: entry['statusMSG']?.toString() ?? '',
      );
    }

    final selectedAudioJson = qualityIndex == 0
        ? entry['lowQualityAudio']
        : entry['highQualityAudio'];
    if (selectedAudioJson is! Map) return null;

    final lowQualityAudio = _audioFromJson(entry['lowQualityAudio']);
    final highQualityAudio = _audioFromJson(entry['highQualityAudio']);
    if (qualityIndex == 0 && lowQualityAudio == null) return null;
    if (qualityIndex != 0 && highQualityAudio == null) return null;

    return HMStreamingData(
      playable: true,
      statusMSG: entry['statusMSG']?.toString() ?? 'OK',
      lowQualityAudio: lowQualityAudio,
      highQualityAudio: highQualityAudio,
    );
  }

  if (entry is List && entry.length > qualityIndex) {
    final audio = _audioFromJson(entry[qualityIndex]);
    if (audio == null) return null;
    return HMStreamingData(
      playable: true,
      statusMSG: 'OK',
      lowQualityAudio: qualityIndex == 0 ? audio : null,
      highQualityAudio: qualityIndex == 0 ? null : audio,
    );
  }

  return null;
}

Audio? _audioFromJson(dynamic value) {
  if (value is! Map) return null;
  try {
    return Audio.fromJson(value);
  } catch (_) {
    return null;
  }
}
