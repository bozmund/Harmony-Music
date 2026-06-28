import 'package:hive/hive.dart';

import '../../domain/repositories/lyrics_repository.dart';

class HiveLyricsRepository implements LyricsRepository {
  Future<Box> get _box => Hive.openBox('lyrics');

  @override
  Future<dynamic> getLyrics(String key) async => (await _box).get(key);

  @override
  Future<void> saveLyrics(String key, dynamic lyrics) async =>
      (await _box).put(key, lyrics);
}
