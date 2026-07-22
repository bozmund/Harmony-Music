import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

import '../../domain/repositories/download_retry_repository.dart';
import '../../models/media_Item_builder.dart';
import '../../services/constant.dart';

/// Persists songs whose local download failed so the user can retry the whole
/// set later. Successful downloads remove their own pending retry entry.
class HiveDownloadRetryRepository implements DownloadRetryRepository {
  Box get _box => Hive.box(BoxNames.downloadFailures);

  @override
  int get count => _box.length;

  @override
  List<MediaItem> getAll() => _box.values
      .whereType<Map>()
      .map((value) => MediaItemBuilder.fromJson(value))
      .toList(growable: false);

  @override
  Future<void> remember(MediaItem song) =>
      _box.put(song.id, MediaItemBuilder.toJson(song));

  @override
  Future<void> remove(String songId) => _box.delete(songId);
}
