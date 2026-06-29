abstract class SearchHistoryRepository {
  Future<List<String>> getQueries();
  Future<void> addQuery(String query, {int? maxEntries});
  Future<void> deleteQuery(String query);
}
