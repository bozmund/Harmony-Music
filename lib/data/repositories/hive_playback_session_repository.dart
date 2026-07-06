import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

import '../../domain/repositories/playback_session_repository.dart';
import '../../models/media_Item_builder.dart';
import '../../services/constant.dart';

class HivePlaybackSessionRepository implements PlaybackSessionRepository {
  Future<Box> get _box => Hive.openBox(BoxNames.prevSessionData);

  @override
  Future<List<MediaItem>> getQueue() async {
    final raw = (await _box).get('queue');
    if (raw is! List) return [];
    return raw
        .map<MediaItem?>((item) => MediaItemBuilder.fromJson(item))
        .whereType<MediaItem>()
        .toList();
  }

  @override
  Future<int?> getIndex() async => (await _box).get('index');

  @override
  Future<int?> getPosition() async => (await _box).get('position');

  @override
  Future<void> saveSession({
    required List<MediaItem> queue,
    required int index,
    required int position,
  }) async {
    final box = await _box;
    await box.put('queue', queue.map(MediaItemBuilder.toJson).toList());
    await box.put('index', index);
    await box.put('position', position);
  }

  @override
  Future<void> clearSession() async => (await _box).clear();

  @override
  Future<void> rewriteQueueEntries(
    Map<dynamic, dynamic>? Function(Map<dynamic, dynamic> song) transform,
  ) async {
    final box = await _box;
    final raw = box.get('queue');
    if (raw is! List) return;
    var changed = false;
    final rewrittenQueue = raw.map((item) {
      if (item is! Map) return item;
      final rewritten = transform(item);
      if (rewritten == null) return item;
      changed = true;
      return rewritten;
    }).toList();
    if (changed) {
      await box.put('queue', rewrittenQueue);
    }
  }
}
