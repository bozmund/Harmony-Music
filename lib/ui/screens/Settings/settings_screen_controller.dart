import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:audio_service/audio_service.dart';
import '../../../domain/repositories/playlist_repository.dart';
import '../../../domain/repositories/settings_repository.dart';
import '../../../domain/repositories/storage_admin_repository.dart';
import '/services/file_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:harmonymusic/l10n/l10n.dart';
import 'package:harmonymusic/services/app_platform_service.dart';
import 'package:harmonymusic/services/permission_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/navigation/app_navigator.dart';
import '../../../app/providers/app_locale_provider.dart';
import '../../../utils/update_check_flag_file.dart';
import '../../../utils/runtime_platform.dart';
import '../../../utils/observable_state.dart';
import '../../../utils/lang_mapping.dart';
import '/services/piped_service.dart';
import '../../../services/resolver/resolver_client.dart';
import '../../../services/resolver/resolver_configuration.dart';
import '../../../services/resolver/resolver_discovery_service.dart';
import '../../../services/resolver/resolver_source_mode.dart';
import '../Library/library_controller.dart';
import '../../widgets/bottom_nav_bar_dimensions.dart';
import '../../widgets/new_version_dialog.dart';
import '../../widgets/snackbar.dart';
import '../../../utils/helper.dart';
import '/services/music_service.dart';
import '/services/app_contracts.dart';
import '/ui/player/player_controller.dart';
import '../Home/home_screen_controller.dart';
import '/ui/utils/theme_controller.dart';

import '/services/constant.dart';
import '../../navigator.dart';

class DeveloperSettingValue {
  const DeveloperSettingValue(this.name, this.value);

  final String name;
  final String value;
}

