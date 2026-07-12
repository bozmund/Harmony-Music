import 'dart:async';

import 'package:hive/hive.dart';

import '../../domain/repositories/settings_repository.dart';
import '../../services/constant.dart';
import '../../utils/helper.dart';

class HiveSettingsRepository implements SettingsRepository {
  Box get _box => Hive.box(BoxNames.appPrefs);

  @override
  String getLanguageCode() => _box.get(PrefKeys.currentAppLanguageCode) ?? 'en';

  @override
  Future<void> setLanguageCode(String value) =>
      _box.put(PrefKeys.currentAppLanguageCode, value);

  @override
  UpdateChannel getUpdateChannel() =>
      (_box.get(PrefKeys.updateChannel) ?? 'stable') == 'rolling'
      ? UpdateChannel.rolling
      : UpdateChannel.stable;

  @override
  Future<void> setUpdateChannel(UpdateChannel value) =>
      _box.put(PrefKeys.updateChannel, value.name);

  @override
  bool isReleasePromptAnswered(String promptId) {
    final answered = _box.get(PrefKeys.answeredReleasePrompts);
    return answered is List && answered.contains(promptId);
  }

  @override
  Future<void> setReleasePromptAnswered(String promptId) async {
    final answered = _box.get(PrefKeys.answeredReleasePrompts);
    final ids = answered is List ? List<dynamic>.from(answered) : <dynamic>[];
    if (ids.contains(promptId)) return;
    ids.add(promptId);
    await _box.put(PrefKeys.answeredReleasePrompts, ids);
  }

  @override
  bool getNewVersionVisibility(bool fallback) =>
      _box.get(PrefKeys.newVersionVisibility) ?? fallback;

  @override
  Future<void> setNewVersionVisibility(bool enabled) =>
      _box.put(PrefKeys.newVersionVisibility, enabled);

  @override
  bool getCacheSongs() => _box.get(PrefKeys.cacheSongs) ?? false;

  @override
  Future<void> setCacheSongs(bool value) =>
      _box.put(PrefKeys.cacheSongs, value);

  @override
  bool getSkipSilenceEnabled() =>
      _box.get(PrefKeys.skipSilenceEnabled) ?? false;

  @override
  Future<void> setSkipSilenceEnabled(bool value) =>
      _box.put(PrefKeys.skipSilenceEnabled, value);

  @override
  bool getLoudnessNormalizationEnabled() =>
      _box.get(PrefKeys.loudnessNormalizationEnabled) ?? false;

  @override
  Future<void> setLoudnessNormalizationEnabled(bool value) =>
      _box.put(PrefKeys.loudnessNormalizationEnabled, value);

  @override
  int getStreamingQualityIndex() => _box.get(PrefKeys.streamingQuality) ?? 1;

  @override
  Future<void> setStreamingQualityIndex(int value) =>
      _box.put(PrefKeys.streamingQuality, value);

  @override
  int getThemeModeType() => _box.get(PrefKeys.themeModeType) ?? 0;

  @override
  Future<void> setThemeModeType(int value) =>
      _box.put(PrefKeys.themeModeType, value);

  @override
  int getThemePrimaryColor() =>
      _box.get(PrefKeys.themePrimaryColor) ?? 4278199603;

  @override
  Future<void> setThemePrimaryColor(int value) =>
      _box.put(PrefKeys.themePrimaryColor, value);

  @override
  String getDiscoverContentType() =>
      _box.get(PrefKeys.discoverContentType) ?? 'BOLI';

  @override
  Future<void> setDiscoverContentType(String value) =>
      _box.put(PrefKeys.discoverContentType, value);

  @override
  bool getQueueLoopModeEnabled() =>
      _box.get(PrefKeys.queueLoopModeEnabled) ?? true;

  @override
  Future<void> setQueueLoopModeEnabled(bool value) =>
      _box.put(PrefKeys.queueLoopModeEnabled, value);

  @override
  bool getLoopModeEnabled() => _box.get(PrefKeys.isLoopModeEnabled) ?? false;

  @override
  Future<void> setLoopModeEnabled(bool value) =>
      _box.put(PrefKeys.isLoopModeEnabled, value);

  @override
  bool getShuffleModeEnabled() =>
      _box.get(PrefKeys.isShuffleModeEnabled) ?? false;

  @override
  Future<void> setShuffleModeEnabled(bool value) =>
      _box.put(PrefKeys.isShuffleModeEnabled, value);

  @override
  int getVolume({int defaultValue = 100}) =>
      _box.get(PrefKeys.volume, defaultValue: defaultValue);

  @override
  Future<void> setVolume(int value) => _box.put(PrefKeys.volume, value);

  @override
  bool getBottomNavBarEnabled() =>
      _box.get(PrefKeys.isBottomNavBarEnabled) ?? true;

  @override
  Future<void> setBottomNavBarEnabled(bool value) =>
      _box.put(PrefKeys.isBottomNavBarEnabled, value);

  @override
  int getNoOfHomeScreenContent() =>
      _box.get(PrefKeys.noOfHomeScreenContent) ?? 3;

