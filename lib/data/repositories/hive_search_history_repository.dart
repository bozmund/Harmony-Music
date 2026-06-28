import 'package:hive/hive.dart';

import '../../domain/repositories/search_history_repository.dart';
import 'hive_repository_helpers.dart';

class HiveSearchHistoryRepository implements SearchHistoryRepository {
  Future<Box> get _box => Hive.openBox('searchQuery');

  @override
  Future<List<String>> getQueries() async =>
      (await _box).values.whereType<String>().toList();

  @override
  Future<void> addQuery(String query, {int? maxEntries}) async {
    final box = await _box;
    if (maxEntries != null && box.length >= maxEntries) {
      await box.deleteAt(0);
    }
    if (!box.values.contains(query)) await box.add(query);
  }

  @override
  Future<void> deleteQuery(String query) async {
    final box = await _box;
    final key = box.keys.firstWhereOrNull((key) => box.get(key) == query);
    if (key != null) await box.delete(key);
  }
}
