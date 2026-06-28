abstract class HomeRepository {
  Future<dynamic> getHomeData(String key);
  Future<void> setHomeData(String key, dynamic value);
  Future<void> clearHomeData();
  Future<Map<dynamic, dynamic>> getAllHomeData();
}