  @override
  Future<void> setNoOfHomeScreenContent(int value) =>
      _box.put(PrefKeys.noOfHomeScreenContent, value);

  @override
  bool getTransitionAnimationDisabled() =>
      _box.get(PrefKeys.isTransitionAnimationDisabled) ?? false;

  @override
  Future<void> setTransitionAnimationDisabled(bool value) =>
      _box.put(PrefKeys.isTransitionAnimationDisabled, value);

  @override
  bool getAutoOpenPlayer() => _box.get(PrefKeys.autoOpenPlayer) ?? true;

  @override
  Future<void> setAutoOpenPlayer(bool value) =>
      _box.put(PrefKeys.autoOpenPlayer, value);

  @override
  bool getRestorePlaybackSession() =>
      _box.get(PrefKeys.restorePlaybackSession) ?? false;

  @override
  Future<void> setRestorePlaybackSession(bool value) =>
      _box.put(PrefKeys.restorePlaybackSession, value);

  @override
  bool getCacheHomeScreenData() =>
      _box.get(PrefKeys.cacheHomeScreenData) ?? true;

  @override
  Future<void> setCacheHomeScreenData(bool value) =>
      _box.put(PrefKeys.cacheHomeScreenData, value);

  @override
  bool getDeveloperSettingsEnabled() =>
      _box.get(PrefKeys.developerSettingsEnabled) ?? false;

  @override
  Future<void> setDeveloperSettingsEnabled(bool value) =>
      _box.put(PrefKeys.developerSettingsEnabled, value);

  @override
  bool getResolverEnabled() => _box.get(PrefKeys.resolverEnabled) ?? true;

  @override
  Future<void> setResolverEnabled(bool value) =>
      _box.put(PrefKeys.resolverEnabled, value);

  @override
  String? getResolverDebugOverride() =>
      _box.get(PrefKeys.resolverDebugOverride) as String?;

  @override
  Future<void> setResolverDebugOverride(String? value) => value == null
      ? _box.delete(PrefKeys.resolverDebugOverride)
      : _box.put(PrefKeys.resolverDebugOverride, value);

  @override
  String? getResolverProductionOverride() =>
      _box.get(PrefKeys.resolverProductionOverride) as String?;

  @override
  Future<void> setResolverProductionOverride(String? value) => value == null
      ? _box.delete(PrefKeys.resolverProductionOverride)
      : _box.put(PrefKeys.resolverProductionOverride, value);

  @override
  int getPlaybackModeIndex() => _box.get(PrefKeys.playbackMode) ?? 0;

  @override
  PlaybackMode getPlaybackMode() {
    final value = getPlaybackModeIndex();
    if (value >= 0 && value < PlaybackMode.values.length) {
      return PlaybackMode.values[value];
    }
    return PlaybackMode.classic;
  }

  @override
  Future<void> setPlaybackMode(PlaybackMode mode) =>
      _box.put(PrefKeys.playbackMode, mode.index);

  @override
  int getPlaybackPreloadRange() {
    final value = _box.get(PrefKeys.playbackPreloadRange) ?? 0;
    return value is int ? value.clamp(0, 5).toInt() : 0;
  }

  @override
  Future<void> setPlaybackPreloadRange(int value) =>
      _box.put(PrefKeys.playbackPreloadRange, value.clamp(0, 5).toInt());

  @override
  int getPlayerUi() => _box.get(PrefKeys.playerUi) ?? 0;

  @override
  Future<void> setPlayerUi(int value) => _box.put(PrefKeys.playerUi, value);

  @override
  int getLyricsMode() => _box.get(PrefKeys.lyricsMode) ?? 0;

  @override
  Future<void> setLyricsMode(int value) => _box.put(PrefKeys.lyricsMode, value);

  @override
  bool getBackgroundPlayEnabled() =>
      _box.get(PrefKeys.backgroundPlayEnabled) ?? true;

  @override
  Future<void> setBackgroundPlayEnabled(bool value) =>
      _box.put(PrefKeys.backgroundPlayEnabled, value);

  @override
  bool getKeepScreenAwake(bool fallback) =>
      _box.get(PrefKeys.keepScreenAwake) ?? fallback;

  @override
  Future<void> setKeepScreenAwake(bool value) =>
      _box.put(PrefKeys.keepScreenAwake, value);

  @override
  String? getDownloadLocationPath() => _box.get(PrefKeys.downloadLocationPath);

  @override
  Future<void> setDownloadLocationPath(String value) =>
      _box.put(PrefKeys.downloadLocationPath, value);

  @override
  Future<void> resetDownloadLocationPath() =>
      _box.delete(PrefKeys.downloadLocationPath);

  @override
  String getExportLocationPath() =>
      _box.get(PrefKeys.exportLocationPath) ?? '/storage/emulated/0/Music';

  @override
  Future<void> setExportLocationPath(String value) =>
      _box.put(PrefKeys.exportLocationPath, value);

  @override
  Future<void> resetExportLocationPath() =>
      _box.delete(PrefKeys.exportLocationPath);

  @override
  String getDownloadingFormat() =>
      _box.get(PrefKeys.downloadingFormat) ?? 'opus';

