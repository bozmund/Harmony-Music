import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/data/repositories/hive_app_repositories.dart';
import 'package:harmonymusic/domain/repositories/repositories.dart';

void main() {
  tearDown(Get.reset);

  test('registerHiveRepositories registers every repository contract', () {
    registerHiveRepositories();

    expect(Get.isRegistered<SettingsRepository>(), isTrue);
    expect(Get.isRegistered<PlaylistRepository>(), isTrue);
    expect(Get.isRegistered<LibraryRepository>(), isTrue);
    expect(Get.isRegistered<DownloadRepository>(), isTrue);
    expect(Get.isRegistered<SongCacheRepository>(), isTrue);
    expect(Get.isRegistered<HomeRepository>(), isTrue);
    expect(Get.isRegistered<PlaybackSessionRepository>(), isTrue);
    expect(Get.isRegistered<SearchHistoryRepository>(), isTrue);
    expect(Get.isRegistered<LyricsRepository>(), isTrue);
    expect(Get.isRegistered<StorageAdminRepository>(), isTrue);
  });
}
