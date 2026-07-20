import 'dart:async';
import 'package:harmonymusic/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:flutter_lyric/flutter_lyric.dart';

import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/lyrics_repository.dart';
import '../../domain/repositories/playback_session_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../models/playing_from.dart';

import '../../app/navigation/app_navigator.dart';
import '../../services/app_platform_service.dart';
import '../../services/downloader.dart';
import '../../services/listen_together/listen_together_gate.dart';
import '../../services/listen_together/session_message.dart';
import '../../services/listen_together/session_payload.dart';
import '../../services/playback_command_service.dart';
import '../../utils/runtime_platform.dart';
import '../../utils/observable_state.dart';
import '../screens/Library/library_controller.dart';
import '../screens/Playlist/playlist_screen_controller.dart';
import '../widgets/snackbar.dart';
import '/services/synced_lyrics_service.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '../../services/windows_audio_service.dart';
import '../../utils/helper.dart';
import '../screens/Home/home_screen_controller.dart';
import '../widgets/bottom_nav_bar_dimensions.dart';
import '../widgets/sliding_up_panel.dart';
import '/models/duration_state.dart';
import '/services/app_contracts.dart';

import '/services/constant.dart';

class PlayerController extends ChangeNotifier implements TickerProvider {
  PlayerController({
    required AudioHandler audioHandler,
    required SettingsScreenController settingsController,
    required HomeScreenController homeScreenController,
    required Downloader downloader,
    required SettingsRepository settingsRepository,
    required LibraryRepository libraryRepository,
    required LyricsRepository lyricsRepository,
    required PlaybackSessionRepository playbackSessionRepository,
    required MusicServiceContract musicService,
    required PlaybackCommandService playbackCommands,
  }) : _audioHandler = audioHandler,
       _settingsController = settingsController,
       _homeScreenController = homeScreenController,
       _downloader = downloader,
       _settingsRepository = settingsRepository,
       _libraryRepository = libraryRepository,
       _lyricsRepository = lyricsRepository,
       _playbackSessionRepository = playbackSessionRepository,
       _musicServices = musicService,
       _playbackCommands = playbackCommands;

  final SettingsRepository _settingsRepository;
  final LibraryRepository _libraryRepository;
  final LyricsRepository _lyricsRepository;
  final PlaybackSessionRepository _playbackSessionRepository;
  final AudioHandler _audioHandler;
  final SettingsScreenController _settingsController;
  final HomeScreenController _homeScreenController;
  final Downloader _downloader;
  final MusicServiceContract _musicServices;
  final PlaybackCommandService _playbackCommands;

  /// Set by [ListenTogetherController] while a session is active. When this
  /// device is a guest, local control intents are forwarded to the host
  /// instead of being executed locally. Null when no session is active.
  ListenTogetherGate? listenTogetherGate;

  final currentQueue = ObservableList<MediaItem>();

  final playerPaneOpacity = ObservableValue(1.0);
  final playerPanelTopVisible = ObservableValue(true);
  final playerPanelOpen = ObservableValue(false);
  final playerPanelMinHeight = ObservableValue(0.0);
  bool initFlagForPlayer = true;
  final isQueueReorderingInProcess = ObservableValue(false);
  PanelController playerPanelController = PanelController();
  PanelController queuePanelController = PanelController();
  AnimationController? gesturePlayerStateAnimationController;
  Animation<double>? gesturePlayerStateAnimation;
  bool isRadioModeOn = false;
  String? radioContinuationParam;
  dynamic radioInitiatorItem;
  Timer? sleepTimer;
  WindowsAudioService? _windowsAudioService;
  int timerDuration = 0;
  final timerDurationLeft = ObservableValue(0);
  final isSleepTimerActive = ObservableValue(false);
  final isSleepEndOfSongActive = ObservableValue(false);
  final volume = ObservableValue(100);

  final progressBarStatus = ObservableValue(
    ProgressBarState(
      buffered: Duration.zero,
      current: Duration.zero,
      total: Duration.zero,
    ),
  );

  final currentSongIndex = ObservableValue(0);
  final isFirstSong = true;
  final isLastSong = true;
  final isQueueLoopModeEnabled = ObservableValue(true);
  final isLoopModeEnabled = ObservableValue(false);
  final isShuffleModeEnabled = ObservableValue(false);
  final currentSong = ObservableNullable<MediaItem>();

  /// The audio-service bridge can briefly expose an empty media item while a
  /// new installation starts its Android service. It is not a playable track
  /// and must not reserve a blank mini-player panel.
  static bool isDisplayableSong(MediaItem? song) =>
      song != null &&
      song.playable == true &&
      song.id.trim().isNotEmpty &&
      song.title.trim().isNotEmpty;

  bool get hasDisplayableCurrentSong => isDisplayableSong(currentSong.value);

  final isCurrentSongFav = ObservableValue(false);
  final playingFrom = ObservableValue(
    PlayingFrom(type: PlayingFromType.SELECTION),
  );
  final showLyricsFlag = ObservableValue(false);
  final isLyricsLoading = ObservableValue(false);
  final lyricsMode = ObservableValue(0);
  bool isDesktopLyricsDialogOpen = false;

  // 0 for play, 1 for pause, 2 for blank
  final gesturePlayerVisibleState = ObservableValue(2);
  final lyricController = LyricController();
  String? _loadedSyncedLyrics;
  int _lyricsLoadGeneration = 0;
  ObservableMap<String, dynamic> lyrics = ObservableMap({
    "synced": "",
    "plainLyrics": "",
  });
  ScrollController scrollController = ScrollController();
  final GlobalKey<ScaffoldState> homeScaffoldKey = GlobalKey<ScaffoldState>();

