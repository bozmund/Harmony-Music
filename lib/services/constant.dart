const domain = "https://music.youtube.com/";
const String baseUrl = '${domain}youtubei/v1/';
const fixedParms =
    '?prettyPrint=false&alt=json&key=AI'
    'zaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';
const userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36';

const List<String> libraryTabKeys = [
  "songs",
  "searches",
  "playlists",
  "albums",
  "artists",
];

class BoxNames {
  static const String appPrefs = 'AppPrefs';
  static const String songDownloads = 'SongDownloads';
  static const String songsCache = 'SongsCache';
  static const String prevSessionData = 'prevSessionData';
  static const String homeScreenData = 'homeScreenData';
  static const String libFav = 'LIBFAV';
  static const String libFavNotDownloaded = 'LIBFAV_NOT_DOWNLOADED';
  static const String libImportDuplicates = 'LIBIMPORT_DUPLICATES';
  static const String libImportReview = 'LIBIMPORT_REVIEW';
  static const String libRP = 'LIBRP';
  static const String libraryPlaylists = 'LibraryPlaylists';
  static const String libraryAlbums = 'LibraryAlbums';
  static const String libraryArtists = 'LibraryArtists';
  static const String librarySearches = 'LibrarySearches';
  static const String songsUrlCache = 'SongsUrlCache';
  static const String blacklistedPlaylist = 'blacklistedPlaylist';
  static const String searchQuery = 'searchQuery';
  static const String lyrics = 'lyrics';
}

class PrefKeys {
  static const String isLoopModeEnabled = 'isLoopModeEnabled';
  static const String isShuffleModeEnabled = 'isShuffleModeEnabled';
  static const String queueLoopModeEnabled = 'queueLoopModeEnabled';
  static const String volume = 'volume';
  static const String streamingQuality = 'streamingQuality';
  static const String playerUi = 'playerUi';
  static const String lyricsMode = 'lyricsMode';
  static const String restorePlaybackSession = 'restorePlaybackSession';
  static const String discoverContentType = 'discoverContentType';
  static const String autoOpenPlayer = 'autoOpenPlayer';
  static const String isBottomNavBarEnabled = 'isBottomNavBarEnabled';
  static const String noOfHomeScreenContent = 'noOfHomeScreenContent';
  static const String isTransitionAnimationDisabled =
      'isTransitionAnimationDisabled';
  static const String skipSilenceEnabled = 'skipSilenceEnabled';
  static const String loudnessNormalizationEnabled =
      'loudnessNormalizationEnabled';
  static const String cacheHomeScreenData = 'cacheHomeScreenData';
  static const String backgroundPlayEnabled = 'backgroundPlayEnabled';
  static const String keepScreenAwake = 'keepScreenAwake';
  static const String exportLocationPath = 'exportLocationPath';
  static const String downloadLocationPath = 'downloadLocationPath';
  static const String downloadingFormat = 'downloadingFormat';
  static const String piped = 'piped';
  static const String autoDownloadFavoriteSongEnabled =
      'autoDownloadFavoriteSongEnabled';
  static const String slidableActionEnabled = 'slidableActionEnabled';
  static const String cacheSongs = 'cacheSongs';
  static const String homeScreenDataTime = 'homeScreenDataTime';
  static const String recentSongId = 'recentSongId';
  static const String newVersionVisibility = 'newVersionVisibility';
  static const String visitorId = 'visitorId';
  static const String themePrimaryColor = 'themePrimaryColor';
  static const String themeModeType = 'themeModeType';
  static const String currentAppLanguageCode = 'currentAppLanguageCode';
  static const String libraryFirstTab = 'libraryFirstTab';
  static const String updateChannel = 'updateChannel';
  static const String answeredReleasePrompts = 'answeredReleasePrompts';
  static const String batteryOptimizationPromptShown =
      'batteryOptimizationPromptShown';
  static const String playbackMode = 'playbackMode';
  static const String playbackPreloadRange = 'playbackPreloadRange';
  static const String developerSettingsEnabled = 'developerSettingsEnabled';
  static const String resolverEnabled = 'resolverEnabled';
  static const String resolverDebugOverride = 'resolverDebugOverride';
  static const String resolverProductionOverride = 'resolverProductionOverride';
  static const String listenTogetherDeviceName = 'listenTogetherDeviceName';
  static const String listenTogetherTransport = 'listenTogetherTransport';
}

enum PlaybackMode { classic, preloaded }

class BuildInfo {
  static const String channel = String.fromEnvironment(
    'BUILD_CHANNEL',
    defaultValue: 'stable',
  );
  static const String version = String.fromEnvironment('BUILD_VERSION');
  static const String sha = String.fromEnvironment('BUILD_SHA');
}

class LogTags {
  static const String home = 'Home';
  static const String player = 'Player';
  static const String downloader = 'Downloader';
  static const String musicService = 'MusicService';
  static const String library = 'Library';
  static const String settings = 'Settings';
  static const String theme = 'Theme';
  static const String audioHandler = 'AudioHandler';
  static const String piped = 'Piped';
  static const String backup = 'Backup';
  static const String preload = 'Preload';
  static const String listenTogether = 'ListenTogether';
}
