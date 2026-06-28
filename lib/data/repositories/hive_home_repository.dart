import 'package:hive/hive.dart';

import '../../domain/repositories/home_repository.dart';
import '../../services/constant.dart';

class HiveHomeRepository implements HomeRepository {
  Future<Box> get _box => Hive.openBox(BoxNames.homeScreenData);

  @override
  Future<dynamic> getHomeData(String key) async => (await _box).get(key);

  @override
  Future<void> setHomeData(String key, dynamic value) async =>
      (await _box).put(key, value);

  @override
  Future<void> clearHomeData() async => (await _box).clear();

  @override
  Future<Map<dynamic, dynamic>> getAllHomeData() async {
    final box = await _box;
    return Map<dynamic, dynamic>.fromEntries(
      box.keys.map((key) => MapEntry(key, box.get(key))),
    );
  }
}
