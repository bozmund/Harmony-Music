import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../app/navigation/app_navigator.dart';
import '../../../domain/repositories/home_repository.dart';
import '../../../domain/repositories/settings_repository.dart';
import '/models/media_Item_builder.dart';
import '/ui/navigator.dart';
import '/ui/player/player_controller.dart';
import '../../../utils/update_check_flag_file.dart';
import '../../../utils/helper.dart';
import '/models/album.dart';
import '/models/playlist.dart';
import '/models/quick_picks.dart';
import '/services/music_service.dart';
import '/services/app_contracts.dart';
import '/services/release_prompt.dart';
import '../Settings/settings_screen_controller.dart';
import '/ui/widgets/new_version_dialog.dart';
import '/ui/widgets/release_prompt_dialog.dart';

class HomeScreenController extends ChangeNotifier {
  HomeScreenController({
    required SettingsRepository settingsRepository,
    required HomeRepository homeRepository,
    required MusicServiceContract musicService,
    required AudioHandler audioHandler,
    required SettingsScreenController Function() settingsScreenController,
    required PlayerController Function() playerController,
  }) : _settingsRepository = settingsRepository,
       _homeRepository = homeRepository,
       _musicServices = musicService,
       _audioHandler = audioHandler,
       _settingsScreenController = settingsScreenController,
       _playerController = playerController;

  final SettingsRepository _settingsRepository;
  final HomeRepository _homeRepository;
  final MusicServiceContract _musicServices;
  final AudioHandler _audioHandler;
  final SettingsScreenController Function() _settingsScreenController;
  final PlayerController Function() _playerController;
  StreamSubscription<dynamic>? _audioEventSubscription;
  bool isContentFetched = false;
  int tabIndex = 0;
  bool networkError = false;
  QuickPicks quickPicks = QuickPicks([]);
  List middleContent = [];
  List fixedContent = [];
  bool showVersionDialog = true;
  //isHomeScreenOnTop var only useful if bottom nav enabled
  bool isHomeScreenOnTop = true;
  final List<ScrollController> contentScrollControllers = [];
  bool _updateDialogPending = false;
  bool _updateDialogShown = false;
  bool reverseAnimationTransition = false;
  bool _closed = false;

  Future<void> init() async {
    _listenForAudioEvents();
    await _settingsScreenController().clearCachedUpdateApks();
    await loadContent();
    // Ask the release's one-time question (e.g. the 6.0.0 channel choice)
    // before checking for updates: the answer decides which channel the
    // update check follows.
    await _maybeShowReleasePrompt();
    if (updateCheckFlag) {
      _checkNewVersion();
    } else if (kDebugMode) {
      _showDebugUpdateDialog();
    }
  }

  void _listenForAudioEvents() {
    _audioEventSubscription ??= _audioHandler.customEvent.listen((event) async {
      if (event is Map && event['eventType'] == 'cacheHomeScreenData') {
        await cachedHomeScreenData();
      }
    });
  }

  Future<void> loadContent() async {
    final isCachedHomeScreenDataEnabled = _settingsRepository
        .getCacheHomeScreenData();
    if (isCachedHomeScreenDataEnabled) {
      final loaded = await loadContentFromDb();

      if (loaded) {
        final currTimeSecsDiff =
            DateTime.now().millisecondsSinceEpoch -
            (_settingsRepository.getHomeScreenDataTime() ??
                DateTime.now().millisecondsSinceEpoch);
        if (currTimeSecsDiff / 1000 > 3600 * 8) {
          await loadContentFromNetwork(silent: true);
        }
      } else {
        await loadContentFromNetwork();
      }
    } else {
      await loadContentFromNetwork();
    }
  }