class SettingsScreenController extends ChangeNotifier
    with WidgetsBindingObserver {
  SettingsScreenController({
    required AudioHandler audioHandler,
    required PlaylistRepository playlistRepository,
    required SettingsRepository settingsRepository,
    required StorageAdminRepository storageAdminRepository,
    required MusicServiceContract musicService,
    required HomeScreenController Function() homeScreenController,
    required PlayerController Function() playerController,
    required ThemeController Function() themeController,
    required PipedServices Function() pipedServices,
    required AppLocaleController appLocaleController,
    required ResolverClient resolverClient,
    required ResolverDiscoveryService resolverDiscovery,
  }) : _audioHandler = audioHandler,
       _playlistRepository = playlistRepository,
       _settingsRepository = settingsRepository,
       _storageAdminRepository = storageAdminRepository,
       _musicService = musicService,
       _homeScreenController = homeScreenController,
       _playerController = playerController,
       _themeController = themeController,
       _pipedServices = pipedServices,
       _appLocaleController = appLocaleController,
       _resolverClient = resolverClient,
       _resolverDiscovery = resolverDiscovery;

  final AudioHandler _audioHandler;
  final PlaylistRepository _playlistRepository;
  final SettingsRepository _settingsRepository;
  final StorageAdminRepository _storageAdminRepository;
  final MusicServiceContract _musicService;
  final HomeScreenController Function() _homeScreenController;
  final PlayerController Function() _playerController;
  final ThemeController Function() _themeController;
  final PipedServices Function() _pipedServices;
  final AppLocaleController _appLocaleController;
  final ResolverClient _resolverClient;
  final ResolverDiscoveryService _resolverDiscovery;
  SettingsRepository get settingsRepository => _settingsRepository;
  StorageAdminRepository get storageAdminRepository => _storageAdminRepository;
  late String _supportDir;
  final cacheSongs = ObservableValue(false);
  final themeModeType = ObservableValue(ThemeType.dynamic);
  final skipSilenceEnabled = ObservableValue(false);
  final loudnessNormalizationEnabled = ObservableValue(false);
  final noOfHomeScreenContent = ObservableValue(3);
  final streamingQuality = ObservableValue(AudioQuality.High);
  final playbackMode = ObservableValue(PlaybackMode.classic);
  final playbackPreloadRange = ObservableValue(0);
  final playerUi = ObservableValue(0);
  final slidableActionEnabled = ObservableValue(true);
  final isIgnoringBatteryOptimizations = ObservableValue(false);
  final autoOpenPlayer = ObservableValue(false);
  final discoverContentType = ObservableValue("BOLI");
  final isNewVersionAvailable = ObservableValue(false);
  final updateInfo = ObservableNullable<UpdateInfo>();
  final updateChannel = ObservableValue(UpdateChannel.stable);
  final isUpdateDownloading = ObservableValue(false);
  final updateDownloadProgress = ObservableValue(0.0);
  final updateDownloadError = ObservableValue("");
  final isLinkedWithPiped = ObservableValue(false);
  final stopPlaybackOnSwipeAway = ObservableValue(false);
  final currentAppLanguageCode = ObservableValue("en");
  final downloadLocationPath = ObservableValue("");
  final exportLocationPath = ObservableValue("");
  final downloadingFormat = ObservableValue("opus");
  final autoDownloadFavoriteSongEnabled = ObservableValue(false);
  final isTransitionAnimationDisabled = ObservableValue(false);
  final isBottomNavBarEnabled = ObservableValue(true);
  final backgroundPlayEnabled = ObservableValue(true);
  final keepScreenAwake = ObservableValue(false);
  final restorePlaybackSession = ObservableValue(false);
  final cacheHomeScreenData = ObservableValue(true);
  final developerSettingsEnabled = ObservableValue(false);
  final developerSettingValues = ObservableList<DeveloperSettingValue>();
  final resolverEnabled = ObservableValue(true);
  final resolverSourceMode = ObservableValue(ResolverSourceMode.both);
  final resolverEffectiveUrl = ObservableValue('');
  final resolverStatus = ObservableValue('not_tested');
  final resolverDiscoveredUrls = ObservableList<String>();
  final currentVersion =
      "V${(BuildInfo.version.isEmpty ? '5.9.2' : BuildInfo.version).split('+').first.split('-').first}";

  final libraryFirstTab = ObservableValue(0);

  var _initialized = false;
  Uri? _discoveredResolver;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    await _setInitValue();
    await _createInAppSongDownDir();
    await clearCachedUpdateApks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      await refreshIgnoringBatteryOptimizations();
    }
  }

  String get currentVision => currentVersion;

  UpdateChannel get selectedUpdateChannel => updateChannel.value;

  get isCurrentPathSupportDownloadDir =>
      "$_supportDir/Music" == downloadLocationPath.toString();

  String get supportDirPath => _supportDir;

  bool _updateSectionRevealPending = false;

  /// One-shot flag: something navigated to Settings and wants the App Info
  /// section (which holds both "Check for updates" and "Update channel")
  /// opened. Set by the 6.0.0 release prompt after a channel choice, and by
  /// the new-version dialog when the user disables the startup popup — so
  /// they land on where updates can be checked manually. The settings
  /// screen consumes it once on build.
  void requestUpdateSectionReveal() {
    _updateSectionRevealPending = true;
  }

  bool consumeUpdateSectionReveal() {
    final pending = _updateSectionRevealPending;
    _updateSectionRevealPending = false;
    return pending;
  }

  Future<UpdateInfo?> checkNewVersion() async {
    updateChannel.value = _settingsRepository.getUpdateChannel();
    final info = await newVersionCheck(
      currentVersion,
      channel: selectedUpdateChannel,
    );
    updateInfo.value = info;
    isNewVersionAvailable.value = info != null;
    notifyListeners();
    return info;
  }

  Future<void> downloadAndInstallUpdate(UpdateInfo? info) async {
    final update = info ?? updateInfo.value;
    final fallbackUrl =
        update?.releaseUrl ??
        update?.downloadUrl ??
        'https://github.com/bozmund/Harmony-Music/releases/latest';

    if (isUpdateDownloading.value) return;
    if (update == null ||
        !RuntimePlatform.isAndroid ||
        !_isApkUrl(update.downloadUrl)) {
      await AppPlatformService.openUrl(fallbackUrl);
      return;
    }

    isUpdateDownloading.value = true;
    updateDownloadProgress.value = 0;
    updateDownloadError.value = "";
    notifyListeners();

    try {
      final updateDir = await _updateCacheDir();
      await clearCachedUpdateApks();
      if (!await updateDir.exists()) {
        await updateDir.create(recursive: true);
      }

      final apkPath = "${updateDir.path}/${_updateApkFileName(update)}";
      await Dio().download(
        update.downloadUrl,
        apkPath,
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          updateDownloadProgress.value = received / total;
          notifyListeners();
        },
      );

      final apkFile = File(apkPath);
      if (!await apkFile.exists() || await apkFile.length() == 0) {
        throw const FileSystemException('Downloaded APK is missing or empty');
      }

      updateDownloadProgress.value = 1;
      notifyListeners();
      await AppPlatformService.installApk(apkPath);
    } on PlatformException catch (e) {
      if (e.code == "INSTALL_PERMISSION_REQUIRED") {
        updateDownloadError.value =
            e.message ?? "Allow install permission, then tap update again.";
        notifyListeners();
        _showUpdateMessage(updateDownloadError.value);
      } else {
        updateDownloadError.value = "Update install failed. Opening browser.";
        notifyListeners();
        _showUpdateMessage(updateDownloadError.value);
        await AppPlatformService.openUrl(fallbackUrl);
      }
    } catch (e) {
      updateDownloadError.value = "Update download failed. Opening browser.";
      notifyListeners();
      _showUpdateMessage(updateDownloadError.value);
      await AppPlatformService.openUrl(fallbackUrl);
    } finally {
      isUpdateDownloading.value = false;
      notifyListeners();
    }
  }

  Future<void> clearCachedUpdateApks() async {
    try {
      final updateDir = await _updateCacheDir();
      if (await updateDir.exists()) {
        await updateDir.delete(recursive: true);
      }
    } catch (_) {
      // Cache cleanup should never block app startup or Settings.
    }
  }

  Future<Directory> _updateCacheDir() async {
    final tempDir = await getTemporaryDirectory();
    return Directory("${tempDir.path}/updates");
  }

  bool _isApkUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.path.toLowerCase().endsWith(".apk");
  }

  String _updateApkFileName(UpdateInfo info) {
    final safeVersion = info.version.replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '_',
    );
    return "harmonymusic-${info.channel.name}-$safeVersion.apk";
  }

  void _showUpdateMessage(String message) {
    final context = AppNavigator.context;
    if (context == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(snackbar(context, message, size: SanckBarSize.MEDIUM));
  }

  Future<String> _createInAppSongDownDir() async {
    _supportDir = (await getApplicationSupportDirectory()).path;
    final directory = Directory("$_supportDir/Music/");
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return "$_supportDir/Music";
  }

  Future<void> _setInitValue() async {
    final isDesktop = RuntimePlatform.isDesktop;
    final appLang = _normalizeAppLanguageCode(
      _settingsRepository.getLanguageCode(),
    );
    currentAppLanguageCode.value = appLang;
    updateChannel.value = _settingsRepository.getUpdateChannel();
    isBottomNavBarEnabled.value = isDesktop
        ? false
        : _settingsRepository.getBottomNavBarEnabled();
    noOfHomeScreenContent.value = _settingsRepository
        .getNoOfHomeScreenContent();
    isTransitionAnimationDisabled.value = _settingsRepository
        .getTransitionAnimationDisabled();
    cacheSongs.value = _settingsRepository.getCacheSongs();
    themeModeType.value =
        ThemeType.values[_settingsRepository.getThemeModeType()];
    skipSilenceEnabled.value = isDesktop
        ? false
        : _settingsRepository.getSkipSilenceEnabled();
    loudnessNormalizationEnabled.value = isDesktop
        ? false
        : _settingsRepository.getLoudnessNormalizationEnabled();
    autoOpenPlayer.value = _settingsRepository.getAutoOpenPlayer();
    restorePlaybackSession.value = _settingsRepository
        .getRestorePlaybackSession();
    cacheHomeScreenData.value = _settingsRepository.getCacheHomeScreenData();
    developerSettingsEnabled.value = _settingsRepository
        .getDeveloperSettingsEnabled();
    resolverEnabled.value = _settingsRepository.getResolverEnabled();
    resolverSourceMode.value = kDebugMode
        ? _settingsRepository.getResolverSourceMode()
        : ResolverSourceMode.both;
    _refreshResolverConfiguration();
    if (developerSettingsEnabled.value) {
      refreshDeveloperSettingValues();
    }
    streamingQuality.value =
        AudioQuality.values[_settingsRepository.getStreamingQualityIndex()];
    playbackMode.value = _settingsRepository.getPlaybackMode();
    playbackPreloadRange.value = _settingsRepository.getPlaybackPreloadRange();
    if (playbackMode.value == PlaybackMode.preloaded &&
        playbackPreloadRange.value == 0) {
      playbackPreloadRange.value = 1;
      await _settingsRepository.setPlaybackPreloadRange(1);
    }
    playerUi.value = isDesktop ? 0 : _settingsRepository.getPlayerUi();
    backgroundPlayEnabled.value = _settingsRepository
        .getBackgroundPlayEnabled();
    keepScreenAwake.value =
        _settingsRepository.getKeepScreenAwake(RuntimePlatform.isDesktop)
        ? true
        : false;
    final downloadPath =
        _settingsRepository.getDownloadLocationPath() ??
        await _createInAppSongDownDir();
    downloadLocationPath.value =
        (isDesktop && downloadPath.contains("emulated"))
        ? await _createInAppSongDownDir()
        : downloadPath;

    exportLocationPath.value = _settingsRepository.getExportLocationPath();
    downloadingFormat.value = _settingsRepository.getDownloadingFormat();
    discoverContentType.value = _settingsRepository.getDiscoverContentType();
    slidableActionEnabled.value = _settingsRepository
        .getSlidableActionEnabled();
    isLinkedWithPiped.value =
        _settingsRepository.getPiped()?['isLoggedIn'] == true;
    stopPlaybackOnSwipeAway.value = _settingsRepository
        .getStopPlaybackOnSwipeAway();
    if (RuntimePlatform.isAndroid) {
      await refreshIgnoringBatteryOptimizations();
      await _requestIgnoringBatteryOptimizationsOnInstall();
    }
    autoDownloadFavoriteSongEnabled.value = _settingsRepository
        .getAutoDownloadFavoriteSongEnabled();
    final normalizedLibraryFirstTab =
        SettingsScreenController.normalizeLibraryFirstTab(
          _settingsRepository.getLibraryFirstTab(),
        );
    libraryFirstTab.value = normalizedLibraryFirstTab;
    await _settingsRepository.setLibraryFirstTab(normalizedLibraryFirstTab);
    notifyListeners();
  }

  Future<void> checkUpdate(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      snackbar(context, context.l10n.checkingUpdate, size: SanckBarSize.MEDIUM),
    );
    final info = await checkNewVersion();
    if (info != null) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => NewVersionDialog(updateInfo: info),
      );
    } else {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, context.l10n.upToDate, size: SanckBarSize.MEDIUM),
      );
    }
  }

  Future<void> changeUpdateChannel(String? val) async {
    final next = val == 'rolling'
        ? UpdateChannel.rolling
        : UpdateChannel.stable;
    updateChannel.value = next;
    await _settingsRepository.setUpdateChannel(next);
    notifyListeners();
    if (updateCheckFlag) await checkNewVersion();
  }

  Future<void> setDeveloperSettingsEnabled(bool value) async {
    developerSettingsEnabled.value = value;
    await _settingsRepository.setDeveloperSettingsEnabled(value);
    if (value) {
      refreshDeveloperSettingValues();
    } else {
      developerSettingValues.clear();
    }
    notifyListeners();
  }

  Future<void> setResolverEnabled(bool value) async {
    resolverEnabled.value = value;
    await _settingsRepository.setResolverEnabled(value);
    notifyListeners();
  }

  Future<void> setResolverSourceMode(ResolverSourceMode? value) async {
    if (!kDebugMode || value == null) return;
    resolverSourceMode.value = value;
    await _settingsRepository.setResolverSourceMode(value);
    await _audioHandler.customAction("preloadConfigChanged");
    refreshDeveloperSettingValues();
  }

  void _refreshResolverConfiguration({Uri? discovered}) {
    if (discovered != null) _discoveredResolver = discovered;
    try {
      final configuration = ResolverConfiguration.load(
        _settingsRepository,
        discovered: _discoveredResolver,
      );
      resolverEffectiveUrl.value = configuration.baseUrl?.toString() ?? '';
    } on FormatException {
      resolverEffectiveUrl.value = '';
      resolverStatus.value = 'invalid_url';
    }
  }

  Future<bool> testResolverConnection() async {
    _refreshResolverConfiguration();
    final value = resolverEffectiveUrl.value;
    if (value.isEmpty) {
      resolverStatus.value = 'not_configured';
      notifyListeners();
      return false;
    }
    resolverStatus.value = 'testing';
    notifyListeners();
    try {
      final health = await _resolverClient.check(Uri.parse(value));
      resolverStatus.value = health.ready ? 'ready' : 'not_ready';
      notifyListeners();
      return health.ready;
    } catch (_) {
      if (!kReleaseMode) {
        final discovered = await discoverResolvers();
        if (discovered.isNotEmpty) {
          try {
            final health = await _resolverClient.check(
              Uri.parse(resolverEffectiveUrl.value),
            );
            resolverStatus.value = health.ready ? 'ready' : 'not_ready';
            notifyListeners();
            return health.ready;
          } catch (_) {}
        }
      }
      resolverStatus.value = 'unreachable';
      notifyListeners();
      return false;
    }
  }

  Future<List<String>> discoverResolvers() async {
    resolverStatus.value = 'discovering';
    notifyListeners();
    try {
      final urls = await _resolverDiscovery.discover();
      resolverDiscoveredUrls
        ..clear()
        ..addAll(urls.map((url) => url.toString()));
      if (urls.isNotEmpty)
        _refreshResolverConfiguration(discovered: urls.first);
      resolverStatus.value = urls.isEmpty ? 'none_discovered' : 'discovered';
      notifyListeners();
      return resolverDiscoveredUrls.toList();
    } catch (_) {
      resolverStatus.value = 'discovery_failed';
      notifyListeners();
      return const [];
    }
  }

  Future<void> setResolverOverride(String? value) async {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      ResolverConfiguration.normalize(trimmed, production: kReleaseMode);
    }
    if (kReleaseMode) {
      await _settingsRepository.setResolverProductionOverride(
        trimmed?.isEmpty == true ? null : trimmed,
      );
    } else {
      await _settingsRepository.setResolverDebugOverride(
        trimmed?.isEmpty == true ? null : trimmed,
      );
    }
    resolverStatus.value = 'not_tested';
    _refreshResolverConfiguration();
    notifyListeners();
  }

  void refreshDeveloperSettingValues() {
    final values = <DeveloperSettingValue>[
      DeveloperSettingValue("app.currentVersion", currentVersion),
      DeveloperSettingValue(
        "build.channel",
        _formatDeveloperValue(BuildInfo.channel),
      ),
      DeveloperSettingValue(
        "build.version",
        _formatDeveloperValue(BuildInfo.version),
      ),
      DeveloperSettingValue("build.sha", _formatDeveloperValue(BuildInfo.sha)),
      DeveloperSettingValue(
        "update.updateCheckFlag",
        updateCheckFlag.toString(),
      ),
      DeveloperSettingValue(
        "update.newVersionVisibility",
        _formatDeveloperValue(
          _settingsRepository.getNewVersionVisibility(updateCheckFlag),
        ),
      ),
      DeveloperSettingValue("update.channel", updateChannel.value.name),
      DeveloperSettingValue(
        "resolver.environment",
        kReleaseMode ? "production" : "debug",
      ),
      DeveloperSettingValue(
        "resolver.enabled",
        resolverEnabled.value.toString(),
      ),
      if (kDebugMode)
        DeveloperSettingValue(
          "resolver.sourceMode",
          resolverSourceMode.value.name,
        ),
      DeveloperSettingValue(
        "resolver.effectiveUrl",
        _formatDeveloperValue(resolverEffectiveUrl.value),
      ),
      DeveloperSettingValue("resolver.status", resolverStatus.value),
      DeveloperSettingValue(
        "resolver.discovered",
        _formatDeveloperValue(resolverDiscoveredUrls.toList()),
      ),
      DeveloperSettingValue(
        "update.isNewVersionAvailable",
        isNewVersionAvailable.value.toString(),
      ),
      DeveloperSettingValue(
        "update.info",
        _formatDeveloperValue(_updateInfoForDeveloperView()),
      ),
    ];

    final appPrefs = _settingsRepository.developerValues();
    final keys = appPrefs.keys.toList()
      ..sort((a, b) => a.toString().compareTo(b.toString()));
    for (final key in keys) {
      final keyName = key.toString();
      values.add(
        DeveloperSettingValue(
          "appPrefs.$keyName",
          _formatDeveloperValue(appPrefs[key], key: keyName),
        ),
      );
    }

    developerSettingValues.assignAll(values);
    notifyListeners();
  }

  Map<String, dynamic>? _updateInfoForDeveloperView() {
    final info = updateInfo.value;
    if (info == null) return null;
    return {
      "channel": info.channel.name,
      "version": info.version,
      "downloadUrl": info.downloadUrl,
      "releaseUrl": info.releaseUrl,
      "sha": info.sha,
    };
  }

  String _formatDeveloperValue(dynamic value, {String? key}) {
    if (_shouldRedactDeveloperValue(key)) return "<redacted>";
    final text = switch (value) {
      null => "null",
      bool() || num() || String() => value.toString(),
      _ => _jsonLikeDeveloperValue(value),
    };
    return _truncateDeveloperValue(text);
  }

  bool _shouldRedactDeveloperValue(String? key) {
    final lowerKey = key?.toLowerCase();
    if (lowerKey == null) return false;
    return lowerKey.contains("token") ||
        lowerKey.contains("secret") ||
        lowerKey.contains("password") ||
        lowerKey.contains("cookie") ||
        lowerKey.contains("auth") ||
        lowerKey == PrefKeys.visitorId.toLowerCase();
  }

  String _jsonLikeDeveloperValue(dynamic value) {
    try {
      return jsonEncode(_normalizeDeveloperValue(value));
    } catch (_) {
      return value.toString();
    }
  }

  dynamic _normalizeDeveloperValue(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, mapValue) =>
            MapEntry(key.toString(), _normalizeDeveloperValue(mapValue)),
      );
    }
    if (value is Iterable) {
      return value.map(_normalizeDeveloperValue).toList();
    }
    return value;
  }

  String _truncateDeveloperValue(String value) {
    const maxLength = 240;
    if (value.length <= maxLength) return value;
    return "${value.substring(0, maxLength)}...";
  }

  Future<void> setAppLanguage(String? val) async {
    final languageCode = _normalizeAppLanguageCode(val);
    _appLocaleController.setLanguageCode(languageCode);
    _musicService.hlCode = languageCode;
    (_homeScreenController().loadContentFromNetwork(silent: true),);
    currentAppLanguageCode.value = languageCode;
    await _settingsRepository.setLanguageCode(languageCode);
    notifyListeners();
  }

  String _normalizeAppLanguageCode(String? languageCode) {
    return langMap.containsKey(languageCode) ? languageCode! : 'en';
  }

  Future<void> setContentNumber(int? no) async {
    noOfHomeScreenContent.value = no!;
    await _settingsRepository.setNoOfHomeScreenContent(no);
    notifyListeners();
  }

  void setStreamingQuality(dynamic val) {
    unawaited(
      _settingsRepository.setStreamingQualityIndex(
        AudioQuality.values.indexOf(val),
      ),
    );
    streamingQuality.value = val;
    unawaited(_audioHandler.customAction("preloadConfigChanged"));
    notifyListeners();
  }

  Future<void> setPlaybackMode(PlaybackMode? mode) async {
    final selectedMode = mode ?? PlaybackMode.classic;
    await _settingsRepository.setPlaybackMode(selectedMode);
    playbackMode.value = selectedMode;
    if (selectedMode == PlaybackMode.classic) {
      playbackPreloadRange.value = 0;
      await _settingsRepository.setPlaybackPreloadRange(0);
    } else if (playbackPreloadRange.value == 0) {
      playbackPreloadRange.value = 1;
      await _settingsRepository.setPlaybackPreloadRange(1);
    }
    await _audioHandler.customAction("updatePlaybackMode", {
      "mode": selectedMode.index,
    });
    await _audioHandler.customAction("updatePlaybackPreloadRange", {
      "range": playbackPreloadRange.value,
    });
    notifyListeners();
  }

  Future<void> setPlaybackPreloadRange(int? value) async {
    final range = (value ?? 0).clamp(0, 5).toInt();
    await _settingsRepository.setPlaybackPreloadRange(range);
    playbackPreloadRange.value = range;
    if (range > 0 && playbackMode.value != PlaybackMode.preloaded) {
      await setPlaybackMode(PlaybackMode.preloaded);
    }
    await _audioHandler.customAction("updatePlaybackPreloadRange", {
      "range": range,
    });
    notifyListeners();
  }

  Future<void> setPlayerUi(dynamic val) async {
    final playerCon = _playerController();
    await _settingsRepository.setPlayerUi(val);
    if (val == 1 && playerCon.gesturePlayerStateAnimationController == null) {
      playerCon.initGesturePlayerStateAnimationController();
    }

    playerUi.value = val;
    notifyListeners();
  }

  Future<void> enableBottomNavBar(bool val) async {
    final homeScrCon = _homeScreenController();
    final playerCon = _playerController();
    if (val) {
      homeScrCon.onSideBarTabSelected(3);
      isBottomNavBarEnabled.value = true;
    } else {
      isBottomNavBarEnabled.value = false;
      homeScrCon.onSideBarTabSelected(5);
    }
    if (!_playerController().initFlagForPlayer) {
      final appContext = AppNavigator.context;
      final isWideScreen =
          appContext != null && MediaQuery.of(appContext).size.width > 800;
      final bottomNavVisible =
          val &&
          homeScrCon.isHomeScreenOnTop &&
          !playerCon.playerPanelOpen.value;
      playerCon.playerPanelMinHeight.value = appContext == null
          ? collapsedMiniPlayerHeightForInset(
              bottomInset: 0,
              isWideScreen: isWideScreen,
              bottomNavVisible: bottomNavVisible,
            )
          : collapsedMiniPlayerHeight(
              appContext,
              isWideScreen: isWideScreen,
              bottomNavVisible: bottomNavVisible,
            );
    }
    await _settingsRepository.setBottomNavBarEnabled(val);
    notifyListeners();
  }

  Future<void> toggleSlidableAction(bool val) async {
    await _settingsRepository.setSlidableActionEnabled(val);
    slidableActionEnabled.value = val;
    notifyListeners();
  }

  Future<void> changeDownloadingFormat(String? val) async {
    downloadingFormat.value = val!;
    await _settingsRepository.setDownloadingFormat(val);
    notifyListeners();
  }

  Future<void> setExportedLocation() async {
    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    final String? pickedFolderPath = await FilePickerService.getDirectoryPath(
      confirmButtonText: "Select export file folder",
    );
    if (pickedFolderPath == '/' || pickedFolderPath == null) {
      return;
    }

    await _settingsRepository.setExportLocationPath(pickedFolderPath);
    exportLocationPath.value = pickedFolderPath;
    notifyListeners();
  }

  Future<void> setDownloadLocation() async {
    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    final String? pickedFolderPath = await FilePickerService.getDirectoryPath(
      confirmButtonText: "Select downloads folder",
    );
    if (pickedFolderPath == '/' || pickedFolderPath == null) {
      return;
    }

    await _settingsRepository.setDownloadLocationPath(pickedFolderPath);
    downloadLocationPath.value = pickedFolderPath;
    notifyListeners();
  }

  Future<void> disableTransitionAnimation(bool val) async {
    await _settingsRepository.setTransitionAnimationDisabled(val);
    isTransitionAnimationDisabled.value = val;
    notifyListeners();
  }

  Future<void> clearImagesCache() async {
    final tempImgDirPath =
        "${(await getApplicationCacheDirectory()).path}/libCachedImageData";
    final tempImgDir = Directory(tempImgDirPath);
    try {
      if (await tempImgDir.exists()) {
        await tempImgDir.delete(recursive: true);
      }
      // ignore: empty_catches
    } catch (e) {}
  }

  Future<void> resetDownloadLocation() async {
    final defaultPath = "$_supportDir/Music";
    await _settingsRepository.setDownloadLocationPath(defaultPath);
    downloadLocationPath.value = defaultPath;
    notifyListeners();
  }

  Future<void> onThemeChange(dynamic val) async {
    unawaited(
      _settingsRepository.setThemeModeType(ThemeType.values.indexOf(val)),
    );
    themeModeType.value = val;
    await _themeController().changeThemeModeType(val);
    notifyListeners();
  }

  Future<void> onContentChange(dynamic value) async {
    await _settingsRepository.setDiscoverContentType(value);
    discoverContentType.value = value;
    await _homeScreenController().changeDiscoverContent(value);
    notifyListeners();
  }

  Future<void> toggleCachingSongsValue(bool value) async {
    await _settingsRepository.setCacheSongs(value);
    cacheSongs.value = value;
    notifyListeners();
  }

  Future<void> toggleSkipSilence(bool val) async {
    await _playerController().toggleSkipSilence(val);
    await _settingsRepository.setSkipSilenceEnabled(val);
    skipSilenceEnabled.value = val;
    notifyListeners();
  }

  Future<void> toggleLoudnessNormalization(bool val) async {
    await _playerController().toggleLoudnessNormalization(val);
    await _settingsRepository.setLoudnessNormalizationEnabled(val);
    loudnessNormalizationEnabled.value = val;
    notifyListeners();
  }

  Future<void> toggleRestorePlaybackSession(bool val) async {
    await _settingsRepository.setRestorePlaybackSession(val);
    restorePlaybackSession.value = val;
    notifyListeners();
  }

  Future<void> toggleCacheHomeScreenData(bool val) async {
    await _settingsRepository.setCacheHomeScreenData(val);
    cacheHomeScreenData.value = val;
    if (!val) {
      await _storageAdminRepository.clearBoxes([BoxNames.homeScreenData]);
    } else {
      (_homeScreenController().cachedHomeScreenData(updateAll: true),);
    }
    notifyListeners();
  }

  Future<void> resetRecoverableAppState() async {
    await _storageAdminRepository.clearPlaybackAndCacheData();

    final homeController = _homeScreenController();
    homeController.resetRecoverableNavigationState();

    final nestedNavigator = ScreenNavigationSetup.navigatorKey.currentState;
    nestedNavigator?.popUntil(
      (route) => route.settings.name == ScreenNavigationSetup.homeScreen,
    );

    final playerController = _playerController();
    if (playerController.playerPanelController.isAttached &&
        playerController.playerPanelController.isPanelOpen) {
      await playerController.playerPanelController.close();
    }
    if (playerController.queuePanelController.isAttached &&
        playerController.queuePanelController.isPanelOpen) {
      await playerController.queuePanelController.close();
    }

    await homeController.loadContentFromNetwork(silent: true);
  }

  Future<void> exportDeveloperClonePackage() async {
    if (!RuntimePlatform.isAndroid) return;
    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    final String? pickedFolderPath = await FilePickerService.getDirectoryPath(
      confirmButtonText: "Select clone export folder",
    );
    if (pickedFolderPath == '/' || pickedFolderPath == null) {
      return;
    }

    try {
      await _flushOpenCloneBoxes();

      final packageInfo = await AppPlatformService.getAppInfo();
      final sourceSupportDir = (await getApplicationSupportDirectory()).path;
      final sourceDbDir = await dbDir;
      final cloneDir = Directory(
        "$pickedFolderPath/HarmonyMusicClone/${DateTime.now().millisecondsSinceEpoch}",
      );
      await cloneDir.create(recursive: true);

      await _copyDirectoryFiles(
        sourceDir: Directory(sourceDbDir),
        targetDir: Directory("${cloneDir.path}/db"),
        extensionFilter: ".hive",
      );
      await _copyDirectoryFiles(
        sourceDir: Directory("$sourceSupportDir/Music"),
        targetDir: Directory("${cloneDir.path}/Music"),
      );
      await _copyDirectoryFiles(
        sourceDir: Directory("$sourceSupportDir/thumbnails"),
        targetDir: Directory("${cloneDir.path}/thumbnails"),
        extensionFilter: ".png",
      );

      final manifest = {
        "sourcePackageId": packageInfo.packageName,
        "sourceSupportPath": sourceSupportDir,
        "sourceDbPath": sourceDbDir,
        "createdAt": DateTime.now().toIso8601String(),
      };
      await File(
        "${cloneDir.path}/manifest.json",
      ).writeAsString(const JsonEncoder.withIndent("  ").convert(manifest));

      _showSettingsSnack("Clone package exported");
      printINFO(
        "Developer clone exported to ${cloneDir.path}",
        tag: LogTags.settings,
      );
    } catch (e, stackTrace) {
      printERROR("Developer clone export failed: $e", tag: LogTags.settings);
      printERROR(stackTrace, tag: LogTags.settings);
      _showSettingsSnack("Clone export failed");
    }
  }

  Future<void> importDeveloperClonePackage() async {
    if (!RuntimePlatform.isAndroid) return;
    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    final String? cloneFolderPath = await FilePickerService.getDirectoryPath(
      confirmButtonText: "Select HarmonyMusicClone package",
    );
    if (cloneFolderPath == '/' || cloneFolderPath == null) {
      return;
    }

    final cloneDir = Directory(cloneFolderPath);
    final manifestFile = File("${cloneDir.path}/manifest.json");
    if (!await manifestFile.exists()) {
      _showSettingsSnack("Clone manifest not found");
      return;
    }

    try {
      final targetSupportDir = (await getApplicationSupportDirectory()).path;
      final targetDbDir = await dbDir;
      final manifest = jsonDecode(await manifestFile.readAsString());
      final sourceSupportPath = manifest["sourceSupportPath"]?.toString();
      if (sourceSupportPath == null || sourceSupportPath.isEmpty) {
        _showSettingsSnack("Invalid clone manifest");
        return;
      }

      await closeAllDatabases();

      await _replaceDirectoryFiles(
        sourceDir: Directory("${cloneDir.path}/db"),
        targetDir: Directory(targetDbDir),
        extensionFilter: ".hive",
      );
      await _replaceDirectoryFiles(
        sourceDir: Directory("${cloneDir.path}/Music"),
        targetDir: Directory("$targetSupportDir/Music"),
      );
      await _replaceDirectoryFiles(
        sourceDir: Directory("${cloneDir.path}/thumbnails"),
        targetDir: Directory("$targetSupportDir/thumbnails"),
        extensionFilter: ".png",
      );

      await _rewriteImportedClonePaths(
        sourceSupportPath: sourceSupportPath,
        targetSupportPath: targetSupportDir,
      );

      _showSettingsSnack("Clone imported. Restarting app.");
      await Future.delayed(const Duration(milliseconds: 350));
      await AppPlatformService.restartApp();
    } catch (e, stackTrace) {
      printERROR("Developer clone import failed: $e", tag: LogTags.settings);
      printERROR(stackTrace, tag: LogTags.settings);
      _showSettingsSnack("Clone import failed");
    }
  }

  Future<void> toggleAutoDownloadFavoriteSong(bool val) async {
    await _settingsRepository.setAutoDownloadFavoriteSongEnabled(val);
    autoDownloadFavoriteSongEnabled.value = val;
    notifyListeners();
  }

  Future<void> toggleBackgroundPlay(bool val) async {
    await _settingsRepository.setBackgroundPlayEnabled(val);
    backgroundPlayEnabled.value = val;
    notifyListeners();
  }

  Future<void> toggleKeepScreenAwake(bool val) async {
    await _settingsRepository.setKeepScreenAwake(val);
    keepScreenAwake.value = val;
    try {
      if (val) {
        // enable wakelock immediately if music is playing
        if (_playerController().buttonState.value == PlayButtonState.playing) {
          await AppPlatformService.setKeepScreenAwake(true);
        }
      } else {
        await AppPlatformService.setKeepScreenAwake(false);
      }
    } catch (e) {
      // ignore if player/controller not available
    }
    notifyListeners();
  }

  Future<void> openBatteryOptimizationSettings() async {
    if (!RuntimePlatform.isAndroid) return;

    await _settingsRepository.setBatteryOptimizationPromptShown(true);
    final isIgnoring = await Permission.ignoreBatteryOptimizations.isGranted;
    if (isIgnoring) {
      await openAppSettings();
    } else {
      await Permission.ignoreBatteryOptimizations.request();
    }
    await refreshIgnoringBatteryOptimizations();
  }

  Future<void> refreshIgnoringBatteryOptimizations() async {
    if (!RuntimePlatform.isAndroid) return;
    isIgnoringBatteryOptimizations.value =
        await Permission.ignoreBatteryOptimizations.isGranted;
    notifyListeners();
  }

  Future<void> _requestIgnoringBatteryOptimizationsOnInstall() async {
    if (_settingsRepository.getBatteryOptimizationPromptShown() ||
        isIgnoringBatteryOptimizations.value) {
      return;
    }

    await _settingsRepository.setBatteryOptimizationPromptShown(true);
    await Permission.ignoreBatteryOptimizations.request();
    await refreshIgnoringBatteryOptimizations();
  }

  Future<void> toggleAutoOpenPlayer(bool val) async {
    await _settingsRepository.setAutoOpenPlayer(val);
    autoOpenPlayer.value = val;
    notifyListeners();
  }

  Future<void> setFirstLibraryTab(int index) async {
    final normalizedIndex = SettingsScreenController.normalizeLibraryFirstTab(
      index,
    );
    await _settingsRepository.setLibraryFirstTab(normalizedIndex);
    libraryFirstTab.value = normalizedIndex;
    notifyListeners();
  }

  static int normalizeLibraryFirstTab(dynamic value) {
    if (value is! int || value < 0 || value >= libraryTabKeys.length) {
      return 0;
    }
    return value;
  }

  Future<void> unlinkPiped(BuildContext context) async {
    await _pipedServices().logout();
    isLinkedWithPiped.value = false;
    LibraryPlaylistsControllerRegistry.current?.removePipedPlaylists();
    await _playlistRepository.clearBlacklistedPlaylistIds();
    _showSettingsSnack(context.l10n.unlinkAlert);
    notifyListeners();
  }

  Future<void> resetAppSettingsToDefault() async {
    await _settingsRepository.clearAll();
  }

  Future<void> toggleStopPlaybackOnSwipeAway(bool val) async {
    await _settingsRepository.setStopPlaybackOnSwipeAway(val);
    stopPlaybackOnSwipeAway.value = val;
    notifyListeners();
  }

  Future<void> closeAllDatabases() async {
    await _storageAdminRepository.closeAll();
  }

  Future<String> get dbDir async {
    if (RuntimePlatform.isDesktop) {
      return "$supportDirPath/db";
    } else {
      return (await getApplicationDocumentsDirectory()).path;
    }
  }

  Future<void> _flushOpenCloneBoxes() async {
    for (final boxName in [
      BoxNames.songsCache,
      BoxNames.songDownloads,
      BoxNames.songsUrlCache,
      BoxNames.appPrefs,
      BoxNames.homeScreenData,
      BoxNames.prevSessionData,
      BoxNames.libFav,
      BoxNames.libRP,
      BoxNames.libraryPlaylists,
      BoxNames.libraryAlbums,
      BoxNames.libraryArtists,
      BoxNames.librarySearches,
      'blacklistedPlaylist',
      'searchQuery',
      'lyrics',
    ]) {
      await _storageAdminRepository.flushBox(boxName);
    }
  }

  Future<void> _copyDirectoryFiles({
    required Directory sourceDir,
    required Directory targetDir,
    String? extensionFilter,
  }) async {
    if (!await sourceDir.exists()) {
      printWarning(
        "Clone source folder missing: ${sourceDir.path}",
        tag: LogTags.settings,
      );
      return;
    }
    await targetDir.create(recursive: true);

    await for (final entity in sourceDir.list(recursive: false)) {
      if (entity is! File) continue;
      if (extensionFilter != null && !entity.path.endsWith(extensionFilter)) {
        continue;
      }
      if (!await entity.exists()) {
        printWarning(
          "Skipping missing clone file: ${entity.path}",
          tag: LogTags.settings,
        );
        continue;
      }
      final fileName = entity.path.split(RegExp(r'[\\/]')).last;
      await entity.copy("${targetDir.path}/$fileName");
    }
  }

  Future<void> _replaceDirectoryFiles({
    required Directory sourceDir,
    required Directory targetDir,
    String? extensionFilter,
  }) async {
    if (await targetDir.exists()) {
      await for (final entity in targetDir.list(recursive: false)) {
        if (entity is File &&
            (extensionFilter == null ||
                entity.path.endsWith(extensionFilter))) {
          await entity.delete();
        }
      }
    }
    await targetDir.create(recursive: true);
    await _copyDirectoryFiles(
      sourceDir: sourceDir,
      targetDir: targetDir,
      extensionFilter: extensionFilter,
    );
  }

  Future<void> _rewriteImportedClonePaths({
    required String sourceSupportPath,
    required String targetSupportPath,
  }) async {
    final oldMusicPath = "$sourceSupportPath/Music";
    final newMusicPath = "$targetSupportPath/Music";

    await _storageAdminRepository.rewriteClonePaths(
      oldMusicPath: oldMusicPath,
      newMusicPath: newMusicPath,
    );
  }

  void _showSettingsSnack(String message) {
    final context = AppNavigator.context;
    if (context == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(snackbar(context, message, size: SanckBarSize.MEDIUM));
  }
}
