import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/permission_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:terminate_restart/terminate_restart.dart';

import '../../../utils/update_check_flag_file.dart';
import '/services/piped_service.dart';
import '../Library/library_controller.dart';
import '../../widgets/snackbar.dart';
import '../../../utils/helper.dart';
import '/services/music_service.dart';
import '/ui/player/player_controller.dart';
import '../Home/home_screen_controller.dart';
import '/ui/utils/theme_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '/services/constant.dart';
import '../../navigator.dart';

class SettingsScreenController extends GetxController {
  late String _supportDir;
  final cacheSongs = false.obs;
  final setBox = Hive.box(BoxNames.appPrefs);
  final themeModetype = ThemeType.dynamic.obs;
  final skipSilenceEnabled = false.obs;
  final loudnessNormalizationEnabled = false.obs;
  final noOfHomeScreenContent = 3.obs;
  final streamingQuality = AudioQuality.High.obs;
  final playerUi = 0.obs;
  final slidableActionEnabled = true.obs;
  final isIgnoringBatteryOptimizations = false.obs;
  final autoOpenPlayer = false.obs;
  final discoverContentType = "QP".obs;
  final isNewVersionAvailable = false.obs;
  final isLinkedWithPiped = false.obs;
  final stopPlyabackOnSwipeAway = false.obs;
  final currentAppLanguageCode = "en".obs;
  final downloadLocationPath = "".obs;
  final exportLocationPath = "".obs;
  final downloadingFormat = "".obs;
  final autoDownloadFavoriteSongEnabled = false.obs;
  final isTransitionAnimationDisabled = false.obs;
  final isBottomNavBarEnabled = false.obs;
  final backgroundPlayEnabled = true.obs;
  final keepScreenAwake = false.obs;
  final restorePlaybackSession = false.obs;
  final cacheHomeScreenData = true.obs;
  final currentVersion = "V1.12.2";

  @override
  void onInit() {
    _setInitValue();
    if (updateCheckFlag) _checkNewVersion();
    _createInAppSongDownDir();
    super.onInit();
  }

  get currentVision => currentVersion;
  get isCurrentPathsupportDownDir =>
      "$_supportDir/Music" == downloadLocationPath.toString();
  String get supportDirPath => _supportDir;

  _checkNewVersion() {
    newVersionCheck(currentVersion)
        .then((value) => isNewVersionAvailable.value = value);
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
    isBottomNavBarEnabled.value = isDesktop
        ? false
        : (setBox.get(PrefKeys.isBottomNavBarEnabled) ?? false);
    noOfHomeScreenContent.value =
        setBox.get(PrefKeys.noOfHomeScreenContent) ?? 3;
    isTransitionAnimationDisabled.value =
        setBox.get(PrefKeys.isTransitionAnimationDisabled) ?? false;
    cacheSongs.value = setBox.get(PrefKeys.cacheSongs) ?? false;
    themeModetype.value =
        ThemeType.values[setBox.get(PrefKeys.themeModeType) ?? 0];
    skipSilenceEnabled.value =
        isDesktop ? false : setBox.get(PrefKeys.skipSilenceEnabled);
    loudnessNormalizationEnabled.value = isDesktop
        ? false
        : (setBox.get(PrefKeys.loudnessNormalizationEnabled) ?? false);
    autoOpenPlayer.value = (setBox.get(PrefKeys.autoOpenPlayer) ?? true);
    restorePlaybackSession.value =
        setBox.get(PrefKeys.restorePlaybackSession) ?? false;
    cacheHomeScreenData.value =
        setBox.get(PrefKeys.cacheHomeScreenData) ?? true;
    streamingQuality.value =
        AudioQuality.values[setBox.get(PrefKeys.streamingQuality)];
    playerUi.value = isDesktop ? 0 : (setBox.get(PrefKeys.playerUi) ?? 0);
    backgroundPlayEnabled.value =
        setBox.get(PrefKeys.backgroundPlayEnabled) ?? true;
    keepScreenAwake.value =
        setBox.get(PrefKeys.keepScreenAwake) ?? GetPlatform.isDesktop
            ? true
            : false;
    final downloadPath = setBox.get(PrefKeys.downloadLocationPath) ??
        await _createInAppSongDownDir();
    downloadLocationPath.value =
        (isDesktop && downloadPath.contains("emulated"))
            ? await _createInAppSongDownDir()
            : downloadPath;

    exportLocationPath.value =
        setBox.get(PrefKeys.exportLocationPath) ?? "/storage/emulated/0/Music";
    downloadingFormat.value = setBox.get(PrefKeys.downloadingFormat) ?? "m4a";
    discoverContentType.value =
        setBox.get(PrefKeys.discoverContentType) ?? "QP";
    slidableActionEnabled.value =
        setBox.get(PrefKeys.slidableActionEnabled) ?? true;
    if (setBox.containsKey(PrefKeys.piped)) {
      isLinkedWithPiped.value = setBox.get(PrefKeys.piped)['isLoggedIn'];
    }
    stopPlyabackOnSwipeAway.value =
        setBox.get('stopPlyabackOnSwipeAway') ?? false;
    if (GetPlatform.isAndroid) {
      isIgnoringBatteryOptimizations.value =
          (await Permission.ignoreBatteryOptimizations.isGranted);
    }
    autoDownloadFavoriteSongEnabled.value =
        setBox.get(PrefKeys.autoDownloadFavoriteSongEnabled) ?? false;
  }

