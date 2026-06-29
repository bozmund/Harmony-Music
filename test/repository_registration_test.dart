import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/data/repositories/hive_repository_registration.dart';
import 'package:harmonymusic/domain/repositories/download_repository.dart';
import 'package:harmonymusic/domain/repositories/home_repository.dart';
import 'package:harmonymusic/domain/repositories/library_repository.dart';
import 'package:harmonymusic/domain/repositories/lyrics_repository.dart';
import 'package:harmonymusic/domain/repositories/playback_session_repository.dart';
import 'package:harmonymusic/domain/repositories/playlist_repository.dart';
import 'package:harmonymusic/domain/repositories/search_history_repository.dart';
import 'package:harmonymusic/domain/repositories/settings_repository.dart';
import 'package:harmonymusic/domain/repositories/song_cache_repository.dart';
import 'package:harmonymusic/domain/repositories/storage_admin_repository.dart';

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
