import 'package:get/get.dart';

import '../../domain/repositories/repositories.dart';
import 'hive_download_repository.dart';
import 'hive_home_repository.dart';
import 'hive_library_repository.dart';
import 'hive_lyrics_repository.dart';
import 'hive_playback_session_repository.dart';
import 'hive_playlist_repository.dart';
import 'hive_search_history_repository.dart';
import 'hive_settings_repository.dart';
import 'hive_song_cache_repository.dart';
import 'hive_storage_admin_repository.dart';

void registerHiveRepositories() {
  if (!Get.isRegistered<SettingsRepository>()) {
    Get.lazyPut<SettingsRepository>(
      () => HiveSettingsRepository(),
      fenix: true,
    );
  }
  if (!Get.isRegistered<PlaylistRepository>()) {
    Get.lazyPut<PlaylistRepository>(
      () => HivePlaylistRepository(),
      fenix: true,
    );
  }
  if (!Get.isRegistered<LibraryRepository>()) {
    Get.lazyPut<LibraryRepository>(() => HiveLibraryRepository(), fenix: true);
  }
  if (!Get.isRegistered<DownloadRepository>()) {
    Get.lazyPut<DownloadRepository>(
      () => HiveDownloadRepository(),
      fenix: true,
    );
  }
  if (!Get.isRegistered<SongCacheRepository>()) {
    Get.lazyPut<SongCacheRepository>(
      () => HiveSongCacheRepository(),
      fenix: true,
    );
  }
  if (!Get.isRegistered<HomeRepository>()) {
    Get.lazyPut<HomeRepository>(() => HiveHomeRepository(), fenix: true);
  }
  if (!Get.isRegistered<PlaybackSessionRepository>()) {
    Get.lazyPut<PlaybackSessionRepository>(
      () => HivePlaybackSessionRepository(),
      fenix: true,
    );
  }
  if (!Get.isRegistered<SearchHistoryRepository>()) {
    Get.lazyPut<SearchHistoryRepository>(
      () => HiveSearchHistoryRepository(),
      fenix: true,
    );
  }
  if (!Get.isRegistered<LyricsRepository>()) {
    Get.lazyPut<LyricsRepository>(() => HiveLyricsRepository(), fenix: true);
  }
  if (!Get.isRegistered<StorageAdminRepository>()) {
    Get.lazyPut<StorageAdminRepository>(
      () => HiveStorageAdminRepository(),
      fenix: true,
    );
  }
}
