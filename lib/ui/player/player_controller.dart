import 'dart:async';
import 'package:hive/hive.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:flutter_lyric/flutter_lyric.dart';

import '../../models/playing_from.dart';

import '../../services/app_platform_service.dart';
import '../../services/downloader.dart';
import '../screens/Playlist/playlist_screen_controller.dart';
import '../widgets/snackbar.dart';
import '/services/synced_lyrics_service.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '../../services/windows_audio_service.dart';
import '../../utils/helper.dart';
import '/models/media_Item_builder.dart';
import '../screens/Home/home_screen_controller.dart';
import '../widgets/sliding_up_panel.dart';
import '/models/duration_state.dart';
import '/services/app_contracts.dart';

import '/services/constant.dart';

class PlayerController extends GetxController
    with GetSingleTickerProviderStateMixin {
  final _audioHandler = Get.find<AudioHandler>();
  final _musicServices = Get.find<MusicServiceContract>();
  final currentQueue = <MediaItem>[].obs;

  final playerPaneOpacity = 1.0.obs;
  final playerPanelTopVisible = true.obs;
  final isPanelGTHOpened = false.obs;
  final playerPanelMinHeight = 0.0.obs;
  bool initFlagForPlayer = true;
  final isQueueReorderingInProcess = false.obs;
  PanelController playerPanelController = PanelController();
  PanelController queuePanelController = PanelController();
  AnimationController? gesturePlayerStateAnimationController;
  Animation<double>? gesturePlayerStateAnimation;
  bool isRadioModeOn = false;
  String? radioContinuationParam;
  dynamic radioInitiatorItem;
  Timer? sleepTimer;
  int timerDuration = 0;
  final timerDurationLeft = 0.obs;
  final isSleepTimerActive = false.obs;
  final isSleepEndOfSongActive = false.obs;
  final volume = 100.obs;

  final progressBarStatus = ProgressBarState(
    buffered: Duration.zero,
    current: Duration.zero,
    total: Duration.zero,
  ).obs;

  final currentSongIndex = 0.obs;
  final isFirstSong = true;
  final isLastSong = true;
  final isQueueLoopModeEnabled = true.obs;
  final isLoopModeEnabled = false.obs;
  final isShuffleModeEnabled = false.obs;
  final currentSong = Rxn<MediaItem>();
  final isCurrentSongFav = false.obs;
  final playingFrom = PlayingFrom(type: PlayingFromType.SELECTION).obs;
  final showLyricsFlag = false.obs;
  final isLyricsLoading = false.obs;
  final lyricsMode = 0.obs;
  bool isDesktopLyricsDialogOpen = false;

  // 0 for play, 1 for pause, 2 for blank
  final gesturePlayerVisibleState = 2.obs;
  final lyricController = LyricController();
  String? _loadedSyncedLyrics;
  int _lyricsLoadGeneration = 0;
  RxMap<String, dynamic> lyrics = <String, dynamic>{
    "synced": "",
    "plainLyrics": "",
  }.obs;
  ScrollController scrollController = ScrollController();
  final GlobalKey<ScaffoldState> homeScaffoldKey = GlobalKey<ScaffoldState>();

  final buttonState = PlayButtonState.paused.obs;

  // track whether wakelock is currently enabled to avoid repeated calls
  bool _wakelockActive = false;
  bool _playbackWakeLockActive = false;
  Future<void>? _playbackCommand;

  var _newSongFlag = true;
  final isCurrentSongBuffered = false.obs;

  late StreamSubscription<bool> keyboardSubscription;

  List<MediaItem> get displayQueue =>
      displayQueueFor(currentQueue, currentSongIndex.value);

  int realQueueIndexForDisplayIndex(int displayIndex) {
    return realQueueIndexForDisplayIndexIn(
      queueLength: currentQueue.length,
      currentIndex: currentSongIndex.value,
      displayIndex: displayIndex,
    );
  }

  static List<MediaItem> displayQueueFor(
    List<MediaItem> queue,
    int currentIndex,
  ) {
    if (!_isValidQueueIndex(queue.length, currentIndex)) {
      return List<MediaItem>.from(queue);
    }

    return <MediaItem>[
      ...queue.sublist(currentIndex),
      ...queue.sublist(0, currentIndex),
    ];
  }

  static int realQueueIndexForDisplayIndexIn({
    required int queueLength,
    required int currentIndex,
    required int displayIndex,
  }) {
    if (queueLength <= 0 || displayIndex < 0 || displayIndex >= queueLength) {
      return displayIndex;
    }
    if (currentIndex < 0 || currentIndex >= queueLength) {
      return displayIndex;
    }
    return (currentIndex + displayIndex) % queueLength;
  }

  static List<MediaItem> realQueueAfterDisplayReorder({
    required List<MediaItem> queue,
    required int currentIndex,
    required int oldDisplayIndex,
    required int newDisplayIndex,
  }) {
    if (!_isValidQueueIndex(queue.length, currentIndex)) {
      return List<MediaItem>.from(queue);
    }
    if (oldDisplayIndex < 0 ||
        oldDisplayIndex >= queue.length ||
        newDisplayIndex < 0 ||
        newDisplayIndex > queue.length) {
      return List<MediaItem>.from(queue);
    }

    final displayQueue = displayQueueFor(queue, currentIndex);
    var insertIndex = newDisplayIndex;
    if (oldDisplayIndex < insertIndex) {
      insertIndex--;
    }
    final movedItem = displayQueue.removeAt(oldDisplayIndex);
    displayQueue.insert(insertIndex, movedItem);

    final currentItem = queue[currentIndex];
    final displayCurrentIndex = displayQueue.indexWhere(
      (item) => item.id == currentItem.id,
    );
    if (displayCurrentIndex == -1) {
      return List<MediaItem>.from(queue);
    }

    final realQueue = List<MediaItem>.filled(queue.length, currentItem);
    for (
      var displayIndex = 0;
      displayIndex < displayQueue.length;
      displayIndex++
    ) {
      final realIndex =
          (currentIndex + displayIndex - displayCurrentIndex) % queue.length;
      realQueue[realIndex < 0 ? realIndex + queue.length : realIndex] =
          displayQueue[displayIndex];
    }
    return realQueue;
  }

  static bool _isValidQueueIndex(int queueLength, int index) =>
      queueLength > 0 && index >= 0 && index < queueLength;

  @override
  Future<void> onInit() async {
    await _init();
    super.onInit();
  }

  @override
  Future<void> onReady() async {
    if (GetPlatform.isWindows) {
      Get.put(WindowsAudioService());
    }
    await _restorePrevSession();
    super.onReady();
  }

  Future<void> _init() async {
    //_createAppDocDir();
    _listenForChangesInPlayerState();
    _listenForChangesInPosition();
    _listenForChangesInBufferedPosition();
    _listenForChangesInDuration();
    _listenForPlaylistChange();
    _listenForKeyboardActivity();
    _setInitLyricsMode();
    final appPrefs = Hive.box(BoxNames.appPrefs);
    isLoopModeEnabled.value = appPrefs.get(PrefKeys.isLoopModeEnabled) ?? false;
    isShuffleModeEnabled.value =
        appPrefs.get(PrefKeys.isShuffleModeEnabled) ?? false;
    isQueueLoopModeEnabled.value =
        appPrefs.get(PrefKeys.queueLoopModeEnabled) ?? true;

    if (GetPlatform.isDesktop) {
      await setVolume(appPrefs.get(PrefKeys.volume) ?? 100);
    }

    if ((appPrefs.get(PrefKeys.playerUi) ?? 0) == 1) {
      initGesturePlayerStateAnimationController();
    }

    // only for android auto
    if (GetPlatform.isAndroid) {
      _listenForCustomEvents();
    }
  }

  void initGesturePlayerStateAnimationController() {
    gesturePlayerStateAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    gesturePlayerStateAnimation = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: gesturePlayerStateAnimationController!,
        curve: Curves.easeIn,
      ),
    );
  }

  void _setInitLyricsMode() {
    lyricsMode.value =
        Hive.box(BoxNames.appPrefs).get(PrefKeys.lyricsMode) ?? 0;
  }

  void panelListener(double x) {
    if (x >= 0 && x <= 0.2) {
      playerPaneOpacity.value = 1 - (x * 5);
      playerPanelTopVisible.value = true;
    } else if (x > 0.2) {
      playerPanelTopVisible.value = false;
    }

    if (x > 0.6) {
      isPanelGTHOpened.value = true;
    } else {
      isPanelGTHOpened.value = false;
    }
  }

  void _listenForKeyboardActivity() {
    var keyboardVisibilityController = KeyboardVisibilityController();
    keyboardSubscription = keyboardVisibilityController.onChange.listen((
      bool visible,
    ) async {
      visible
          ? await playerPanelController.hide()
          : await playerPanelController.show();
    });
  }

  void _listenForChangesInPlayerState() {
    _audioHandler.playbackState.listen((playerState) {
      final isPlaying = playerState.playing;
      final processingState = playerState.processingState;
      if (processingState == AudioProcessingState.loading) {
        buttonState.value = PlayButtonState.loading;
      } else if (processingState == AudioProcessingState.buffering) {
        buttonState.value = PlayButtonState.loading;
      } else if (!isPlaying || processingState == AudioProcessingState.error) {
        buttonState.value = PlayButtonState.paused;
      } else if (processingState != AudioProcessingState.completed) {
        buttonState.value = PlayButtonState.playing;
      } else {
        _runPlaybackCommand(() async {
          await _audioHandler.seek(Duration.zero);
          await _audioHandler.pause();
        });
      }

      final settings = Get.find<SettingsScreenController>();
      // Keep the screen awake whenever playback is active and the setting is enabled.
      final shouldEnable = settings.keepScreenAwake.isTrue && isPlaying;
      _setWakelock(shouldEnable);
      final shouldHoldPlaybackWakeLock =
          isPlaying &&
          processingState != AudioProcessingState.completed &&
          processingState != AudioProcessingState.error &&
          processingState != AudioProcessingState.idle;
      _setPlaybackWakeLock(shouldHoldPlaybackWakeLock);
    });
  }

  void _setWakelock(bool enable) {
    if (_wakelockActive == enable) return; // no-op if already in desired state

    try {
      if (enable) {
        printINFO("Enabling wakelock", tag: LogTags.player);
        unawaited(AppPlatformService.setKeepScreenAwake(true));
        _wakelockActive = true;
      } else {
        printINFO("Disabling wakelock", tag: LogTags.player);
        unawaited(AppPlatformService.setKeepScreenAwake(false));
        _wakelockActive = false;
      }
    } catch (e) {
      printERROR(e, tag: LogTags.player);
    }
  }

  void _setPlaybackWakeLock(bool enable) {
    if (_playbackWakeLockActive == enable) return;

    try {
      unawaited(AppPlatformService.setPlaybackWakeLock(enable));
      _playbackWakeLockActive = enable;
    } catch (e) {
      printERROR(e, tag: LogTags.player);
    }
  }

  void _listenForChangesInPosition() {
    AudioService.position.listen((position) {
      final oldState = progressBarStatus.value;
      if (isSleepEndOfSongActive.isTrue) {
        timerDurationLeft.value = oldState.total.inSeconds - position.inSeconds;
        if (timerDurationLeft.value == 1) {
          requestPause();
          cancelSleepTimer();
        }
      }
      progressBarStatus.update((val) {
        val!.current = position;
        val.buffered = oldState.buffered;
        val.total = oldState.total;
      });
      lyricController.setProgress(position);
    });
  }

  void _listenForChangesInBufferedPosition() {
    _audioHandler.playbackState.listen((playbackState) async {
      final oldState = progressBarStatus.value;
      if (progressBarStatus.value.total.inSeconds != 0 &&
          playbackState.bufferedPosition.inSeconds /
                  progressBarStatus.value.total.inSeconds >=
              0.98) {
        if (_newSongFlag) {
          await _audioHandler.customAction("checkWithCacheDb", {
            'mediaItem': currentSong.value!,
          });
          _newSongFlag = false;
        }
      }
      progressBarStatus.update((val) {
        val!.buffered = playbackState.bufferedPosition;
        val.current = oldState.current;
        val.total = oldState.total;
      });
    });
  }

  void _listenForChangesInDuration() {
    _audioHandler.mediaItem.listen((mediaItem) async {
      final oldState = progressBarStatus.value;
      progressBarStatus.update((val) {
        val!.total = mediaItem?.duration ?? Duration.zero;
        val.current = oldState.current;
        val.buffered = oldState.buffered;
      });
      if (mediaItem != null) {
        final previousSongId = currentSong.value?.id;
        final isSameSong = previousSongId == mediaItem.id;
        printINFO(mediaItem.title, tag: LogTags.player);
        _newSongFlag = true;
        isCurrentSongBuffered.value = false;
        currentSong.value = mediaItem;
        currentSongIndex.value = currentQueue.indexWhere(
          (element) => element.id == currentSong.value!.id,
        );
        progressBarStatus.update((val) {
          val!.total = mediaItem.duration ?? Duration.zero;
          val.current = Duration.zero;
          val.buffered = Duration.zero;
        });
        if (!isSameSong) {
          _clearLyricsForSongChange();
        }
        if (isDesktopLyricsDialogOpen) {
          Navigator.pop(Get.context!);
        }

        // reset player visible state when player is in gesture mode
        if (Get.find<SettingsScreenController>().playerUi.value == 1) {
          gesturePlayerVisibleState.value = 2;
        }

        unawaited(_updateCurrentSongSideEffects(mediaItem));
      }
    });
  }

  Future<void> _updateCurrentSongSideEffects(MediaItem mediaItem) async {
    await _checkFavFor(mediaItem);
    await _addToRP(mediaItem);
    if (currentSong.value?.id == mediaItem.id &&
        isRadioModeOn &&
        currentQueue.isNotEmpty &&
        mediaItem.id == currentQueue.last.id) {
      await _addRadioContinuation(radioInitiatorItem!);
    }
  }

  void _listenForPlaylistChange() {
    _audioHandler.queue.listen((queue) {
      currentQueue.value = queue;
      currentQueue.refresh();
      final song = currentSong.value;
      if (song != null) {
        currentSongIndex.value = queue.indexWhere(
          (element) => element.id == song.id,
        );
      }
    });
  }

  Future<void> _restorePrevSession() async {
    final restorePrevSessionEnabled =
        Hive.box(BoxNames.appPrefs).get(PrefKeys.restorePlaybackSession) ??
        false;
    if (restorePrevSessionEnabled) {
      final prevSessionData = await Hive.openBox(BoxNames.prevSessionData);
      if (prevSessionData.keys.isNotEmpty) {
        final songList = (prevSessionData.get("queue") as List)
            .map((e) => MediaItemBuilder.fromJson(e))
            .toList();
        final int currentIndex = prevSessionData.get("index");
        final int position = prevSessionData.get("position");
        await prevSessionData.close();
        await _audioHandler.addQueueItems(songList);
        await _playerPanelCheck(restoreSession: true);
        await _audioHandler.customAction("playByIndex", {
          "index": currentIndex,
          "position": position,
          "restoreSession": true,
        });
      }
    }
  }

  void _listenForCustomEvents() {
    _audioHandler.customEvent.listen((event) async {
      if (event['eventType'] == 'playFromMediaId') {
        await _playViaAndroidAuto(event['songId'], event['libraryId']);
      }
    });
  }

  ///pushSongToPlaylist method clear previous song queue, plays the tapped song and push related
  ///songs into Queue
  Future<void> pushSongToQueue(
    MediaItem? mediaItem, {
    String? playlistId,
    bool radio = false,
  }) async {
    /// update playing from value
    playingFrom.value = PlayingFrom(
      type: PlayingFromType.SELECTION,
      name: radio ? "randomRadio".tr : "randomSelection".tr,
    );

    /// set global radio mode flag
    isRadioModeOn = radio;

    final queueUpdate = Future.delayed(Duration.zero, () async {
      final content = await _musicServices.getWatchPlaylist(
        videoId: mediaItem?.id ?? "",
        radio: radio,
        playlistId: playlistId,
      );
      radioContinuationParam = content['additionalParamsForNext'];
      await _audioHandler.updateQueue(List<MediaItem>.from(content['tracks']));
      if (isShuffleModeEnabled.isTrue) {
        await _audioHandler.customAction("shuffleCmd", {"index": 0});
      }

      // added here to broadcast current mediaItem via Audio Service as list is updated
      // if radio is started on current playing song
      if (radio && (currentSong.value?.id == mediaItem?.id)) {
        await _audioHandler.customAction("updateMediaItemInAudioService", {
          "index": 0,
        });
      }
    });

    if (playlistId != null) {
      unawaited(_playerPanelCheck());
      await queueUpdate;
      await _audioHandler.customAction("playByIndex", {"index": 0});
      return;
    }

    unawaited(
      queueUpdate.then((value) async {
        if (Hive.box(BoxNames.appPrefs).get(PrefKeys.discoverContentType) ==
            "BOLI") {
          await Get.find<HomeScreenController>().changeDiscoverContent(
            "BOLI",
            songId: mediaItem!.id,
          );
        }
      }),
    );

    if (radio && (currentSong.value?.id == mediaItem?.id)) {
      return;
    }

    //currentSong.value = mediaItem;
    unawaited(_playerPanelCheck());
    await _audioHandler.customAction("setSourceNPlay", {
      'mediaItem': mediaItem,
    });

    // disable queue loop mode when radio is started
    if (radio &&
        isQueueLoopModeEnabled.isTrue &&
        isShuffleModeEnabled.isFalse) {
      await toggleQueueLoopMode();
    }
  }

  Future<void> playPlayListSong(
    List<MediaItem> mediaItems,
    int index, {
    PlayingFrom? playFrom,
  }) async {
    isRadioModeOn = false;
    //open player pane,set current song and push first song into playing list,

    /// update playing from value
    playingFrom.value =
        playFrom ?? PlayingFrom(type: PlayingFromType.SELECTION);

    //for changing home content based on last iteration
    unawaited(
      Future.delayed(const Duration(seconds: 3), () async {
        if (Hive.box(BoxNames.appPrefs).get(PrefKeys.discoverContentType) ==
            "BOLI") {
          await Get.find<HomeScreenController>().changeDiscoverContent(
            "BOLI",
            songId: mediaItems[index].id,
          );
        }
      }),
    );

    await _playerPanelCheck();
    await _audioHandler.updateQueue(mediaItems);
    if (isShuffleModeEnabled.value) {
      await _audioHandler.customAction("shuffleCmd", {"index": index});
    }
    await _audioHandler.customAction("playByIndex", {"index": index});
  }

  Future<void> startRadio(MediaItem? mediaItem, {String? playlistId}) async {
    radioInitiatorItem = mediaItem ?? playlistId;
    await pushSongToQueue(mediaItem, playlistId: playlistId, radio: true);
  }

  Future<void> _addRadioContinuation(dynamic item) async {
    final isSong = item.runtimeType.toString() == "MediaItem";
    final content = await _musicServices.getWatchPlaylist(
      videoId: isSong ? item.id : "",
      radio: true,
      limit: 24,
      playlistId: isSong ? null : item,
      additionalParamsNext: radioContinuationParam,
    );
    radioContinuationParam = content['additionalParamsForNext'];
    await enqueueSongList(List<MediaItem>.from(content['tracks']));
  }

  ///enqueueSong   append a song to current queue
  ///if current queue is empty, push the song into Queue and play that song
  Future<void> enqueueSong(MediaItem mediaItem) async {
    if (currentQueue.isEmpty) {
      await playPlayListSong([mediaItem], 0);
      return;
    }
    //check if song is available in queue and if not add it to queue
    if (!currentQueue.contains(mediaItem)) {
      await _audioHandler.addQueueItem(mediaItem);
    }
  }

  ///enqueueSongList method add song List to current queue
  Future<void> enqueueSongList(List<MediaItem> mediaItems) async {
    if (currentQueue.isEmpty) {
      await playPlayListSong(mediaItems, 0);
      return;
    }
    final listToEnqueue = <MediaItem>[];
    for (MediaItem item in mediaItems) {
      if (!currentQueue.contains(item)) {
        listToEnqueue.add(item);
      }
    }
    await _audioHandler.addQueueItems(listToEnqueue);
  }

  Future<void> _playViaAndroidAuto(String songId, String libraryId) async {
    await Hive.openBox(libraryId).then((box) async {
      List<MediaItem> songList = [];
      final songJson = box.values.toList();
      int songIndex = 0;
      for (int i = 0; i < box.length; i++) {
        final song = MediaItemBuilder.fromJson(songJson[i]);
        if (song.id == songId) {
          songIndex = i;
        }
        songList.add(song);
      }
      await playPlayListSong(songList, songIndex);
      if (libraryId != BoxNames.songDownloads) {
        await box.close();
      }
    });
  }

  Future<void> playNext(MediaItem song) async {
    if (currentQueue.isEmpty) {
      await enqueueSong(song);
      return;
    }
    int index = -1;
    for (int i = 0; i < currentQueue.length; i++) {
      if (song.id == currentQueue[i].id) {
        index = i;
        break;
      }
    }
    final currentIndex = currentSongIndex.value;
    if (index == currentIndex) {
      return;
    }
    if (index != -1) {
      if (currentQueue.length == 1 ||
          (currentQueue.length == 2 && index == 1)) {
        return;
      }
      await onReorder(index, currentSongIndex.value + 1);
    } else {
      //Will add song just below the current song
      (currentIndex == currentQueue.length - 1)
          ? await enqueueSong(song)
          : await _audioHandler.customAction("addPlayNextItem", {
              "mediaItem": song,
            });
    }
  }

  Future<void> _playerPanelCheck({bool restoreSession = false}) async {
    final isWideScreen = Get.size.width > 800;
    final autoOpenPlayer =
        Hive.box(BoxNames.appPrefs).get(PrefKeys.autoOpenPlayer) ?? true;
    if ((!isWideScreen && autoOpenPlayer && playerPanelController.isAttached) &&
        !restoreSession) {
      await playerPanelController.open();
    }

    if (initFlagForPlayer) {
      final miniPlayerHeight = isWideScreen ? 105.0 : 75.0;
      if (Get.find<SettingsScreenController>().isBottomNavBarEnabled.isFalse ||
          getCurrentRouteName() != '/homeScreen') {
        playerPanelMinHeight.value =
            miniPlayerHeight + Get.mediaQuery.viewPadding.bottom;
      } else {
        playerPanelMinHeight.value = miniPlayerHeight;
      }
      initFlagForPlayer = false;
    }
  }

  Future<void> removeFromQueue(MediaItem song) async {
    await _audioHandler.removeQueueItem(song);
  }

  Future<void> clearQueue() async {
    await _audioHandler.customAction("clearQueue");
  }

  Future<void> shuffleQueue() async {
    await _audioHandler.customAction("shuffleQueue");
  }

  Future<void> toggleShuffleMode() async {
    final shuffleModeEnabled = isShuffleModeEnabled.value;
    shuffleModeEnabled
        ? await _audioHandler.setShuffleMode(AudioServiceShuffleMode.none)
        : await _audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
    isShuffleModeEnabled.value = !shuffleModeEnabled;
    await Hive.box(
      BoxNames.appPrefs,
    ).put(PrefKeys.isShuffleModeEnabled, !shuffleModeEnabled);
    // restrict queue loop mode when shuffle mode is enabled
    if (isShuffleModeEnabled.isTrue && isQueueLoopModeEnabled.isFalse) {
      isQueueLoopModeEnabled.value = true;
    } else if (isShuffleModeEnabled.isFalse) {
      isQueueLoopModeEnabled.value = Hive.box(
        BoxNames.appPrefs,
      ).get(PrefKeys.queueLoopModeEnabled, defaultValue: true);
    }
  }

  Future<void> onReorder(int oldIndex, int newIndex) async {
    await _audioHandler.customAction("reorderQueue", {
      "oldIndex": oldIndex,
      "newIndex": newIndex,
    });
  }

  Future<void> onDisplayReorder(
    int oldDisplayIndex,
    int newDisplayIndex,
  ) async {
    final reorderedQueue = realQueueAfterDisplayReorder(
      queue: currentQueue,
      currentIndex: currentSongIndex.value,
      oldDisplayIndex: oldDisplayIndex,
      newDisplayIndex: newDisplayIndex,
    );
    await _audioHandler.updateQueue(reorderedQueue);
  }

  void onReorderStart(int index) {
    isQueueReorderingInProcess.value = true;
  }

  void onReorderEnd(int index) {
    isQueueReorderingInProcess.value = false;
  }

  Future<void> play() async {
    await _audioHandler.play();
  }

  void requestPlay() {
    _runPlaybackCommand(() => play());
  }

  Future<void> pause() async {
    await _audioHandler.pause();
  }

  void requestPause() {
    _runPlaybackCommand(() => pause());
  }

  Future<void> playPause() async {
    if (initFlagForPlayer) return;
    _audioHandler.playbackState.value.playing ? await pause() : await play();
    // for gesture player
    if (Get.find<SettingsScreenController>().playerUi.value == 1) {
      gesturePlayerVisibleState.value =
          _audioHandler.playbackState.value.playing ? 0 : 1;
      gesturePlayerStateAnimationController?.reset();
      await gesturePlayerStateAnimationController?.forward();
    }
  }

  void requestPlayPause() {
    _runPlaybackCommand(() => playPause());
  }

  Future<void> prev() async {
    await _audioHandler.skipToPrevious();
  }

  void requestPrev() {
    _runPlaybackCommand(() => prev());
  }

  Future<void> next() async {
    await _audioHandler.skipToNext();
  }

  void requestNext() {
    _runPlaybackCommand(() => next());
  }

  Future<void> seek(Duration position) async {
    await _audioHandler.seek(position);
  }

  void requestSeek(Duration position) {
    _runPlaybackCommand(() => seek(position));
  }

  Future<void> seekByIndex(int index) async {
    await _audioHandler.customAction("playByIndex", {"index": index});
  }

  void requestSeekByIndex(int index) {
    _runPlaybackCommand(() => seekByIndex(index));
  }

  void _runPlaybackCommand(Future<void> Function() command) {
    final future = command();
    _playbackCommand = future;
    unawaited(
      future
          .catchError((Object error, StackTrace stackTrace) {
            printERROR(error, tag: LogTags.player);
            printERROR(stackTrace, tag: LogTags.player);
          })
          .whenComplete(() {
            if (identical(_playbackCommand, future)) {
              _playbackCommand = null;
            }
          }),
    );
  }

  Future<void> toggleSkipSilence(bool enable) async {
    await _audioHandler.customAction("toggleSkipSilence", {"enable": enable});
  }

  Future<void> toggleLoudnessNormalization(bool enable) async {
    await _audioHandler.customAction("toggleLoudnessNormalization", {
      "enable": enable,
    });
  }

  Future<void> toggleLoopMode() async {
    isLoopModeEnabled.isFalse
        ? await _audioHandler.setRepeatMode(AudioServiceRepeatMode.one)
        : await _audioHandler.setRepeatMode(AudioServiceRepeatMode.none);
    isLoopModeEnabled.value = !isLoopModeEnabled.value;
    await Hive.box(
      BoxNames.appPrefs,
    ).put(PrefKeys.isLoopModeEnabled, isLoopModeEnabled.value);
  }

  Future<void> toggleQueueLoopMode({bool showMessage = true}) async {
    if (isShuffleModeEnabled.isTrue && isQueueLoopModeEnabled.isTrue) {
      if (!showMessage) return;
      ScaffoldMessenger.of(Get.context!).showSnackBar(
        snackbar(
          Get.context!,
          "queueLoopNotDisMsg1".tr,
          size: SanckBarSize.BIG,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (isRadioModeOn && isQueueLoopModeEnabled.isFalse) {
      if (!showMessage) return;
      ScaffoldMessenger.of(Get.context!).showSnackBar(
        snackbar(
          Get.context!,
          "queueLoopNotDisMsg2".tr,
          size: SanckBarSize.BIG,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    isQueueLoopModeEnabled.value = !isQueueLoopModeEnabled.value;
    await _audioHandler.customAction("toggleQueueLoopMode", {
      "enable": isQueueLoopModeEnabled.value,
    });
    await Hive.box(
      BoxNames.appPrefs,
    ).put(PrefKeys.queueLoopModeEnabled, isQueueLoopModeEnabled.value);
  }

  Future<void> setVolume(int value) async {
    await _audioHandler.customAction("setVolume", {"value": value});
    volume.value = value;
    await Hive.box(BoxNames.appPrefs).put(PrefKeys.volume, value);
  }

  Future<void> mute() async {
    int? vol;
    if (volume.value != 0) {
      vol = 0;
    } else {
      vol = await Hive.box(
        BoxNames.appPrefs,
      ).get(PrefKeys.volume, defaultValue: 10);
      if (vol == 0) {
        vol = 10;
        await Hive.box(BoxNames.appPrefs).put(PrefKeys.volume, vol);
      }
    }
    await _audioHandler.customAction("setVolume", {"value": vol!});
    volume.value = vol;
  }

  Future<void> _checkFavFor(MediaItem song) async {
    final isFavorite = (await Hive.openBox(
      BoxNames.libFav,
    )).containsKey(song.id);
    if (currentSong.value?.id == song.id) {
      isCurrentSongFav.value = isFavorite;
    }
  }

  Future<void> toggleFavourite() async {
    final currMediaItem = currentSong.value!;
    final box = await Hive.openBox(BoxNames.libFav);
    isCurrentSongFav.isFalse
        ? await box.put(
            currMediaItem.id,
            MediaItemBuilder.toJson(currMediaItem),
          )
        : await box.delete(currMediaItem.id);
    try {
      final playlistController = Get.find<PlaylistScreenController>(
        tag: const Key(BoxNames.libFav).hashCode.toString(),
      );
      isCurrentSongFav.isFalse
          ? await playlistController.addNRemoveItemsInList(
              currMediaItem,
              action: 'add',
              index: 0,
            )
          : await playlistController.addNRemoveItemsInList(
              currMediaItem,
              action: 'remove',
            );

      // ignore: empty_catches
    } catch (e) {}
    try {
      final likedNotDownloadedController = Get.find<PlaylistScreenController>(
        tag: const Key(BoxNames.libFavNotDownloaded).hashCode.toString(),
      );
      if (isCurrentSongFav.isFalse &&
          !Hive.box(BoxNames.songDownloads).containsKey(currMediaItem.id)) {
        await likedNotDownloadedController.addNRemoveItemsInList(
          currMediaItem,
          action: 'add',
          index: 0,
        );
      } else {
        await likedNotDownloadedController.addNRemoveItemsInList(
          currMediaItem,
          action: 'remove',
        );
      }
      // ignore: empty_catches
    } catch (e) {}
    isCurrentSongFav.value = !isCurrentSongFav.value;
    if (Get.find<SettingsScreenController>()
            .autoDownloadFavoriteSongEnabled
            .isTrue &&
        isCurrentSongFav.isTrue) {
      await Get.find<Downloader>().download(currMediaItem);
    }
  }

  // ignore: prefer_typing_uninitialized_variables
  var recentItem;

  /// This function is used to add a mediaItem/Song to Recently played playlist
  Future<void> _addToRP(MediaItem mediaItem) async {
    if (recentItem != mediaItem) {
      final box = await Hive.openBox(BoxNames.libRP);
      String? removedSongId;
      if (box.keys.length >= 30) {
        removedSongId = box.getAt(0)['videoId'];
        await box.deleteAt(0);
      }
      final valuesCopy = box.values.toList();
      for (int i = valuesCopy.length - 1; i >= 0; i--) {
        if (valuesCopy[i]['videoId'] == mediaItem.id) {
          await box.deleteAt(i);
        }
      }
      await box.add(MediaItemBuilder.toJson(mediaItem));
      try {
        final playlistController = Get.find<PlaylistScreenController>(
          tag: const Key(BoxNames.libRP).hashCode.toString(),
        );
        if (removedSongId != null) {
          playlistController.songList.removeWhere(
            (element) => element.id == removedSongId,
          );
        }
        // removes current duplicate item from list
        playlistController.songList.removeWhere(
          (element) => element.id == mediaItem.id,
        );
        // adds current item to list
        await playlistController.addNRemoveItemsInList(
          mediaItem,
          action: 'add',
          index: 0,
        );

        // ignore: empty_catches
      } catch (e) {}
    }
    recentItem = mediaItem;
  }

  Future<void> showLyrics() async {
    showLyricsFlag.value = !showLyricsFlag.value;
    if ((lyrics["synced"].isEmpty && lyrics['plainLyrics'].isEmpty) &&
        showLyricsFlag.value) {
      final song = currentSong.value;
      if (song == null) return;
      final songId = song.id;
      final generation = ++_lyricsLoadGeneration;
      isLyricsLoading.value = true;
      try {
        final Map<String, dynamic>? lyricsR =
            await SyncedLyricsService.getSyncedLyrics(
              song,
              progressBarStatus.value.total.inSeconds,
            );
        if (!_isCurrentLyricsRequest(songId, generation)) return;
        if (lyricsR != null) {
          lyrics.value = lyricsR;
          isLyricsLoading.value = false;
          return;
        }
        final related = await _musicServices.getWatchPlaylist(
          videoId: songId,
          onlyRelated: true,
        );
        if (!_isCurrentLyricsRequest(songId, generation)) return;
        final relatedLyricsId = related['lyrics'];
        if (relatedLyricsId != null) {
          final lyrics_ = await _musicServices.getLyrics(relatedLyricsId);
          if (!_isCurrentLyricsRequest(songId, generation)) return;
          lyrics.value = {"synced": "", "plainLyrics": lyrics_};
        } else {
          lyrics.value = {"synced": "", "plainLyrics": "NA"};
        }
      } catch (e) {
        if (!_isCurrentLyricsRequest(songId, generation)) return;
        lyrics.value = {"synced": "", "plainLyrics": "NA"};
      } finally {
        if (_isCurrentLyricsRequest(songId, generation)) {
          isLyricsLoading.value = false;
        }
      }
    }
  }

  Future<void> changeLyricsMode(int? val) async {
    await Hive.box(BoxNames.appPrefs).put(PrefKeys.lyricsMode, val);
    lyricsMode.value = val!;
  }

  void updateSyncedLyricsController() {
    final syncedLyrics = lyrics['synced']?.toString() ?? "";
    if (syncedLyrics.isEmpty || syncedLyrics == "NA") return;
    if (_loadedSyncedLyrics != syncedLyrics) {
      lyricController.loadLyric(syncedLyrics);
      _loadedSyncedLyrics = syncedLyrics;
    }
    lyricController.setProgress(progressBarStatus.value.current);
  }

  void _clearLyricsForSongChange() {
    _lyricsLoadGeneration++;
    _loadedSyncedLyrics = null;
    lyrics.value = {"synced": "", "plainLyrics": ""};
    showLyricsFlag.value = false;
    isLyricsLoading.value = false;
  }

  bool _isCurrentLyricsRequest(String songId, int generation) {
    return generation == _lyricsLoadGeneration &&
        currentSong.value?.id == songId;
  }

  void sleepEndOfSong() {
    isSleepTimerActive.value = true;
    isSleepEndOfSongActive.value = true;
  }

  void startSleepTimer(int minutes) {
    timerDuration = minutes * 60;
    isSleepTimerActive.value = true;
    if ((sleepTimer != null && !sleepTimer!.isActive) || sleepTimer == null) {
      sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (timer.tick == timerDuration) {
          sleepTimer?.cancel();
          requestPause();
          isSleepTimerActive.value = false;
          timerDuration = 0;
          timerDurationLeft.value = 0;
        } else {
          timerDurationLeft.value = timerDuration - timer.tick;
        }
      });
    }
  }

  void addFiveMinutes() {
    timerDuration += 300;
  }

  void cancelSleepTimer() {
    if (isSleepEndOfSongActive.isTrue) {
      isSleepEndOfSongActive.value = false;
    }
    sleepTimer?.cancel();
    isSleepTimerActive.value = false;
    timerDuration = 0;
    timerDurationLeft.value = 0;
  }

  Future<void> openEqualizer() async {
    await _audioHandler.customAction("openEqualizer");
  }

  /// Called from audio handler in case audio is not playable
  /// or returned streamInfo null due to network error
  void notifyPlayError(String message) {
    ScaffoldMessenger.of(Get.context!).showSnackBar(
      snackbar(
        Get.context!,
        message == "networkError" ? message.tr : message,
        size: SanckBarSize.MEDIUM,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await _audioHandler.customAction('dispose');
    await keyboardSubscription.cancel();
    scrollController.dispose();
    lyricController.dispose();
    gesturePlayerStateAnimationController?.dispose();
    sleepTimer?.cancel();
    if (GetPlatform.isWindows) {
      await Get.delete<WindowsAudioService>();
    }
    // ensure wakelock disabled when player controller disposed
    try {
      _setWakelock(false);
      _setPlaybackWakeLock(false);
    } catch (e) {
      printERROR(e, tag: LogTags.player);
    }
    super.dispose();
  }
}

enum PlayButtonState { paused, playing, loading }