  @override
  Future<void> setDownloadingFormat(String value) =>
      _box.put(PrefKeys.downloadingFormat, value);

  @override
  bool getSlidableActionEnabled() =>
      _box.get(PrefKeys.slidableActionEnabled) ?? true;

  @override
  Future<void> setSlidableActionEnabled(bool value) =>
      _box.put(PrefKeys.slidableActionEnabled, value);

  @override
  bool getAutoDownloadFavoriteSongEnabled() =>
      _box.get(PrefKeys.autoDownloadFavoriteSongEnabled) ?? false;

  @override
  Future<void> setAutoDownloadFavoriteSongEnabled(bool value) =>
      _box.put(PrefKeys.autoDownloadFavoriteSongEnabled, value);

  @override
  int getLibraryFirstTab() => _box.get(PrefKeys.libraryFirstTab) is int
      ? _box.get(PrefKeys.libraryFirstTab)
      : 0;

  @override
  Future<void> setLibraryFirstTab(int value) =>
      _box.put(PrefKeys.libraryFirstTab, value);

  @override
  bool getBatteryOptimizationPromptShown() =>
      _box.get(PrefKeys.batteryOptimizationPromptShown) ?? false;

  @override
  Future<void> setBatteryOptimizationPromptShown(bool value) =>
      _box.put(PrefKeys.batteryOptimizationPromptShown, value);

  @override
  Map<dynamic, dynamic>? getPiped() {
    final value = _box.get(PrefKeys.piped);
    return value is Map ? value : null;
  }

  @override
  Future<void> setPiped(Map<dynamic, dynamic> value) =>
      _box.put(PrefKeys.piped, value);

  @override
  Future<void> deletePiped() => _box.delete(PrefKeys.piped);

  @override
  String? getVisitorId() => _box.get(PrefKeys.visitorId);

  @override
  Map<dynamic, dynamic>? getVisitorData() {
    final value = _box.get(PrefKeys.visitorId);
    return value is Map ? value : null;
  }

  @override
  Future<void> setVisitorData(Map<dynamic, dynamic> value) =>
      _box.put(PrefKeys.visitorId, value);

  @override
  String getContentLanguage() => _box.get('contentLanguage') ?? 'en';

  @override
  bool getStopPlaybackOnSwipeAway() =>
      _box.get('stopPlaybackOnSwipeAway') ?? false;

  @override
  Future<void> setStopPlaybackOnSwipeAway(bool value) =>
      _box.put('stopPlaybackOnSwipeAway', value);

  @override
  int? getHomeScreenDataTime() => _box.get(PrefKeys.homeScreenDataTime);

  @override
  Future<void> setHomeScreenDataTime(int value) =>
      _box.put(PrefKeys.homeScreenDataTime, value);

  @override
  Future<void> deleteHomeScreenDataTime() =>
      _box.delete(PrefKeys.homeScreenDataTime);

  @override
  String? getRecentSongId() => _box.get(PrefKeys.recentSongId);

  @override
  Future<void> setRecentSongId(String songId) =>
      _box.put(PrefKeys.recentSongId, songId);

  @override
  Future<void> seedDefaults(bool updateCheckFlag) async {
    if (_box.isEmpty) {
      await _box.putAll({
        PrefKeys.themeModeType: 0,
        PrefKeys.cacheSongs: false,
        PrefKeys.skipSilenceEnabled: false,
        PrefKeys.streamingQuality: 1,
        PrefKeys.themePrimaryColor: 4278199603,
        PrefKeys.discoverContentType: 'BOLI',
        PrefKeys.newVersionVisibility: updateCheckFlag,
        PrefKeys.updateChannel: 'rolling',
        PrefKeys.cacheHomeScreenData: true,
        PrefKeys.queueLoopModeEnabled: true,
        PrefKeys.isBottomNavBarEnabled: true,
        PrefKeys.downloadingFormat: 'opus',
        PrefKeys.batteryOptimizationPromptShown: false,
        PrefKeys.playbackMode: PlaybackMode.classic.index,
        PrefKeys.playbackPreloadRange: 0,
      });
    }
    if (!_box.containsKey(PrefKeys.queueLoopModeEnabled)) {
      unawaited(_box.put(PrefKeys.queueLoopModeEnabled, true));
    }
    if (!_box.containsKey(PrefKeys.batteryOptimizationPromptShown)) {
      unawaited(_box.put(PrefKeys.batteryOptimizationPromptShown, true));
    }
    if (!_box.containsKey(PrefKeys.playbackMode)) {
      unawaited(_box.put(PrefKeys.playbackMode, PlaybackMode.classic.index));
    }
    if (!_box.containsKey(PrefKeys.playbackPreloadRange)) {
      unawaited(_box.put(PrefKeys.playbackPreloadRange, 0));
    }
  }

  @override
  Future<void> clearAll() => _box.clear();

  @override
  Map<String, dynamic> developerValues() => Map<String, dynamic>.fromEntries(
    _box.keys.map((key) => MapEntry(key.toString(), _box.get(key))),
  );
}
