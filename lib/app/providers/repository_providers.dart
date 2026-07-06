import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/hive_download_repository.dart';
import '../../data/repositories/hive_home_repository.dart';
import '../../data/repositories/hive_library_repository.dart';
import '../../data/repositories/hive_lyrics_repository.dart';
import '../../data/repositories/hive_playback_session_repository.dart';
import '../../data/repositories/hive_playlist_repository.dart';
import '../../data/repositories/hive_search_history_repository.dart';
import '../../data/repositories/hive_settings_repository.dart';
import '../../data/repositories/hive_song_cache_repository.dart';
import '../../data/repositories/hive_storage_admin_repository.dart';
import '../../domain/repositories/download_repository.dart';
import '../../domain/repositories/home_repository.dart';
import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/lyrics_repository.dart';
import '../../domain/repositories/playback_session_repository.dart';
import '../../domain/repositories/playlist_repository.dart';
import '../../domain/repositories/search_history_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/repositories/song_cache_repository.dart';
import '../../domain/repositories/storage_admin_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => HiveSettingsRepository(),
);

final playlistRepositoryProvider = Provider<PlaylistRepository>(
  (ref) => HivePlaylistRepository(),
);

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => HiveLibraryRepository(),
);

final downloadRepositoryProvider = Provider<DownloadRepository>(
  (ref) => HiveDownloadRepository(),
);

final songCacheRepositoryProvider = Provider<SongCacheRepository>(
  (ref) => HiveSongCacheRepository(),
);

final homeRepositoryProvider = Provider<HomeRepository>(
  (ref) => HiveHomeRepository(),
);

final playbackSessionRepositoryProvider = Provider<PlaybackSessionRepository>(
  (ref) => HivePlaybackSessionRepository(),
);

final searchHistoryRepositoryProvider = Provider<SearchHistoryRepository>(
  (ref) => HiveSearchHistoryRepository(),
);

final lyricsRepositoryProvider = Provider<LyricsRepository>(
  (ref) => HiveLyricsRepository(),
);

final storageAdminRepositoryProvider = Provider<StorageAdminRepository>(
  (ref) => HiveStorageAdminRepository(),
);
