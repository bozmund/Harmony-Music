import '../../services/constant.dart';
import '../../services/resolver/resolver_source_mode.dart';
import '../../utils/helper.dart';

abstract class SettingsRepository {
  String getLanguageCode();
  Future<void> setLanguageCode(String value);
  UpdateChannel getUpdateChannel();
  Future<void> setUpdateChannel(UpdateChannel value);

  /// Whether the one-time release prompt with [promptId] was already
  /// answered by the user (see lib/services/release_prompt.dart).
  bool isReleasePromptAnswered(String promptId);
  Future<void> setReleasePromptAnswered(String promptId);
  bool getNewVersionVisibility(bool fallback);
  Future<void> setNewVersionVisibility(bool enabled);
  bool getCacheSongs();
  Future<void> setCacheSongs(bool value);
  bool getSkipSilenceEnabled();
  Future<void> setSkipSilenceEnabled(bool value);
  bool getLoudnessNormalizationEnabled();
  Future<void> setLoudnessNormalizationEnabled(bool value);
  int getStreamingQualityIndex();
  Future<void> setStreamingQualityIndex(int value);
  int getThemeModeType();
  Future<void> setThemeModeType(int value);
  int getThemePrimaryColor();
  Future<void> setThemePrimaryColor(int value);
  String getDiscoverContentType();
  Future<void> setDiscoverContentType(String value);
  bool getQueueLoopModeEnabled();
  Future<void> setQueueLoopModeEnabled(bool value);
  bool getLoopModeEnabled();
  Future<void> setLoopModeEnabled(bool value);
  bool getShuffleModeEnabled();
  Future<void> setShuffleModeEnabled(bool value);
  int getVolume({int defaultValue = 100});
  Future<void> setVolume(int value);
  bool getBottomNavBarEnabled();
  Future<void> setBottomNavBarEnabled(bool value);
  int getNoOfHomeScreenContent();
  Future<void> setNoOfHomeScreenContent(int value);
  bool getTransitionAnimationDisabled();
  Future<void> setTransitionAnimationDisabled(bool value);
  bool getAutoOpenPlayer();
  Future<void> setAutoOpenPlayer(bool value);
  bool getRestorePlaybackSession();
  Future<void> setRestorePlaybackSession(bool value);
  bool getCacheHomeScreenData();
  Future<void> setCacheHomeScreenData(bool value);
  bool getDeveloperSettingsEnabled();
  Future<void> setDeveloperSettingsEnabled(bool value);
  bool getResolverEnabled();
  Future<void> setResolverEnabled(bool value);
  ResolverSourceMode getResolverSourceMode();
  Future<void> setResolverSourceMode(ResolverSourceMode value);
  String? getResolverDebugOverride();
  Future<void> setResolverDebugOverride(String? value);
  String? getResolverProductionOverride();
  Future<void> setResolverProductionOverride(String? value);
  int getPlaybackModeIndex();
  PlaybackMode getPlaybackMode();
  Future<void> setPlaybackMode(PlaybackMode mode);
  int getPlaybackPreloadRange();
  Future<void> setPlaybackPreloadRange(int value);
  int getPlayerUi();
  Future<void> setPlayerUi(int value);
  int getLyricsMode();
  Future<void> setLyricsMode(int value);
  bool getBackgroundPlayEnabled();
  Future<void> setBackgroundPlayEnabled(bool value);
  bool getKeepScreenAwake(bool fallback);
  Future<void> setKeepScreenAwake(bool value);
  String? getDownloadLocationPath();
  Future<void> setDownloadLocationPath(String value);

  /// Clears the stored download location so the app's default applies again.
  /// Used after a restore when the restored value points at a directory this
  /// install cannot use (e.g. another package's private storage).
  Future<void> resetDownloadLocationPath();
  String getExportLocationPath();
  Future<void> setExportLocationPath(String value);

  /// Clears the stored export location; see [resetDownloadLocationPath].
  Future<void> resetExportLocationPath();
  String getDownloadingFormat();
  Future<void> setDownloadingFormat(String value);
  bool getSlidableActionEnabled();
  Future<void> setSlidableActionEnabled(bool value);
  bool getAutoDownloadFavoriteSongEnabled();
  Future<void> setAutoDownloadFavoriteSongEnabled(bool value);
  int getLibraryFirstTab();
  Future<void> setLibraryFirstTab(int value);
  bool getBatteryOptimizationPromptShown();
  Future<void> setBatteryOptimizationPromptShown(bool value);
  Map<dynamic, dynamic>? getPiped();
  Future<void> setPiped(Map<dynamic, dynamic> value);
  Future<void> deletePiped();
  String? getVisitorId();
  Map<dynamic, dynamic>? getVisitorData();
  Future<void> setVisitorData(Map<dynamic, dynamic> value);
  String getContentLanguage();
  bool getStopPlaybackOnSwipeAway();
  Future<void> setStopPlaybackOnSwipeAway(bool value);
  int? getHomeScreenDataTime();
  Future<void> setHomeScreenDataTime(int value);
  Future<void> deleteHomeScreenDataTime();
  String? getRecentSongId();
  Future<void> setRecentSongId(String songId);
  Future<void> seedDefaults(bool updateCheckFlag);
  Future<void> clearAll();
  Map<String, dynamic> developerValues();
}