  void setAppLanguage(String? val) {
    Get.updateLocale(Locale(val!));
    Get.find<MusicServices>().hlCode = val;
    Get.find<HomeScreenController>().loadContentFromNetwork(silent: true);
    currentAppLanguageCode.value = val;
    setBox.put(PrefKeys.currentAppLanguageCode, val);
  }

  void setContentNumber(int? no) {
    noOfHomeScreenContent.value = no!;
    setBox.put(PrefKeys.noOfHomeScreenContent, no);
  }

  void setStreamingQuality(dynamic val) {
    setBox.put(PrefKeys.streamingQuality, AudioQuality.values.indexOf(val));
    streamingQuality.value = val;
  }

  void setPlayerUi(dynamic val) {
    final playerCon = Get.find<PlayerController>();
    setBox.put(PrefKeys.playerUi, val);
    if (val == 1 && playerCon.gesturePlayerStateAnimationController == null) {
      playerCon.initGesturePlayerStateAnimationController();
    }

    playerUi.value = val;
  }

  void enableBottomNavBar(bool val) {
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
      playerCon.playerPanelMinHeight.value =
          val ? 75.0 : 75.0 + Get.mediaQuery.viewPadding.bottom;
    }
    setBox.put(PrefKeys.isBottomNavBarEnabled, val);
  }

  void toggleSlidableAction(bool val) {
    setBox.put(PrefKeys.slidableActionEnabled, val);
    slidableActionEnabled.value = val;
  }

  void changeDownloadingFormat(String? val) {
    setBox.put(PrefKeys.downloadingFormat, val);
    downloadingFormat.value = val!;
  }

  Future<void> setExportedLocation() async {
    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    final String? pickedFolderPath = await FilePicker.platform
        .getDirectoryPath(dialogTitle: "Select export file folder");
    if (pickedFolderPath == '/' || pickedFolderPath == null) {
      return;
    }

    setBox.put(PrefKeys.exportLocationPath, pickedFolderPath);
    exportLocationPath.value = pickedFolderPath;
  }

  Future<void> setDownloadLocation() async {
    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    final String? pickedFolderPath = await FilePicker.platform
        .getDirectoryPath(dialogTitle: "Select downloads folder");
    if (pickedFolderPath == '/' || pickedFolderPath == null) {
      return;
    }

    setBox.put(PrefKeys.downloadLocationPath, pickedFolderPath);
    downloadLocationPath.value = pickedFolderPath;
  }

  void disableTransitionAnimation(bool val) {
    setBox.put(PrefKeys.isTransitionAnimationDisabled, val);
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

  void resetDownloadLocation() {
    final defaultPath = "$_supportDir/Music";
    setBox.put(PrefKeys.downloadLocationPath, defaultPath);
    downloadLocationPath.value = defaultPath;
  }

  void onThemeChange(dynamic val) {
    setBox.put(PrefKeys.themeModeType, ThemeType.values.indexOf(val));
    themeModetype.value = val;
    Get.find<ThemeController>().changeThemeModeType(val);
  }

  void onContentChange(dynamic value) {
    setBox.put(PrefKeys.discoverContentType, value);
    discoverContentType.value = value;
    Get.find<HomeScreenController>().changeDiscoverContent(value);
  }

  void toggleCachingSongsValue(bool value) {
    setBox.put(PrefKeys.cacheSongs, value);
    cacheSongs.value = value;
  }

  void toggleSkipSilence(bool val) {
    Get.find<PlayerController>().toggleSkipSilence(val);
    setBox.put(PrefKeys.skipSilenceEnabled, val);
    skipSilenceEnabled.value = val;
  }

  void toggleLoudnessNormalization(bool val) {
    Get.find<PlayerController>().toggleLoudnessNormalization(val);
    setBox.put(PrefKeys.loudnessNormalizationEnabled, val);
    loudnessNormalizationEnabled.value = val;
  }

  void toggleRestorePlaybackSession(bool val) {
    setBox.put(PrefKeys.restorePlaybackSession, val);
    restorePlaybackSession.value = val;
  }

  Future<void> toggleCacheHomeScreenData(bool val) async {
    setBox.put(PrefKeys.cacheHomeScreenData, val);
    cacheHomeScreenData.value = val;
    if (!val) {
      Hive.openBox(BoxNames.homeScreenData).then((box) async {
        await box.clear();
        await box.close();
      });
    } else {
      await Hive.openBox(BoxNames.homeScreenData);
      Get.find<HomeScreenController>().cachedHomeScreenData(updateAll: true);
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
    homeController.isHomeSreenOnTop.value = true;
    homeController.networkError.value = false;
    homeController.isContentFetched.value = false;

    final nestedNavigator =
        Get.nestedKey(ScreenNavigationSetup.id)?.currentState;
    nestedNavigator?.popUntil(
        (route) => route.settings.name == ScreenNavigationSetup.homeScreen);

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

    final String? pickedFolderPath = await FilePicker.platform
        .getDirectoryPath(dialogTitle: "Select clone export folder");
    if (pickedFolderPath == '/' || pickedFolderPath == null) {
      return;
    }

    try {
      await _flushOpenCloneBoxes();

      final packageInfo = await PackageInfo.fromPlatform();
      final sourceSupportDir = (await getApplicationSupportDirectory()).path;
      final sourceDbDir = await dbDir;
      final cloneDir = Directory(
          "$pickedFolderPath/HarmonyMusicClone/${DateTime.now().millisecondsSinceEpoch}");
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
      await File("${cloneDir.path}/manifest.json")
          .writeAsString(const JsonEncoder.withIndent("  ").convert(manifest));

      _showSettingsSnack("Clone package exported");
      printINFO("Developer clone exported to ${cloneDir.path}",
          tag: LogTags.settings);
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

    final String? cloneFolderPath = await FilePicker.platform
        .getDirectoryPath(dialogTitle: "Select HarmonyMusicClone package");
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
      await TerminateRestart.instance.restartApp(
        options: const TerminateRestartOptions(terminate: true),
      );
    } catch (e, stackTrace) {
      printERROR("Developer clone import failed: $e", tag: LogTags.settings);
      printERROR(stackTrace, tag: LogTags.settings);
      _showSettingsSnack("Clone import failed");
    }
  }

  void toggleAutoDownloadFavoriteSong(bool val) {
    setBox.put(PrefKeys.autoDownloadFavoriteSongEnabled, val);
    autoDownloadFavoriteSongEnabled.value = val;
  }

  void toggleBackgroundPlay(bool val) {
    setBox.put(PrefKeys.backgroundPlayEnabled, val);
    backgroundPlayEnabled.value = val;
  }

  void toggleKeepScreenAwake(bool val) {
    setBox.put(PrefKeys.keepScreenAwake, val);
    keepScreenAwake.value = val;
    try {
      if (val) {
        // enable wakelock immediately if music is playing
        if (Get.find<PlayerController>().buttonState.value ==
            PlayButtonState.playing) {
          WakelockPlus.enable();
        }
      } else {
        WakelockPlus.disable();
      }
    } catch (e) {
      // ignore if player/controller not available
    }
  }

  Future<void> enableIgnoringBatteryOptimizations() async {
    await Permission.ignoreBatteryOptimizations.request();
    isIgnoringBatteryOptimizations.value =
        await Permission.ignoreBatteryOptimizations.isGranted;
  }

  void toggleAutoOpenPlayer(bool val) {
    setBox.put(PrefKeys.autoOpenPlayer, val);
    autoOpenPlayer.value = val;
  }

  Future<void> unlinkPiped() async {
    Get.find<PipedServices>().logout();
    isLinkedWithPiped.value = false;
    Get.find<LibraryPlaylistsController>().removePipedPlaylists();
    final box = await Hive.openBox('blacklistedPlaylist');
    box.clear();
    ScaffoldMessenger.of(Get.context!).showSnackBar(
        snackbar(Get.context!, "unlinkAlert".tr, size: SanckBarSize.MEDIUM));
    box.close();
  }

  Future<void> resetAppSettingsToDefault() async {
    await setBox.clear();
  }

  void toggleStopPlyabackOnSwipeAway(bool val) {
    setBox.put('stopPlyabackOnSwipeAway', val);
    stopPlyabackOnSwipeAway.value = val;
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
      printWarning("Clone source folder missing: ${sourceDir.path}",
          tag: LogTags.settings);
      return;
    }
    await targetDir.create(recursive: true);

    await for (final entity in sourceDir.list(recursive: false)) {
      if (entity is! File) continue;
      if (extensionFilter != null && !entity.path.endsWith(extensionFilter)) {
        continue;
      }
      if (!await entity.exists()) {
        printWarning("Skipping missing clone file: ${entity.path}",
            tag: LogTags.settings);
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
    final updatedDownloadPath =
        _rewriteClonePath(downloadPath, oldMusicPath, newMusicPath);
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
    ScaffoldMessenger.of(context).showSnackBar(
      snackbar(context, message, size: SanckBarSize.MEDIUM),
    );
  }
}