  Future<bool> loadContentFromDb() async {
    final homeScreenData = await _homeRepository.getAllHomeData();
    if (homeScreenData.isNotEmpty) {
      final String quickPicksType = homeScreenData["quickPicksType"];
      final List quickPicksData = homeScreenData["quickPicks"];
      final List middleContentData = homeScreenData["middleContent"] ?? [];
      final List fixedContentData = homeScreenData["fixedContent"] ?? [];
      quickPicks = QuickPicks(
        quickPicksData.map((e) => MediaItemBuilder.fromJson(e)).toList(),
        title: quickPicksType,
      );
      middleContent = middleContentData
          .map(
            (e) => e["type"] == "Album Content"
                ? AlbumContent.fromJson(e)
                : PlaylistContent.fromJson(e),
          )
          .toList();
      fixedContent = fixedContentData
          .map(
            (e) => e["type"] == "Album Content"
                ? AlbumContent.fromJson(e)
                : PlaylistContent.fromJson(e),
          )
          .toList();
      isContentFetched = true;
      _notifyHomeChanged();
      printINFO("Loaded from offline db");
      return true;
    } else {
      return false;
    }
  }

  Future<void> loadContentFromNetwork({bool silent = false}) async {
    String contentType = _settingsRepository.getDiscoverContentType();

    networkError = false;
    _notifyHomeChanged();
    try {
      List middleContentTemp = [];
      final homeContentListMap = await _musicServices.getHome(
        limit: _settingsScreenController().noOfHomeScreenContent.value,
      );
      if (contentType == "TR") {
        final index = homeContentListMap.indexWhere(
          (element) => element['title'] == "Trending",
        );
        if (index != -1 && index != 0) {
          quickPicks = QuickPicks(
            List<MediaItem>.from(homeContentListMap[index]["contents"]),
            title: "Trending",
          );
        } else if (index == -1) {
          List charts = await _musicServices.getCharts(contentType);
          final index = charts.indexWhere(
            (element) =>
                element['title'] ==
                (contentType == "TMV" ? "Top Music Videos" : "Trending"),
          );
          if (index != -1) {
            quickPicks = QuickPicks(
              List<MediaItem>.from(charts[index]["contents"]),
              title: charts[index]['title'],
            );
            middleContentTemp.addAll(charts);
          }
        }
      } else if (contentType == "TMV") {
        final index = homeContentListMap.indexWhere(
          (element) => element['title'] == "Top music videos",
        );
        if (index != -1 && index != 0) {
          final con = homeContentListMap.removeAt(index);
          quickPicks = QuickPicks(
            List<MediaItem>.from(con["contents"]),
            title: con["title"],
          );
        } else if (index == -1) {
          List charts = await _musicServices.getCharts(contentType);
          final index = charts.indexWhere(
            (element) =>
                element['title'] ==
                (contentType == "TMV" ? "Top Music Videos" : "Trending"),
          );
          if (index != -1) {
            quickPicks = QuickPicks(
              List<MediaItem>.from(charts[index]["contents"]),
              title: charts[index]["title"],
            );
            middleContentTemp.addAll(charts);
          }
        }
      } else if (contentType == "BOLI") {
        try {
          final songId = _settingsRepository.getRecentSongId();
          if (songId != null) {
            final rel = await _musicServices.getContentRelatedToSong(
              songId,
              getContentHlCode(),
            );
            final con = rel.removeAt(0);
            quickPicks = QuickPicks(List<MediaItem>.from(con["contents"]));
            middleContentTemp.addAll(rel);
          }
        } catch (e) {
          printERROR(
            "Seems Based on last interaction content currently not available!",
          );
        }
      }

      if (quickPicks.songList.isEmpty) {
        final con =
            _takeContentSectionByTitle(homeContentListMap, "Quick picks") ??
            _takeFirstSongSection(homeContentListMap);
        if (con != null) {
          quickPicks = QuickPicks(
            List<MediaItem>.from(con["contents"].whereType<MediaItem>()),
            title: con["title"],
          );
        }
      }

      middleContent = _setContentList(middleContentTemp);
      fixedContent = _setContentList(homeContentListMap);

      if (quickPicks.songList.isEmpty &&
          middleContent.isEmpty &&
          fixedContent.isEmpty) {
        throw Exception("Home content did not include usable sections");
      }

      isContentFetched = true;
      _notifyHomeChanged();

      // set home content last update time
      await cachedHomeScreenData(updateAll: true);
      await _settingsRepository.setHomeScreenDataTime(
        DateTime.now().millisecondsSinceEpoch,
      );
    } on NetworkError catch (r) {
      printERROR("Home Content not loaded due to ${r.message}");
      await Future.delayed(const Duration(seconds: 1));
      networkError = !silent;
      _notifyHomeChanged();
    } catch (r) {
      printERROR("Home Content not loaded due to $r");
      await Future.delayed(const Duration(seconds: 1));
      networkError = !silent;
      _notifyHomeChanged();
    }
  }