  final buttonState = ObservableValue(PlayButtonState.paused);

  // track whether wakelock is currently enabled to avoid repeated calls
  bool _wakelockActive = false;
  bool _playbackWakeLockActive = false;
  Future<void>? _playbackCommand;

  var _newSongFlag = true;
  final isCurrentSongBuffered = ObservableValue(false);

  // Edge detection for externally-initiated repeat/shuffle changes
  // (see _reflectExternalRepeatShuffleChanges).
  AudioServiceRepeatMode? _lastSeenRepeatMode;
  AudioServiceShuffleMode? _lastSeenShuffleMode;

  StreamSubscription<bool>? keyboardSubscription;
  var _initialized = false;
  var _disposed = false;
  var _playerChangeNotificationScheduled = false;
  static const _sourceStartProgressWindow = Duration(seconds: 10);
  String? _pendingPlaybackStartSongId;
  final List<StreamSubscription<dynamic>> _observableSubscriptions = [];

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

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _bindObservableState();
    await _init();
    if (RuntimePlatform.isWindows) {
      _windowsAudioService = WindowsAudioService(this);
    }
    await _restorePrevSession();
  }

  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);

  void _bindObservableState() {
    void watchValue<T>(ObservableValue<T> value) {
      _observableSubscriptions.add(value.listen((_) => _notifyPlayerChanged()));
    }

    void watchList<T>(ObservableList<T> value) {
      _observableSubscriptions.add(value.listen((_) => _notifyPlayerChanged()));
    }

    void watchMap<K, V>(ObservableMap<K, V> value) {
      _observableSubscriptions.add(value.listen((_) => _notifyPlayerChanged()));
    }

    watchList(currentQueue);
    watchValue(playerPaneOpacity);
    watchValue(playerPanelTopVisible);
    watchValue(playerPanelOpen);
    watchValue(playerPanelMinHeight);
    watchValue(isQueueReorderingInProcess);
    watchValue(timerDurationLeft);
    watchValue(isSleepTimerActive);
    watchValue(isSleepEndOfSongActive);
    watchValue(volume);
    watchValue(currentSongIndex);
    watchValue(isQueueLoopModeEnabled);
    watchValue(isLoopModeEnabled);
    watchValue(isShuffleModeEnabled);
    watchValue(currentSong);
    watchValue(isCurrentSongFav);
    watchValue(playingFrom);
    watchValue(showLyricsFlag);
    watchValue(isLyricsLoading);
    watchValue(lyricsMode);
    watchValue(gesturePlayerVisibleState);
    watchMap(lyrics);
    watchValue(buttonState);
    watchValue(isCurrentSongBuffered);
  }

  void _notifyPlayerChanged() {
    if (_disposed || _playerChangeNotificationScheduled) return;
    _playerChangeNotificationScheduled = true;
    scheduleMicrotask(() {
      _playerChangeNotificationScheduled = false;
      if (!_disposed) {
        notifyListeners();
      }
    });
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
    isLoopModeEnabled.value = _settingsRepository.getLoopModeEnabled();
    isShuffleModeEnabled.value = _settingsRepository.getShuffleModeEnabled();
    isQueueLoopModeEnabled.value = _settingsRepository
        .getQueueLoopModeEnabled();

    if (RuntimePlatform.isDesktop) {
      await setVolume(_settingsRepository.getVolume());
    }

    if (_settingsRepository.getPlayerUi() == 1) {
      initGesturePlayerStateAnimationController();
    }

    // only for android auto
    if (RuntimePlatform.isAndroid) {
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
    lyricsMode.value = _settingsRepository.getLyricsMode();
  }

  void panelListener(double x) {
    if (x >= 0 && x <= 0.2) {
      playerPaneOpacity.value = 1 - (x * 5);
      playerPanelTopVisible.value = true;
    } else if (x > 0.2) {
      playerPanelTopVisible.value = false;
    }

    // 0.6 threshold (not exact 1.0): the flag must flip while the panel is
    // clearly past halfway so dependent UI (nav bar) doesn't wait on the
    // animation landing exactly on the bound, and doesn't thrash mid-drag.
    if (x > 0.6) {
      playerPanelOpen.value = true;
    } else {
      playerPanelOpen.value = false;
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
      _reflectExternalRepeatShuffleChanges(playerState);
      if (_isWaitingForCurrentSourceStart && _isReadySourceStart(playerState)) {
        _clearPendingSourceStart();
      }
      if (!isPlaying ||
          processingState == AudioProcessingState.completed ||
          processingState == AudioProcessingState.error) {
        _clearPendingSourceStart();
      }

      if (processingState == AudioProcessingState.loading) {
        _setButtonState(PlayButtonState.loading);
      } else if (processingState == AudioProcessingState.buffering) {
        _setButtonState(PlayButtonState.loading);
      } else if (_isWaitingForCurrentSourceStart &&
          isPlaying &&
          processingState != AudioProcessingState.completed &&
          processingState != AudioProcessingState.error) {
        _setButtonState(PlayButtonState.loading);
      } else if (!isPlaying || processingState == AudioProcessingState.error) {
        _setButtonState(PlayButtonState.paused);
      } else if (processingState == AudioProcessingState.completed) {
        _setButtonState(PlayButtonState.paused);
      } else {
        _setButtonState(PlayButtonState.playing);
      }

      // Keep the screen awake whenever playback is active and the setting is enabled.
      final shouldEnable =
          _settingsController.keepScreenAwake.value && isPlaying;
      _setWakelock(shouldEnable);
      final shouldHoldPlaybackWakeLock =
          isPlaying &&
          processingState != AudioProcessingState.completed &&
          processingState != AudioProcessingState.error &&
          processingState != AudioProcessingState.idle;
      _setPlaybackWakeLock(shouldHoldPlaybackWakeLock);
    });
  }

  /// Mirror repeat/shuffle changes made by external media controllers (car
  /// head units over Bluetooth/AVRCP, notification, Android Auto) into the UI
  /// observables so the icons stay truthful. Edge-detected: the BehaviorSubject
  /// replays an initial PlaybackState (repeatMode none) on subscribe, which
  /// must not clobber the settings-seeded values during startup.
  void _reflectExternalRepeatShuffleChanges(PlaybackState playerState) {
    final repeatMode = playerState.repeatMode;
    if (_lastSeenRepeatMode != null && repeatMode != _lastSeenRepeatMode) {
      final enabled = repeatMode != AudioServiceRepeatMode.none;
      if (isLoopModeEnabled.value != enabled) {
        isLoopModeEnabled.value = enabled;
      }
    }
    _lastSeenRepeatMode = repeatMode;

    final shuffleMode = playerState.shuffleMode;
    if (_lastSeenShuffleMode != null && shuffleMode != _lastSeenShuffleMode) {
      final enabled = shuffleMode != AudioServiceShuffleMode.none;
      if (isShuffleModeEnabled.value != enabled) {
        isShuffleModeEnabled.value = enabled;
        // Mirror the queue-loop coupling from toggleShuffleMode.
        if (enabled && !isQueueLoopModeEnabled.value) {
          isQueueLoopModeEnabled.value = true;
        } else if (!enabled) {
          isQueueLoopModeEnabled.value = _settingsRepository
              .getQueueLoopModeEnabled();
        }
      }
    }
    _lastSeenShuffleMode = shuffleMode;
  }

  void _setButtonState(PlayButtonState state) {
    if (buttonState.value == state) return;
    buttonState.value = state;
    _notifyPlayerChanged();
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
      if (_isWaitingForCurrentSourceStart) {
        final playbackState = _audioHandler.playbackState.value;
        if (!_isReadySourceStart(playbackState) ||
            !_isSourceStartPosition(position)) {
          return;
        }
        _clearPendingSourceStart();
        _setButtonState(PlayButtonState.playing);
      }
      final oldState = progressBarStatus.value;
      final clampedPosition = _clampProgressPosition(position, oldState.total);
      if (isSleepEndOfSongActive.value) {
        timerDurationLeft.value =
            oldState.total.inSeconds - clampedPosition.inSeconds;
        if (timerDurationLeft.value == 1) {
          requestPause();
          cancelSleepTimer();
        }
      }
      progressBarStatus.update((val) {
        val.current = clampedPosition;
        val.buffered = oldState.buffered;
        val.total = oldState.total;
      });
      lyricController.setProgress(clampedPosition);
    });
  }

  void _listenForChangesInBufferedPosition() {
    _audioHandler.playbackState.listen((playbackState) async {
      final oldState = progressBarStatus.value;
      final startedPendingSource =
          _isWaitingForCurrentSourceStart && _isReadySourceStart(playbackState);
      if (_isWaitingForCurrentSourceStart && !startedPendingSource) return;

      if (startedPendingSource) {
        _clearPendingSourceStart();
        _setButtonState(PlayButtonState.playing);
      }

      final currentPosition = startedPendingSource
          ? _clampProgressPosition(playbackState.updatePosition, oldState.total)
          : oldState.current;
      final bufferedPosition = _clampProgressPosition(
        playbackState.bufferedPosition,
        oldState.total,
      );
      progressBarStatus.update((val) {
        val.buffered = bufferedPosition;
        val.current = currentPosition;
        val.total = oldState.total;
      });
      if (startedPendingSource) {
        lyricController.setProgress(currentPosition);
      }

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
    });
  }

  void _listenForChangesInDuration() {
    _audioHandler.mediaItem.listen((mediaItem) async {
      if (mediaItem == null || !isDisplayableSong(mediaItem)) {
        currentSong.value = null;
        _clearPendingSourceStart();
        progressBarStatus.update((val) {
          val.total = Duration.zero;
          val.current = Duration.zero;
          val.buffered = Duration.zero;
        });
        _notifyPlayerChanged();
        return;
      }

      final previousSongId = currentSong.value?.id;
      final isSameSong = previousSongId == mediaItem.id;
      printINFO(mediaItem.title, tag: LogTags.player);
      _newSongFlag = true;
      isCurrentSongBuffered.value = false;
      currentSong.value = mediaItem;
      currentSongIndex.value = currentQueue.indexWhere(
        (element) => element.id == currentSong.value!.id,
      );
      if (!isSameSong) {
        _beginPendingSourceStart(mediaItem.id);
      }
      final nextTotal = mediaItem.duration ?? Duration.zero;
      progressBarStatus.update((val) {
        // A same-song rebroadcast (e.g. shuffle rewriting the queue) can carry
        // a stale item without a duration — keep the known total instead of
        // collapsing it to zero, which would pin the progress bar at 0:00.
        val.total = nextTotal > Duration.zero
            ? nextTotal
            : (isSameSong ? val.total : Duration.zero);
        val.current = isSameSong
            ? _clampProgressPosition(val.current, val.total)
            : Duration.zero;
        val.buffered = isSameSong
            ? _clampProgressPosition(val.buffered, val.total)
            : Duration.zero;
      });
      // Coalesced: the observable writes above already scheduled a
      // microtask notification via _notifyPlayerChanged; a direct
      // notifyListeners() here would rebuild every listener twice per song
      // change (a visible hitch on next/prev).
      _notifyPlayerChanged();
      if (!isSameSong) {
        _clearLyricsForSongChange();
      }
      final appContext = AppNavigator.context;
      if (isDesktopLyricsDialogOpen && appContext != null) {
        Navigator.pop(appContext);
      }

      // reset player visible state when player is in gesture mode
      if (_settingsController.playerUi.value == 1) {
        gesturePlayerVisibleState.value = 2;
      }

      unawaited(_updateCurrentSongSideEffects(mediaItem));
    });
  }

  Duration _clampProgressPosition(Duration position, Duration total) {
    if (position < Duration.zero) return Duration.zero;
    if (total > Duration.zero && position > total) return total;
    return position;
  }

  bool get _isWaitingForCurrentSourceStart =>
      _pendingPlaybackStartSongId != null &&
      _pendingPlaybackStartSongId == currentSong.value?.id;

  bool _isSourceStartPosition(Duration position) {
    return position <= _sourceStartProgressWindow;
  }

  bool _isReadySourceStart(PlaybackState playbackState) {
    return playbackState.processingState == AudioProcessingState.ready &&
        playbackState.playing &&
        _isSourceStartPosition(playbackState.updatePosition);
  }

  void _beginPendingSourceStart(String songId) {
    _pendingPlaybackStartSongId = songId;
    _setButtonState(PlayButtonState.loading);
  }

  void _clearPendingSourceStart() {
    _pendingPlaybackStartSongId = null;
  }

  Future<void> _updateCurrentSongSideEffects(MediaItem mediaItem) async {
    await _checkFavFor(mediaItem);
    await _addToRP(mediaItem);
    await _backfillLibraryDuration(mediaItem);
    if (currentSong.value?.id == mediaItem.id &&
        isRadioModeOn &&
        currentQueue.isNotEmpty &&
        mediaItem.id == currentQueue.last.id) {
      await _addRadioContinuation(radioInitiatorItem!);
    }
  }

  /// Some sources add a song to the library with no duration; the real
  /// value only arrives once playback resolves the audio source. Persist it
  /// then (and patch the on-screen list) so the library stops showing a
  /// blank duration for that track.
  Future<void> _backfillLibraryDuration(MediaItem mediaItem) async {
    final duration = mediaItem.duration;
    if (duration == null || duration <= Duration.zero) return;
    await _libraryRepository.backfillSongDuration(mediaItem.id, duration);
    LibrarySongsControllerRegistry.current?.applyResolvedDuration(
      mediaItem.id,
      duration,
    );
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
      _notifyPlayerChanged();
    });
  }

  Future<void> _restorePrevSession() async {
    final restorePrevSessionEnabled = _settingsRepository
        .getRestorePlaybackSession();
    if (restorePrevSessionEnabled) {
      final songList = await _playbackSessionRepository.getQueue();
      final currentIndex = await _playbackSessionRepository.getIndex();
      final position = await _playbackSessionRepository.getPosition();
      if (songList.isNotEmpty && currentIndex != null && position != null) {
        await _playbackCommands.addQueueItems(songList);
        await _playerPanelCheck(restoreSession: true);
        await _playbackCommands.playByIndex(
          currentIndex,
          position: position,
          restoreSession: true,
        );
      }
    }
  }

  void _listenForCustomEvents() {
    _audioHandler.customEvent.listen((event) async {
      if (event['eventType'] == 'playFromMediaId') {
        await _playViaAndroidAuto(event['songId'], event['libraryId']);
      } else if (event['eventType'] == 'playError') {
        notifyPlayError(event['message'] as String? ?? 'networkError');
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
    // A guest's "play now" would otherwise replace the host's queue. Treat a
    // concrete song as a request instead; radio/playlist-id expansion remains
    // host-controlled because it cannot be represented as one safe song.
    if (_isSessionGuest) {
      if (mediaItem == null) {
        _showSessionUnavailableSnackbar();
        return;
      }
      _routeToHost(SessionCommand.enqueue(sessionSafeSongJson(mediaItem)));
      _showAddedToSharedQueueSnackbar();
      return;
    }

    /// update playing from value
    playingFrom.value = PlayingFrom(type: PlayingFromType.SELECTION, name: '');

    /// set global radio mode flag
    isRadioModeOn = radio;

    final queueUpdate = Future.delayed(Duration.zero, () async {
      final content = await _musicServices.getWatchPlaylist(
        videoId: mediaItem?.id ?? "",
        radio: radio,
        playlistId: playlistId,
      );
      radioContinuationParam = content['additionalParamsForNext'];
      await _playbackCommands.updateQueue(
        List<MediaItem>.from(content['tracks']),
      );
      if (isShuffleModeEnabled.value) {
        await _playbackCommands.shuffleFromIndex(0);
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
      await _playbackCommands.playByIndex(0);
      return;
    }

    unawaited(
      queueUpdate.then((value) async {
        if (_settingsRepository.getDiscoverContentType() == "BOLI") {
          await _homeScreenController.changeDiscoverContent(
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
    await _playbackCommands.setSourceAndPlay(mediaItem!);

    // disable queue loop mode when radio is started
    if (radio && isQueueLoopModeEnabled.value && !isShuffleModeEnabled.value) {
      await toggleQueueLoopMode();
    }
  }

  Future<void> playPlayListSong(
    List<MediaItem> mediaItems,
    int index, {
    PlayingFrom? playFrom,
  }) async {
    // A guest cannot safely replace the shared queue or play a local index.
    // Request the selected song as an append on the host instead.
    if (_isSessionGuest) {
      if (index < 0 || index >= mediaItems.length) return;
      _routeToHost(
        SessionCommand.enqueue(sessionSafeSongJson(mediaItems[index])),
      );
      _showAddedToSharedQueueSnackbar();
      return;
    }

    isRadioModeOn = false;
    //open player pane,set current song and push first song into playing list,

    /// update playing from value
    playingFrom.value =
        playFrom ?? PlayingFrom(type: PlayingFromType.SELECTION);

    //for changing home content based on last iteration
    unawaited(
      Future.delayed(const Duration(seconds: 3), () async {
        if (_settingsRepository.getDiscoverContentType() == "BOLI") {
          await _homeScreenController.changeDiscoverContent(
            "BOLI",
            songId: mediaItems[index].id,
          );
        }
      }),
    );

    await _playerPanelCheck();
    await _playbackCommands.updateQueue(mediaItems);
    if (isShuffleModeEnabled.value) {
      await _playbackCommands.shuffleFromIndex(index);
      await _playbackCommands.playByIndex(0);
      return;
    }
    await _playbackCommands.playByIndex(index);
  }

  Future<void> startRadio(MediaItem? mediaItem, {String? playlistId}) async {
    radioInitiatorItem = mediaItem ?? playlistId;
    await pushSongToQueue(mediaItem, playlistId: playlistId, radio: true);
  }

  Future<void> _addRadioContinuation(dynamic item) async {
    if (_isSessionGuest) return;
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
    if (_routeToHost(SessionCommand.enqueue(sessionSafeSongJson(mediaItem)))) {
      return;
    }
    if (currentQueue.isEmpty) {
      await playPlayListSong([mediaItem], 0);
      return;
    }
    //check if song is available in queue and if not add it to queue
    if (!currentQueue.contains(mediaItem)) {
      await _playbackCommands.addQueueItem(mediaItem);
    }
  }

  ///enqueueSongList method add song List to current queue
  Future<void> enqueueSongList(List<MediaItem> mediaItems) async {
    if (_isSessionGuest) {
      for (final chunk in chunkList(mediaItems, 50)) {
        _routeToHost(
          SessionCommand.enqueueList(chunk.map(sessionSafeSongJson).toList()),
        );
      }
      return;
    }
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
    await _playbackCommands.addQueueItems(listToEnqueue);
  }

  Future<void> _playViaAndroidAuto(String songId, String libraryId) async {
    final songList = switch (libraryId) {
      BoxNames.songDownloads => await _libraryRepository.getDownloadedSongs(),
      BoxNames.songsCache => await _libraryRepository.getCachedSongs(),
      BoxNames.libFav => await _libraryRepository.getFavoriteSongs(),
      BoxNames.libFavNotDownloaded =>
        await _libraryRepository.getFavoriteNotDownloadedSongs(),
      BoxNames.libImportDuplicates =>
        await _libraryRepository.getImportDuplicateSongs(),
      BoxNames.libImportReview =>
        await _libraryRepository.getImportReviewSongs(),
      BoxNames.libRP => await _libraryRepository.getRecentlyPlayedSongs(),
      _ => <MediaItem>[],
    };
    final songIndex = songList.indexWhere((song) => song.id == songId);
    await playPlayListSong(songList, songIndex < 0 ? 0 : songIndex);
  }

  Future<void> playNext(MediaItem song) async {
    if (_routeToHost(SessionCommand.playNextSong(sessionSafeSongJson(song)))) {
      return;
    }
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
          : await _playbackCommands.addPlayNextItem(song);
    }
  }

  Future<void> _playerPanelCheck({bool restoreSession = false}) async {
    final appContext = AppNavigator.context;
    final screenSize = appContext == null
        ? Size.zero
        : MediaQuery.of(appContext).size;
    final isWideScreen = screenSize.width > 800;
    final autoOpenPlayer = _settingsRepository.getAutoOpenPlayer();
    if (initFlagForPlayer || playerPanelMinHeight.value == 0) {
      final bottomNavVisible =
          _settingsController.isBottomNavBarEnabled.value &&
          getCurrentRouteName() == '/homeScreen' &&
          !playerPanelOpen.value;
      playerPanelMinHeight.value = appContext == null
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
      initFlagForPlayer = false;
      // Publish the new min height *before* auto-opening the panel so the
      // panel does not animate open from a zero-height mini player.
      _notifyPlayerChanged();
    }

    if ((!isWideScreen && autoOpenPlayer && playerPanelController.isAttached) &&
        !restoreSession) {
      await playerPanelController.open();
    }
  }

  Future<void> removeFromQueue(MediaItem song) async {
    await _playbackCommands.removeQueueItem(song);
  }

  Future<void> clearQueue() async {
    await _playbackCommands.clearQueue();
  }

  Future<void> shuffleQueue() async {
    await _playbackCommands.shuffleQueue();
  }

  Future<void> toggleShuffleMode() async {
    if (_routeToHost(SessionCommand.toggleShuffle())) return;
    final shuffleModeEnabled = isShuffleModeEnabled.value;
    final nextEnabled = await _playbackCommands.toggleShuffle(
      enabled: shuffleModeEnabled,
    );
    isShuffleModeEnabled.value = nextEnabled;
    // restrict queue loop mode when shuffle mode is enabled
    if (isShuffleModeEnabled.value && !isQueueLoopModeEnabled.value) {
      isQueueLoopModeEnabled.value = true;
    } else if (!isShuffleModeEnabled.value) {
      isQueueLoopModeEnabled.value = _settingsRepository
          .getQueueLoopModeEnabled();
    }
  }

  Future<void> onReorder(int oldIndex, int newIndex) async {
    await _playbackCommands.reorderQueue(
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
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
    await _playbackCommands.updateQueue(reorderedQueue);
  }

  void onReorderStart(int index) {
    isQueueReorderingInProcess.value = true;
  }

  void onReorderEnd(int index) {
    isQueueReorderingInProcess.value = false;
  }

  /// Returns true and forwards the intent to the host when this device is a
  /// guest in a Listen Together session, so callers can short-circuit local
  /// execution.
  bool get _isSessionGuest => listenTogetherGate?.isGuest ?? false;

  bool _routeToHost(SessionCommand command) {
    final gate = listenTogetherGate;
    if (gate != null && gate.isGuest) {
      gate.sendCommand(command);
      return true;
    }
    return false;
  }

  void _showSessionSnackbar(String message) {
    final context = AppNavigator.context;
    if (context == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      snackbar(
        context,
        message,
        size: SanckBarSize.BIG,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showAddedToSharedQueueSnackbar() {
    final context = AppNavigator.context;
    if (context == null) return;
    _showSessionSnackbar(context.l10n.addedToSharedQueue);
  }

  void _showSessionUnavailableSnackbar() {
    final context = AppNavigator.context;
    if (context == null) return;
    _showSessionSnackbar(context.l10n.notAvailableInSession);
  }

  Future<void> play() async {
    if (_routeToHost(SessionCommand.play())) return;
    await _playbackCommands.play();
  }

  void requestPlay() {
    _runPlaybackCommand(() => play());
  }

  Future<void> pause() async {
    if (_routeToHost(SessionCommand.pause())) return;
    await _playbackCommands.pause();
  }

  void requestPause() {
    _runPlaybackCommand(() => pause());
  }

  Future<void> playPause() async {
    if (initFlagForPlayer) return;
    if (_routeToHost(SessionCommand.playPause())) return;
    await _playbackCommands.playPause(
      isPlaying: _audioHandler.playbackState.value.playing,
    );
    // for gesture player
    if (_settingsController.playerUi.value == 1) {
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
    if (_routeToHost(SessionCommand.prev())) return;
    await _playbackCommands.previous();
  }

  void requestPrev() {
    _runPlaybackCommand(() => prev());
  }

  Future<void> next() async {
    if (_routeToHost(SessionCommand.next())) return;
    await _playbackCommands.next();
  }

  void requestNext() {
    _runPlaybackCommand(() => next());
  }

  Future<void> seek(Duration position) async {
    if (_routeToHost(SessionCommand.seek(position))) return;
    await _playbackCommands.seek(position);
  }

  void requestSeek(Duration position) {
    _runPlaybackCommand(() => seek(position));
  }

  Future<void> seekByIndex(int index) async {
    if (listenTogetherGate?.isPartyModeGuest ?? false) {
      _showSessionUnavailableSnackbar();
      return;
    }
    if (_routeToHost(SessionCommand.playByIndex(index))) return;
    await _playbackCommands.playByIndex(index);
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
    await _playbackCommands.toggleSkipSilence(enable);
  }

  Future<void> toggleLoudnessNormalization(bool enable) async {
    await _playbackCommands.toggleLoudnessNormalization(enable);
  }

  Future<void> toggleLoopMode() async {
    if (_routeToHost(SessionCommand.toggleLoop())) return;
    isLoopModeEnabled.value = await _playbackCommands.toggleLoop(
      enabled: isLoopModeEnabled.value,
    );
  }

  Future<void> toggleQueueLoopMode({bool showMessage = true}) async {
    if (isShuffleModeEnabled.value && isQueueLoopModeEnabled.value) {
      if (!showMessage) return;
      final context = AppNavigator.context;
      if (context == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(
          context,
          context.l10n.queueLoopNotDisMsg1,
          size: SanckBarSize.BIG,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (isRadioModeOn && !isQueueLoopModeEnabled.value) {
      if (!showMessage) return;
      final context = AppNavigator.context;
      if (context == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(
          context,
          context.l10n.queueLoopNotDisMsg2,
          size: SanckBarSize.BIG,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    isQueueLoopModeEnabled.value = !isQueueLoopModeEnabled.value;
    await _playbackCommands.setQueueLoopMode(isQueueLoopModeEnabled.value);
  }

  Future<void> setVolume(int value) async {
    await _playbackCommands.setVolume(value);
    volume.value = value;
    await _settingsRepository.setVolume(value);
  }

  Future<void> mute() async {
    int? vol;
    if (volume.value != 0) {
      vol = 0;
    } else {
      vol = _settingsRepository.getVolume(defaultValue: 10);
      if (vol == 0) {
        vol = 10;
        await _settingsRepository.setVolume(vol);
      }
    }
    await _playbackCommands.setVolume(vol);
    volume.value = vol;
  }

  Future<void> _checkFavFor(MediaItem song) async {
    final isFavorite = await _libraryRepository.isFavorite(song.id);
    if (currentSong.value?.id == song.id) {
      isCurrentSongFav.value = isFavorite;
    }
  }

  Future<void> toggleFavourite() async {
    final currMediaItem = currentSong.value!;
    await _libraryRepository.setFavorite(
      currMediaItem,
      !isCurrentSongFav.value,
    );
    try {
      final playlistController = PlaylistScreenControllerRegistry.maybeOf(
        const Key(BoxNames.libFav).hashCode.toString(),
      );
      if (playlistController != null) {
        !isCurrentSongFav.value
            ? await playlistController.addNRemoveItemsInList(
                currMediaItem,
                action: 'add',
                index: 0,
              )
            : await playlistController.addNRemoveItemsInList(
                currMediaItem,
                action: 'remove',
              );
      }

      // ignore: empty_catches
    } catch (e) {}
    try {
      final likedNotDownloadedController =
          PlaylistScreenControllerRegistry.maybeOf(
            const Key(BoxNames.libFavNotDownloaded).hashCode.toString(),
          );
      if (likedNotDownloadedController != null) {
        if (!isCurrentSongFav.value &&
            !await _libraryRepository.isDownloaded(currMediaItem.id)) {
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
      }
      // ignore: empty_catches
    } catch (e) {}
    isCurrentSongFav.value = !isCurrentSongFav.value;
    // Favorites/liked built-in tiles derive artwork from their first song.
    unawaited(
      LibraryPlaylistsControllerRegistry.current
              ?.refreshInitialPlaylistThumbs() ??
          Future.value(),
    );
    if (_settingsController.autoDownloadFavoriteSongEnabled.value &&
        isCurrentSongFav.value) {
      await _downloader.download(currMediaItem);
    }
  }

  // ignore: prefer_typing_uninitialized_variables
  var recentItem;

  /// This function is used to add a mediaItem/Song to Recently played playlist
  Future<void> _addToRP(MediaItem mediaItem) async {
    if (recentItem != mediaItem) {
      final before = await _libraryRepository.getRecentlyPlayedSongs();
      final removedSongId = before.length >= 30 ? before.first.id : null;
      await _libraryRepository.addRecentlyPlayedSong(mediaItem);
      try {
        final playlistController = PlaylistScreenControllerRegistry.maybeOf(
          const Key(BoxNames.libRP).hashCode.toString(),
        );
        if (playlistController != null) {
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
        }

        // ignore: empty_catches
      } catch (e) {}
      // Recently-played built-in tile derives artwork from its newest song.
      unawaited(
        LibraryPlaylistsControllerRegistry.current
                ?.refreshInitialPlaylistThumbs() ??
            Future.value(),
      );
    }
    recentItem = mediaItem;
  }

  Future<void> showLyrics() async {
    showLyricsFlag.value = !showLyricsFlag.value;
    notifyListeners();
    if ((lyrics["synced"].isEmpty && lyrics['plainLyrics'].isEmpty) &&
        showLyricsFlag.value) {
      final song = currentSong.value;
      if (song == null) return;
      final songId = song.id;
      final generation = ++_lyricsLoadGeneration;
      isLyricsLoading.value = true;
      notifyListeners();
      try {
        final Map<String, dynamic>? lyricsR =
            await SyncedLyricsService.getSyncedLyrics(
              song,
              progressBarStatus.value.total.inSeconds,
              _lyricsRepository,
            );
        if (!_isCurrentLyricsRequest(songId, generation)) return;
        if (lyricsR != null) {
          lyrics.value = lyricsR;
          isLyricsLoading.value = false;
          notifyListeners();
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
        notifyListeners();
      } catch (e) {
        if (!_isCurrentLyricsRequest(songId, generation)) return;
        lyrics.value = {"synced": "", "plainLyrics": "NA"};
        notifyListeners();
      } finally {
        if (_isCurrentLyricsRequest(songId, generation)) {
          isLyricsLoading.value = false;
          notifyListeners();
        }
      }
    }
  }

  Future<void> changeLyricsMode(int? val) async {
    await _settingsRepository.setLyricsMode(val ?? 0);
    lyricsMode.value = val ?? 0;
    notifyListeners();
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
    notifyListeners();
  }

  bool _isCurrentLyricsRequest(String songId, int generation) {
    return generation == _lyricsLoadGeneration &&
        currentSong.value?.id == songId;
  }

  void sleepEndOfSong() {
    isSleepTimerActive.value = true;
    isSleepEndOfSongActive.value = true;
    notifyListeners();
  }

  void startSleepTimer(int minutes) {
    timerDuration = minutes * 60;
    isSleepTimerActive.value = true;
    notifyListeners();
    if ((sleepTimer != null && !sleepTimer!.isActive) || sleepTimer == null) {
      sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (timer.tick == timerDuration) {
          sleepTimer?.cancel();
          requestPause();
          isSleepTimerActive.value = false;
          timerDuration = 0;
          timerDurationLeft.value = 0;
          notifyListeners();
        } else {
          timerDurationLeft.value = timerDuration - timer.tick;
          notifyListeners();
        }
      });
    }
  }

  void addFiveMinutes() {
    timerDuration += 300;
    notifyListeners();
  }

  void cancelSleepTimer() {
    if (isSleepEndOfSongActive.value) {
      isSleepEndOfSongActive.value = false;
    }
    sleepTimer?.cancel();
    isSleepTimerActive.value = false;
    timerDuration = 0;
    timerDurationLeft.value = 0;
    notifyListeners();
  }

  Future<void> openEqualizer() async {
    await _audioHandler.customAction("openEqualizer");
  }

  /// Called from audio handler in case audio is not playable
  /// or returned streamInfo null due to network error
  void notifyPlayError(String message) {
    final context = AppNavigator.context;
    if (context == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      snackbar(context, switch (message) {
        "networkError" => context.l10n.networkError,
        "resolverPlaybackFailed" => context.l10n.resolverPlaybackFailed,
        _ => message,
      }, size: SanckBarSize.MEDIUM),
    );
  }

  Map<String, dynamic> playbackDebugSnapshot() {
    final playback = _audioHandler.playbackState.value;
    final handlerMediaItem = _audioHandler.mediaItem.value;
    final handlerQueue = _audioHandler.queue.value;
    final progress = progressBarStatus.value;
    final current = currentSong.value;
    return {
      'playerController': {
        'buttonState': buttonState.value.name,
        'currentSongIndex': currentSongIndex.value,
        'currentSong': _mediaItemDebug(current),
        'currentQueueLength': currentQueue.length,
        'displayQueueLength': displayQueue.length,
        'isShuffleModeEnabled': isShuffleModeEnabled.value,
        'isLoopModeEnabled': isLoopModeEnabled.value,
        'isQueueLoopModeEnabled': isQueueLoopModeEnabled.value,
        'isCurrentSongBuffered': isCurrentSongBuffered.value,
        'isRadioModeOn': isRadioModeOn,
        'isSleepTimerActive': isSleepTimerActive.value,
        'isSleepEndOfSongActive': isSleepEndOfSongActive.value,
        'timerDuration': timerDuration,
        'timerDurationLeft': timerDurationLeft.value,
        'progressCurrentMs': progress.current.inMilliseconds,
        'progressBufferedMs': progress.buffered.inMilliseconds,
        'progressTotalMs': progress.total.inMilliseconds,
        'pendingPlaybackStartSongId': _pendingPlaybackStartSongId,
        'isWaitingForCurrentSourceStart': _isWaitingForCurrentSourceStart,
        'sourceStartProgressWindowMs':
            _sourceStartProgressWindow.inMilliseconds,
        'playerPanelMinHeight': playerPanelMinHeight.value,
        'playerPanelTopVisible': playerPanelTopVisible.value,
        'isPanelGTHOpened': playerPanelOpen.value,
        'lyricsMode': lyricsMode.value,
        'showLyricsFlag': showLyricsFlag.value,
        'isLyricsLoading': isLyricsLoading.value,
      },
      'audioHandler': {
        'mediaItem': _mediaItemDebug(handlerMediaItem),
        'queueLength': handlerQueue.length,
        'queueIndex': playback.queueIndex,
        'playing': playback.playing,
        'processingState': playback.processingState.name,
        'repeatMode': playback.repeatMode.name,
        'shuffleMode': playback.shuffleMode.name,
        'updatePositionMs': playback.updatePosition.inMilliseconds,
        'bufferedPositionMs': playback.bufferedPosition.inMilliseconds,
        'speed': playback.speed,
        'errorCode': playback.errorCode,
        'errorMessage': playback.errorMessage,
      },
    };
  }

  Future<Map<String, dynamic>> detailedPlaybackDebugSnapshot() async {
    final snapshot = playbackDebugSnapshot();
    try {
      final handlerSnapshot = await _audioHandler.customAction(
        'playbackDebugSnapshot',
      );
      if (handlerSnapshot is Map) {
        snapshot['audioHandlerInternal'] = Map<String, dynamic>.from(
          handlerSnapshot,
        );
      }
    } catch (error) {
      snapshot['audioHandlerInternalError'] = error.toString();
    }
    return snapshot;
  }

  Map<String, dynamic>? _mediaItemDebug(MediaItem? item) {
    if (item == null) return null;
    return {
      'id': item.id,
      'title': item.title,
      'artist': item.artist,
      'album': item.album,
      'durationMs': item.duration?.inMilliseconds,
      'artUri': item.artUri?.toString(),
      'extras': _extrasDebug(item.extras),
    };
  }

  Map<String, dynamic>? _extrasDebug(Map<String, dynamic>? extras) {
    if (extras == null) return null;
    return {for (final entry in extras.entries) entry.key: _debugValue(entry)};
  }

  Object? _debugValue(MapEntry<String, dynamic> entry) {
    final key = entry.key.toLowerCase();
    final value = entry.value;
    if (key.contains('url') ||
        key.contains('token') ||
        key.contains('cookie')) {
      return _redactedUrlDebug(value);
    }
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is Uri) return value.toString();
    if (value is Map) return {'type': 'Map', 'keys': value.keys.toList()};
    if (value is Iterable) return {'type': 'Iterable', 'length': value.length};
    return value.toString();
  }

  Map<String, dynamic>? _redactedUrlDebug(Object? value) {
    if (value == null) return null;
    final url = value.toString();
    final uri = Uri.tryParse(url);
    return {
      'isEmpty': url.isEmpty,
      'scheme': uri?.scheme,
      'host': uri?.host,
      'pathLength': uri?.path.length,
      'queryParameterCount': uri?.queryParameters.length,
    };
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_audioHandler.customAction('dispose'));
    for (final subscription in _observableSubscriptions) {
      unawaited(subscription.cancel());
    }
    _observableSubscriptions.clear();
    unawaited(keyboardSubscription?.cancel());
    scrollController.dispose();
    lyricController.dispose();
    gesturePlayerStateAnimationController?.dispose();
    sleepTimer?.cancel();
    if (RuntimePlatform.isWindows) {
      _windowsAudioService?.dispose();
      _windowsAudioService = null;
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
