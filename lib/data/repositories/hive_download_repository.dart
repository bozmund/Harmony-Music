import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

import '../../domain/repositories/download_repository.dart';
import '../../models/media_Item_builder.dart';
import '../../services/constant.dart';

class HiveDownloadRepository implements DownloadRepository {
  Box get _box => Hive.box(BoxNames.songDownloads);

  @override
  Future<bool> containsDownload(String songId) async =>
      _box.containsKey(songId);

  @override
  Future<dynamic> getDownloadJson(String songId) async => _box.get(songId);

  @override
  Future<Map<dynamic, dynamic>> getAllDownloadJsonEntries() async =>
      Map<dynamic, dynamic>.from(_box.toMap());

  @override
  Future<MediaItem?> getDownloadedSong(String songId) async {
    final value = _box.get(songId);
    return value == null ? null : MediaItemBuilder.fromJson(value);
  }

  @override
  Future<void> saveDownloadedSong(MediaItem song) =>
      _box.put(song.id, MediaItemBuilder.toJson(song));

  @override
  Future<void> saveDownloadedSongJson(
    String songId,
    Map<String, dynamic> json,
  ) => _box.put(songId, json);

  @override
  Future<void> deleteDownloadedSong(String songId) => _box.delete(songId);

  @override
  Future<List<String>> getDownloadedSongFilePaths() async => _box.values
      .map((item) => item is Map ? item['url'] : null)
      .whereType<String>()
      .toList();

  @override
  Future<void> updateDownloadedSongJson(
    String songId,
    Map<String, dynamic> json,
  ) => _box.put(songId, json);
}