  Map<String, dynamic>? _takeContentSectionByTitle(
    List<dynamic> contentList,
    String title,
  ) {
    final index = contentList.indexWhere(
      (element) => element['title'] == title,
    );
    if (index == -1) return null;
    return Map<String, dynamic>.from(contentList.removeAt(index));
  }

  Map<String, dynamic>? _takeFirstSongSection(List<dynamic> contentList) {
    final index = contentList.indexWhere((element) {
      final contents = element["contents"];
      return contents is List && contents.whereType<MediaItem>().isNotEmpty;
    });
    if (index == -1) return null;
    return Map<String, dynamic>.from(contentList.removeAt(index));
  }

  List _setContentList(List<dynamic> contents) {
    List contentTemp = [];
    for (var content in contents) {
      if (content["contents"] is! List || content["contents"].isEmpty) {
        continue;
      }
      if (content["contents"][0].runtimeType == Playlist) {
        final tmp = PlaylistContent(
          playlistList: content["contents"].whereType<Playlist>().toList(),
          title: content["title"],
        );
        if (tmp.playlistList.length >= 2) {
          contentTemp.add(tmp);
        }
      } else if (content["contents"][0].runtimeType == Album) {
        final tmp = AlbumContent(
          albumList: content["contents"].whereType<Album>().toList(),
          title: content["title"],
        );
        if (tmp.albumList.length >= 2) {
          contentTemp.add(tmp);
        }
      }
    }
    return contentTemp;
  }

