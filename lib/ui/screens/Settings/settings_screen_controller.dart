import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:audio_service/audio_service.dart';
import '../../../domain/repositories/settings_repository.dart';
import '../../../domain/repositories/storage_admin_repository.dart';
import '/services/file_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/app_platform_service.dart';
import 'package:harmonymusic/services/permission_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../utils/update_check_flag_file.dart';
import '/services/piped_service.dart';
import '../Library/library_controller.dart';
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

class SettingsScreenController extends GetxController
    with WidgetsBindingObserver {
  SettingsScreenController({
    required SettingsRepository settingsRepository,
    required StorageAdminRepository storageAdminRepository,
  }) : _settingsRepository = settingsRepository,
       _storageAdminRepository = storageAdminRepository;

  final SettingsRepository _settingsRepository;
  final StorageAdminRepository _storageAdminRepository;
  SettingsRepository get settingsRepository => _settingsRepository;
  StorageAdminRepository get storageAdminRepository => _storageAdminRepository;
  late String _supportDir;
  final cacheSongs = false.obs;
  final setBox = Hive.box(BoxNames.appPrefs);
  final themeModeType = ThemeType.dynamic.obs;
  final skipSilenceEnabled = false.obs;
  final loudnessNormalizationEnabled = false.obs;
  final noOfHomeScreenContent = 3.obs;
  final streamingQuality = AudioQuality.High.obs;
  final playbackMode = PlaybackMode.classic.obs;
  final playbackPreloadRange = 0.obs;
  final playerUi = 0.obs;
  final slidableActionEnabled = true.obs;
  final isIgnoringBatteryOptimizations = false.obs;
  final autoOpenPlayer = false.obs;
  final discoverContentType = "BOLI".obs;
  final isNewVersionAvailable = false.obs;
  final updateInfo = Rxn<UpdateInfo>();
  final updateChannel = UpdateChannel.rolling.obs;
  final isUpdateDownloading = false.obs;
  final updateDownloadProgress = 0.0.obs;
  final updateDownloadError = "".obs;
  final isLinkedWithPiped = false.obs;
  final stopPlaybackOnSwipeAway = false.obs;
  final currentAppLanguageCode = "en".obs;
  final downloadLocationPath = "".obs;
  final exportLocationPath = "".obs;
  final downloadingFormat = "opus".obs;
  final autoDownloadFavoriteSongEnabled = false.obs;
  final isTransitionAnimationDisabled = false.obs;
  final isBottomNavBarEnabled = true.obs;
  final backgroundPlayEnabled = true.obs;
  final keepScreenAwake = false.obs;
  final restorePlaybackSession = false.obs;
  final cacheHomeScreenData = true.obs;
  final developerSettingsEnabled = false.obs;
  final developerSettingValues = <DeveloperSettingValue>[].obs;
  final currentVersion =
      "V${(BuildInfo.version.isEmpty ? '5.9.2' : BuildInfo.version).split('+').first.split('-').first}";

  final libraryFirstTab = 0.obs;

  @override
  Future<void> onInit() async {
    WidgetsBinding.instance.addObserver(this);
    await _setInitValue();
    await _createInAppSongDownDir();
    await clearCachedUpdateApks();
    super.onInit();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
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

  Future<UpdateInfo?> checkNewVersion() async {
    updateChannel.value =
        (setBox.get(PrefKeys.updateChannel) ?? 'rolling') == 'rolling'
        ? UpdateChannel.rolling
        : UpdateChannel.stable;
    final info = await newVersionCheck(
      currentVersion,
      channel: selectedUpdateChannel,
    );
    updateInfo.value = info;
    isNewVersionAvailable.value = info != null;
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
        !GetPlatform.isAndroid ||
        !_isApkUrl(update.downloadUrl)) {
      await AppPlatformService.openUrl(fallbackUrl);
      return;
    }

    isUpdateDownloading.value = true;
    updateDownloadProgress.value = 0;
    updateDownloadError.value = "";

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
        },
      );

      final apkFile = File(apkPath);
      if (!await apkFile.exists() || await apkFile.length() == 0) {
        throw const FileSystemException('Downloaded APK is missing or empty');
      }

      updateDownloadProgress.value = 1;
      await AppPlatformService.installApk(apkPath);
    } on PlatformException catch (e) {
      if (e.code == "INSTALL_PERMISSION_REQUIRED") {
        updateDownloadError.value =
            e.message ?? "Allow install permission, then tap update again.";
        _showUpdateMessage(updateDownloadError.value);
      } else {
        updateDownloadError.value = "Update install failed. Opening browser.";
        _showUpdateMessage(updateDownloadError.value);
        await AppPlatformService.openUrl(fallbackUrl);
      }
    } catch (e) {
      updateDownloadError.value = "Update download failed. Opening browser.";
      _showUpdateMessage(updateDownloadError.value);
      await AppPlatformService.openUrl(fallbackUrl);
    } finally {
      isUpdateDownloading.value = false;
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
    final context = Get.context;
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
    final isDesktop = GetPlatform.isDesktop;
    final appLang = setBox.get(PrefKeys.currentAppLanguageCode) ?? "en";
    currentAppLanguageCode.value = appLang == "zh_Hant"
        ? "zh-TW"
        : appLang == "zh_Hans"
        ? "zh-CN"
        : appLang;
    updateChannel.value =
        (setBox.get(PrefKeys.updateChannel) ?? 'rolling') == 'rolling'
        ? UpdateChannel.rolling
        : UpdateChannel.stable;
    isBottomNavBarEnabled.value = isDesktop
        ? false
        : (setBox.get(PrefKeys.isBottomNavBarEnabled) ?? true);
    noOfHomeScreenContent.value =
        setBox.get(PrefKeys.noOfHomeScreenContent) ?? 3;
    isTransitionAnimationDisabled.value =
        setBox.get(PrefKeys.isTransitionAnimationDisabled) ?? false;
    cacheSongs.value = setBox.get(PrefKeys.cacheSongs) ?? false;
    themeModeType.value =
        ThemeType.values[setBox.get(PrefKeys.themeModeType) ?? 0];
    skipSilenceEnabled.value = isDesktop
        ? false
        : setBox.get(PrefKeys.skipSilenceEnabled);
    loudnessNormalizationEnabled.value = isDesktop
        ? false
        : (setBox.get(PrefKeys.loudnessNormalizationEnabled) ?? false);
    autoOpenPlayer.value = setBox.get(PrefKeys.autoOpenPlayer) ?? true;
    restorePlaybackSession.value =
        setBox.get(PrefKeys.restorePlaybackSession) ?? false;
    cacheHomeScreenData.value =
        setBox.get(PrefKeys.cacheHomeScreenData) ?? true;
    developerSettingsEnabled.value =
        setBox.get(PrefKeys.developerSettingsEnabled) ?? false;
    if (developerSettingsEnabled.isTrue) {
      refreshDeveloperSettingValues();
    }
    streamingQuality.value =
        AudioQuality.values[setBox.get(PrefKeys.streamingQuality) ?? 1];
    final storedPlaybackMode = setBox.get(PrefKeys.playbackMode) ?? 0;
    playbackMode.value =
        storedPlaybackMode is int &&
            storedPlaybackMode >= 0 &&
            storedPlaybackMode < PlaybackMode.values.length
        ? PlaybackMode.values[storedPlaybackMode]
        : PlaybackMode.classic;
    playbackPreloadRange.value =
        ((setBox.get(PrefKeys.playbackPreloadRange) ?? 0) as int)
            .clamp(0, 5)
            .toInt();
    if (playbackMode.value == PlaybackMode.preloaded &&
        playbackPreloadRange.value == 0) {
      playbackPreloadRange.value = 1;
      await setBox.put(PrefKeys.playbackPreloadRange, 1);
    }
    playerUi.value = isDesktop ? 0 : (setBox.get(PrefKeys.playerUi) ?? 0);
    backgroundPlayEnabled.value =
        setBox.get(PrefKeys.backgroundPlayEnabled) ?? true;
    keepScreenAwake.value =
        setBox.get(PrefKeys.keepScreenAwake) ?? GetPlatform.isDesktop
        ? true
        : false;
    final downloadPath =
        setBox.get(PrefKeys.downloadLocationPath) ??
        await _createInAppSongDownDir();
    downloadLocationPath.value =
        (isDesktop && downloadPath.contains("emulated"))
        ? await _createInAppSongDownDir()
        : downloadPath;

    exportLocationPath.value =
        setBox.get(PrefKeys.exportLocationPath) ?? "/storage/emulated/0/Music";
    downloadingFormat.value = setBox.get(PrefKeys.downloadingFormat) ?? "opus";
    discoverContentType.value =
        setBox.get(PrefKeys.discoverContentType) ?? "BOLI";
    slidableActionEnabled.value =
        setBox.get(PrefKeys.slidableActionEnabled) ?? true;
    if (setBox.containsKey(PrefKeys.piped)) {
      isLinkedWithPiped.value = setBox.get(PrefKeys.piped)['isLoggedIn'];
    }
    stopPlaybackOnSwipeAway.value =
        setBox.get('stopPlaybackOnSwipeAway') ?? false;
    if (GetPlatform.isAndroid) {
      await refreshIgnoringBatteryOptimizations();
      await _requestIgnoringBatteryOptimizationsOnInstall();
    }
    autoDownloadFavoriteSongEnabled.value =
        setBox.get(PrefKeys.autoDownloadFavoriteSongEnabled) ?? false;
    final normalizedLibraryFirstTab =
        SettingsScreenController.normalizeLibraryFirstTab(
          setBox.get(PrefKeys.libraryFirstTab),
        );
    libraryFirstTab.value = normalizedLibraryFirstTab;
    await setBox.put(PrefKeys.libraryFirstTab, normalizedLibraryFirstTab);
  }

  Future<void> checkUpdate(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      snackbar(context, "checkingUpdate".tr, size: SanckBarSize.MEDIUM),
    );
    final info = await checkNewVersion();
    if (info != null) {
      await Get.dialog(
        NewVersionDialog(
          updateInfo: info,
          disableStartupPopupOnUpdateTap: true,
        ),
      );
    } else {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, "upToDate".tr, size: SanckBarSize.MEDIUM),
      );
    }
  }

  Future<void> changeUpdateChannel(String? val) async {
    final next = val == 'rolling'
        ? UpdateChannel.rolling
        : UpdateChannel.stable;
    updateChannel.value = next;
    await setBox.put(PrefKeys.updateChannel, next.name);
    if (updateCheckFlag) await checkNewVersion();
  }

  Future<void> setDeveloperSettingsEnabled(bool value) async {
    developerSettingsEnabled.value = value;
    await setBox.put(PrefKeys.developerSettingsEnabled, value);
    if (value) {
      refreshDeveloperSettingValues();
    } else {
      developerSettingValues.clear();
    }
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
        _formatDeveloperValue(setBox.get(PrefKeys.newVersionVisibility)),
      ),
      DeveloperSettingValue("update.channel", updateChannel.value.name),
      DeveloperSettingValue(
        "update.isNewVersionAvailable",
        isNewVersionAvailable.value.toString(),
      ),
      DeveloperSettingValue(
        "update.info",
        _formatDeveloperValue(_updateInfoForDeveloperView()),
      ),
    ];

    final appPrefs = setBox.keys.toList()
      ..sort((a, b) => a.toString().compareTo(b.toString()));
    for (final key in appPrefs) {
      final keyName = key.toString();
      values.add(
        DeveloperSettingValue(
          "appPrefs.$keyName",
          _formatDeveloperValue(setBox.get(key), key: keyName),
        ),
      );
    }

    developerSettingValues.assignAll(values);
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
    await Get.updateLocale(Locale(val!));
    Get.find<MusicServiceContract>().hlCode = val;
    (Get.find<HomeScreenController>().loadContentFromNetwork(silent: true),);
    currentAppLanguageCode.value = val;
    await setBox.put(PrefKeys.currentAppLanguageCode, val);
  }

  Future<void> setContentNumber(int? no) async {
    noOfHomeScreenContent.value = no!;
    await setBox.put(PrefKeys.noOfHomeScreenContent, no);
  }

  void setStreamingQuality(dynamic val) {
    (setBox.put(PrefKeys.streamingQuality, AudioQuality.values.indexOf(val)),);
    streamingQuality.value = val;
    if (Get.isRegistered<AudioHandler>()) {
      unawaited(Get.find<AudioHandler>().customAction("preloadConfigChanged"));
    }
  }

  Future<void> setPlaybackMode(PlaybackMode? mode) async {
    final selectedMode = mode ?? PlaybackMode.classic;
    await setBox.put(PrefKeys.playbackMode, selectedMode.index);
    playbackMode.value = selectedMode;
    if (selectedMode == PlaybackMode.classic) {
      playbackPreloadRange.value = 0;
      await setBox.put(PrefKeys.playbackPreloadRange, 0);
    } else if (playbackPreloadRange.value == 0) {
      playbackPreloadRange.value = 1;
      await setBox.put(PrefKeys.playbackPreloadRange, 1);
    }
    if (Get.isRegistered<AudioHandler>()) {
      await Get.find<AudioHandler>().customAction("updatePlaybackMode", {
        "mode": selectedMode.index,
      });
      await Get.find<AudioHandler>().customAction(
        "updatePlaybackPreloadRange",
        {"range": playbackPreloadRange.value},
      );
    }
  }

  Future<void> setPlaybackPreloadRange(int? value) async {
    final range = (value ?? 0).clamp(0, 5).toInt();
    await setBox.put(PrefKeys.playbackPreloadRange, range);
    playbackPreloadRange.value = range;
    if (range > 0 && playbackMode.value != PlaybackMode.preloaded) {
      await setPlaybackMode(PlaybackMode.preloaded);
    }
    if (Get.isRegistered<AudioHandler>()) {
      await Get.find<AudioHandler>().customAction(
        "updatePlaybackPreloadRange",
        {"range": range},
      );
    }
  }

  Future<void> setPlayerUi(dynamic val) async {
    final playerCon = Get.find<PlayerController>();
    await setBox.put(PrefKeys.playerUi, val);
    if (val == 1 && playerCon.gesturePlayerStateAnimationController == null) {
      playerCon.initGesturePlayerStateAnimationController();
    }

    playerUi.value = val;
  }

  Future<void> enableBottomNavBar(bool val) async {
    final homeScrCon = Get.find<HomeScreenController>();
    final playerCon = Get.find<PlayerController>();
    if (val) {
      homeScrCon.onSideBarTabSelected(3);
      isBottomNavBarEnabled.value = true;
    } else {
      isBottomNavBarEnabled.value = false;
      homeScrCon.onSideBarTabSelected(5);
    }
    if (!Get.find<PlayerController>().initFlagForPlayer) {
      playerCon.playerPanelMinHeight.value = val
          ? 75.0
          : 75.0 + Get.mediaQuery.viewPadding.bottom;
    }
    await setBox.put(PrefKeys.isBottomNavBarEnabled, val);
  }

  Future<void> toggleSlidableAction(bool val) async {
    await setBox.put(PrefKeys.slidableActionEnabled, val);
    slidableActionEnabled.value = val;
  }

  Future<void> changeDownloadingFormat(String? val) async {
    await setBox.put(PrefKeys.downloadingFormat, val);
    downloadingFormat.value = val!;
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

    await setBox.put(PrefKeys.exportLocationPath, pickedFolderPath);
    exportLocationPath.value = pickedFolderPath;
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

    await setBox.put(PrefKeys.downloadLocationPath, pickedFolderPath);
    downloadLocationPath.value = pickedFolderPath;
  }

  Future<void> disableTransitionAnimation(bool val) async {
    await setBox.put(PrefKeys.isTransitionAnimationDisabled, val);
    isTransitionAnimationDisabled.value = val;
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
    await setBox.put(PrefKeys.downloadLocationPath, defaultPath);
    downloadLocationPath.value = defaultPath;
  }

  Future<void> onThemeChange(dynamic val) async {
    (setBox.put(PrefKeys.themeModeType, ThemeType.values.indexOf(val)),);
    themeModeType.value = val;
    await Get.find<ThemeController>().changeThemeModeType(val);
  }

  Future<void> onContentChange(dynamic value) async {
    await setBox.put(PrefKeys.discoverContentType, value);
    discoverContentType.value = value;
    await Get.find<HomeScreenController>().changeDiscoverContent(value);
  }

  Future<void> toggleCachingSongsValue(bool value) async {
    await setBox.put(PrefKeys.cacheSongs, value);
    cacheSongs.value = value;
  }

  Future<void> toggleSkipSilence(bool val) async {
    await Get.find<PlayerController>().toggleSkipSilence(val);
    await setBox.put(PrefKeys.skipSilenceEnabled, val);
    skipSilenceEnabled.value = val;
  }

  Future<void> toggleLoudnessNormalization(bool val) async {
    await Get.find<PlayerController>().toggleLoudnessNormalization(val);
    await setBox.put(PrefKeys.loudnessNormalizationEnabled, val);
    loudnessNormalizationEnabled.value = val;
  }

  Future<void> toggleRestorePlaybackSession(bool val) async {
    await setBox.put(PrefKeys.restorePlaybackSession, val);
    restorePlaybackSession.value = val;
  }

  Future<void> toggleCacheHomeScreenData(bool val) async {
    await setBox.put(PrefKeys.cacheHomeScreenData, val);
    cacheHomeScreenData.value = val;
    if (!val) {
      (
        Hive.openBox(BoxNames.homeScreenData).then((box) async {
          await box.clear();
          await box.close();
        }),
      );
    } else {
      await Hive.openBox(BoxNames.homeScreenData);
      (Get.find<HomeScreenController>().cachedHomeScreenData(updateAll: true),);
    }
  }

  Future<void> resetRecoverableAppState() async {
    final homeScreenData = await Hive.openBox(BoxNames.homeScreenData);
    await homeScreenData.clear();

    final prevSessionData = await Hive.openBox(BoxNames.prevSessionData);
    await prevSessionData.clear();
    await Hive.box(BoxNames.songsUrlCache).clear();
    await setBox.delete(PrefKeys.homeScreenDataTime);

    final homeController = Get.find<HomeScreenController>();
    homeController.tabIndex.value = 0;
    homeController.isHomeScreenOnTop.value = true;
    homeController.networkError.value = false;
    homeController.isContentFetched.value = false;

    final nestedNavigator = Get.nestedKey(
      ScreenNavigationSetup.id,
    )?.currentState;
    nestedNavigator?.popUntil(
      (route) => route.settings.name == ScreenNavigationSetup.homeScreen,
    );

    final playerController = Get.find<PlayerController>();
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
    if (!GetPlatform.isAndroid) return;
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
    if (!GetPlatform.isAndroid) return;
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
    await setBox.put(PrefKeys.autoDownloadFavoriteSongEnabled, val);
    autoDownloadFavoriteSongEnabled.value = val;
  }

  Future<void> toggleBackgroundPlay(bool val) async {
    await setBox.put(PrefKeys.backgroundPlayEnabled, val);
    backgroundPlayEnabled.value = val;
  }

  Future<void> toggleKeepScreenAwake(bool val) async {
    await setBox.put(PrefKeys.keepScreenAwake, val);
    keepScreenAwake.value = val;
    try {
      if (val) {
        // enable wakelock immediately if music is playing
        if (Get.find<PlayerController>().buttonState.value ==
            PlayButtonState.playing) {
          await AppPlatformService.setKeepScreenAwake(true);
        }
      } else {
        await AppPlatformService.setKeepScreenAwake(false);
      }
    } catch (e) {
      // ignore if player/controller not available
    }
  }

  Future<void> openBatteryOptimizationSettings() async {
    if (!GetPlatform.isAndroid) return;

    await setBox.put(PrefKeys.batteryOptimizationPromptShown, true);
    final isIgnoring = await Permission.ignoreBatteryOptimizations.isGranted;
    if (isIgnoring) {
      await openAppSettings();
    } else {
      await Permission.ignoreBatteryOptimizations.request();
    }
    await refreshIgnoringBatteryOptimizations();
  }

  Future<void> refreshIgnoringBatteryOptimizations() async {
    if (!GetPlatform.isAndroid) return;
    isIgnoringBatteryOptimizations.value =
        await Permission.ignoreBatteryOptimizations.isGranted;
  }

  Future<void> _requestIgnoringBatteryOptimizationsOnInstall() async {
    if (setBox.get(PrefKeys.batteryOptimizationPromptShown) == true ||
        isIgnoringBatteryOptimizations.isTrue) {
      return;
    }

    await setBox.put(PrefKeys.batteryOptimizationPromptShown, true);
    await Permission.ignoreBatteryOptimizations.request();
    await refreshIgnoringBatteryOptimizations();
  }

  Future<void> toggleAutoOpenPlayer(bool val) async {
    await setBox.put(PrefKeys.autoOpenPlayer, val);
    autoOpenPlayer.value = val;
  }

  Future<void> setFirstLibraryTab(int index) async {
    final normalizedIndex = SettingsScreenController.normalizeLibraryFirstTab(
      index,
    );
    await setBox.put(PrefKeys.libraryFirstTab, normalizedIndex);
    libraryFirstTab.value = normalizedIndex;
  }

  static int normalizeLibraryFirstTab(dynamic value) {
    if (value is! int || value < 0 || value >= libraryTabKeys.length) {
      return 0;
    }
    return value;
  }

  Future<void> unlinkPiped() async {
    await Get.find<PipedServices>().logout();
    isLinkedWithPiped.value = false;
    Get.find<LibraryPlaylistsController>().removePipedPlaylists();
    final box = await Hive.openBox('blacklistedPlaylist');
    await box.clear();
    ScaffoldMessenger.of(Get.context!).showSnackBar(
      snackbar(Get.context!, "unlinkAlert".tr, size: SanckBarSize.MEDIUM),
    );
    await box.close();
  }

  Future<void> resetAppSettingsToDefault() async {
    await setBox.clear();
  }

  Future<void> toggleStopPlaybackOnSwipeAway(bool val) async {
    await setBox.put('stopPlaybackOnSwipeAway', val);
    stopPlaybackOnSwipeAway.value = val;
  }

  Future<void> closeAllDatabases() async {
    await Hive.close();
  }

  Future<String> get dbDir async {
    if (GetPlatform.isDesktop) {
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
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box(boxName).flush();
      }
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

    final downloadsBox = await Hive.openBox(BoxNames.songDownloads);
    for (final key in downloadsBox.keys.toList()) {
      final song = downloadsBox.get(key);
      if (song is! Map) continue;

      final updatedSong = Map<dynamic, dynamic>.from(song);
      updatedSong['url'] = _rewriteClonePath(
        updatedSong['url'],
        oldMusicPath,
        newMusicPath,
      );

      final streamInfo = updatedSong['streamInfo'];
      if (streamInfo is List && streamInfo.length > 1 && streamInfo[1] is Map) {
        final streamInfoData = Map<dynamic, dynamic>.from(streamInfo[1]);
        streamInfoData['url'] = _rewriteClonePath(
          streamInfoData['url'],
          oldMusicPath,
          newMusicPath,
        );
        final updatedStreamInfo = List<dynamic>.from(streamInfo);
        updatedStreamInfo[1] = streamInfoData;
        updatedSong['streamInfo'] = updatedStreamInfo;
      }

      await downloadsBox.put(key, updatedSong);
    }

    final appPrefsBox = await Hive.openBox(BoxNames.appPrefs);
    final downloadPath = appPrefsBox.get(PrefKeys.downloadLocationPath);
    final updatedDownloadPath = _rewriteClonePath(
      downloadPath,
      oldMusicPath,
      newMusicPath,
    );
    if (updatedDownloadPath != downloadPath) {
      await appPrefsBox.put(PrefKeys.downloadLocationPath, updatedDownloadPath);
    }

    await downloadsBox.flush();
    await appPrefsBox.flush();
  }

  dynamic _rewriteClonePath(dynamic value, String oldPath, String newPath) {
    if (value is! String) return value;
    if (value.startsWith(oldPath)) {
      return value.replaceFirst(oldPath, newPath);
    }
    return value;
  }

  void _showSettingsSnack(String message) {
    final context = Get.context;
    if (context == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(snackbar(context, message, size: SanckBarSize.MEDIUM));
  }
}