  Future<void> changeDiscoverContent(dynamic val, {String? songId}) async {
    QuickPicks? quickPicks_;
    if (val == 'QP') {
      final homeContentListMap = await _musicServices.getHome(limit: 3);
      quickPicks_ = QuickPicks(
        List<MediaItem>.from(homeContentListMap[0]["contents"]),
        title: homeContentListMap[0]["title"],
      );
    } else if (val == "TMV" || val == 'TR') {
      try {
        final charts = await _musicServices.getCharts(val);
        final index = charts.indexWhere(
          (element) =>
              element['title'] ==
              (val == "TMV" ? "Top Music Videos" : "Trending"),
        );
        quickPicks_ = QuickPicks(
          List<MediaItem>.from(charts[index]["contents"]),
          title: charts[index]["title"],
        );
      } catch (e) {
        printERROR(
          "Seems ${val == "TMV" ? "Top music videos" : "Trending songs"} currently not available!",
        );
      }
    } else {
      songId ??= _settingsRepository.getRecentSongId();
      if (songId != null) {
        try {
          final value = await _musicServices.getContentRelatedToSong(
            songId,
            getContentHlCode(),
          );
          middleContent = _setContentList(value);
          _notifyHomeChanged();
          if (value.isNotEmpty && value[0]['title'].contains("like")) {
            quickPicks_ = QuickPicks(
              List<MediaItem>.from(value[0]["contents"]),
            );
            unawaited(_settingsRepository.setRecentSongId(songId));
          }
          // ignore: empty_catches
        } catch (e) {}
      }
    }
    if (quickPicks_ == null) return;

    quickPicks = quickPicks_;
    _notifyHomeChanged();

    // set home content last update time
    await cachedHomeScreenData(updateQuickPicksNMiddleContent: true);
    await _settingsRepository.setHomeScreenDataTime(
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  String getContentHlCode() {
    const List<String> unsupportedLangIds = ["ia", "ga", "fj", "eo"];
    final userLangId = _settingsScreenController().currentAppLanguageCode.value;
    return unsupportedLangIds.contains(userLangId) ? "en" : userLangId;
  }

  void onSideBarTabSelected(int index) {
    _popNestedNavigatorToRoot();
    reverseAnimationTransition = index > tabIndex;
    tabIndex = index;
    _notifyHomeChanged();
  }

  void onBottonBarTabSelected(int index) {
    _popNestedNavigatorToRoot();
    reverseAnimationTransition = index > tabIndex;
    tabIndex = index;
    _notifyHomeChanged();
  }

  void resetRecoverableNavigationState() {
    tabIndex = 0;
    isHomeScreenOnTop = true;
    networkError = false;
    isContentFetched = false;
    _notifyHomeChanged();
  }

  void _popNestedNavigatorToRoot() {
    ScreenNavigationSetup.navigatorKey.currentState?.popUntil(
      (route) => route.isFirst,
    );
  }

  void _checkNewVersion() {
    showVersionDialog = isStartupUpdatePopupEnabled();
    _notifyHomeChanged();
    if (showVersionDialog) {
      final settingsController = _settingsScreenController();
      (
        settingsController.checkNewVersion().then((value) {
          if (value != null) {
            _showNewVersionDialog(value);
          }
        }),
      );
    }
  }

  /// Shows the current release's one-time prompt (null = none this release)
  /// and completes when it is dismissed. If the navigator isn't ready yet
  /// the prompt simply stays unanswered and shows on the next launch.
  Future<void> _maybeShowReleasePrompt() async {
    final prompt = currentReleasePrompt;
    if (prompt == null) return;
    if (_settingsRepository.isReleasePromptAnswered(prompt.id)) return;

    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = AppNavigator.context;
      if (_closed || context == null) {
        completer.complete();
        return;
      }
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => const ReleasePromptDialog(),
        ).whenComplete(completer.complete),
      );
    });
    return completer.future;
  }

  /// Persists that the current release prompt was answered so it never
  /// shows again.
  Future<void> markReleasePromptAnswered() async {
    final prompt = currentReleasePrompt;
    if (prompt == null) return;
    await _settingsRepository.setReleasePromptAnswered(prompt.id);
  }

  /// Switches the home shell to the Settings tab (its index depends on the
  /// active navigation style).
  void openSettingsTab() {
    final settingsTabIndex =
        _settingsScreenController().isBottomNavBarEnabled.value ? 3 : 5;
    onSideBarTabSelected(settingsTabIndex);
  }

  void _showNewVersionDialog(UpdateInfo updateInfo) {
    if (_updateDialogPending || _updateDialogShown) return;
    _updateDialogPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryShowNewVersionDialog(updateInfo);
    });
  }

  void _tryShowNewVersionDialog(UpdateInfo updateInfo) {
    final context = AppNavigator.context;
    if (_closed || context == null) {
      _updateDialogPending = false;
      return;
    }

    _updateDialogPending = false;
    _updateDialogShown = true;
    (
      showDialog<void>(
        context: context,
        builder: (context) => NewVersionDialog(updateInfo: updateInfo),
      ).whenComplete(() {
        _updateDialogShown = false;
      }),
    );
  }

  void _showDebugUpdateDialog() {
    _showNewVersionDialog(
      const UpdateInfo(
        channel: UpdateChannel.rolling,
        version: 'debug-preview',
        downloadUrl: 'https://github.com/bozmund/Harmony-Music/releases',
        releaseUrl: 'https://github.com/bozmund/Harmony-Music/releases',
        sha: 'debug',
      ),
    );
  }

  bool isStartupUpdatePopupEnabled() {
    return _settingsRepository.getNewVersionVisibility(true);
  }

  void setStartupUpdatePopupEnabled(bool enabled) {
    unawaited(_settingsRepository.setNewVersionVisibility(enabled));
    showVersionDialog = enabled;
    _notifyHomeChanged();
  }

  void disableStartupUpdatePopup() {
    setStartupUpdatePopupEnabled(false);
  }

  void onChangeVersionVisibility(bool val) {
    setStartupUpdatePopupEnabled(!val);
  }

  ///This is used to minimized bottom navigation bar by setting [isHomeScreenOnTop.value] to `true` and set mini player height.
  ///
  ///and applicable/useful if bottom nav enabled
  void whenHomeScreenOnTop() {
    // Callers include screen controllers' close() running during widget
    // disposal (tree finalization), where any synchronous notifyListeners —
    // _notifyHomeChanged() or the playerPanelMinHeight writes below — hits a
    // locked tree: the listener's markNeedsBuild throws (debug-only),
    // ChangeNotifier swallows it, and the home Scaffold silently misses the
    // rebuild (nav bar stuck hidden; stale tab view enabling a back-press
    // minimize). Defer the whole body out of that phase.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_closed) whenHomeScreenOnTop();
      });
      // A post-frame callback does not schedule a frame by itself; without
      // this the deferred run would wait for the next user interaction.
      SchedulerBinding.instance.ensureVisualUpdate();
      return;
    }
    if (_settingsScreenController().isBottomNavBarEnabled.value) {
      final currentRoute = getCurrentRouteName();
      final isHomeOnTop = currentRoute == '/homeScreen';
      final isResultScreenOnTop = currentRoute == '/searchResultScreen';
      final playerCon = _playerController();

      isHomeScreenOnTop = isHomeOnTop;
      _notifyHomeChanged();

      // Set mini-player height accordingly
      if (!playerCon.initFlagForPlayer) {
        if (isHomeOnTop) {
          playerCon.playerPanelMinHeight.value = 75.0;
        } else {
          Future.delayed(
            isResultScreenOnTop
                ? const Duration(milliseconds: 300)
                : Duration.zero,
            () {
              final bottomPadding = AppNavigator.context == null
                  ? 0.0
                  : MediaQuery.of(AppNavigator.context!).viewPadding.bottom;
              playerCon.playerPanelMinHeight.value = 75.0 + bottomPadding;
            },
          );
        }
      }
    }
  }

  Future<void> cachedHomeScreenData({
    bool updateAll = false,
    bool updateQuickPicksNMiddleContent = false,
  }) async {
    if (!_settingsScreenController().cacheHomeScreenData.value ||
        quickPicks.songList.isEmpty) {
      return;
    }

    if (updateQuickPicksNMiddleContent) {
      await _homeRepository.setHomeData("quickPicksType", quickPicks.title);
      await _homeRepository.setHomeData(
        "quickPicks",
        _getContentDataInJson(quickPicks.songList, isQuickPicks: true),
      );
      await _homeRepository.setHomeData(
        "middleContent",
        _getContentDataInJson(middleContent.toList()),
      );
    } else if (updateAll) {
      await _homeRepository.setHomeData("quickPicksType", quickPicks.title);
      await _homeRepository.setHomeData(
        "quickPicks",
        _getContentDataInJson(quickPicks.songList, isQuickPicks: true),
      );
      await _homeRepository.setHomeData(
        "middleContent",
        _getContentDataInJson(middleContent.toList()),
      );
      await _homeRepository.setHomeData(
        "fixedContent",
        _getContentDataInJson(fixedContent.toList()),
      );
    }

    printINFO("Saved Homescreen data data");
  }

  List<Map<String, dynamic>> _getContentDataInJson(
    List content, {
    bool isQuickPicks = false,
  }) {
    if (isQuickPicks) {
      return content.toList().map((e) => MediaItemBuilder.toJson(e)).toList();
    } else {
      return content.map((e) {
        if (e.runtimeType == AlbumContent) {
          return (e as AlbumContent).toJson();
        } else {
          return (e as PlaylistContent).toJson();
        }
      }).toList();
    }
  }

  void disposeDetachedScrollControllers({bool disposeAll = false}) {
    final scrollControllersCopy = contentScrollControllers.toList();
    for (final controller in scrollControllersCopy) {
      if (!controller.hasClients || disposeAll) {
        contentScrollControllers.remove(controller);
        controller.dispose();
      }
    }
  }

  void _notifyHomeChanged() {
    if (_closed) return;
    // This can be reached from a screen controller's close() during widget
    // disposal (tree finalization), where listeners' markNeedsBuild throws a
    // debug-only "framework locked" error that ChangeNotifier swallows — the
    // UI then silently misses the rebuild (navbar staying hidden after leaving
    // album/playlist/search screens). Defer to the next frame in that phase.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_closed) notifyListeners();
      });
      // A post-frame callback does not schedule a frame by itself.
      SchedulerBinding.instance.ensureVisualUpdate();
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _closed = true;
    unawaited(_audioEventSubscription?.cancel());
    disposeDetachedScrollControllers(disposeAll: true);
    super.dispose();
  }
}
