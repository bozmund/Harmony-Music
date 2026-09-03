import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:harmonymusic/l10n/app_localizations.dart';
import 'package:harmonymusic/l10n/l10n.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_service/audio_service.dart';

// ignore: depend_on_referenced_packages
import 'package:rxdart/rxdart.dart';

import '../domain/repositories/download_repository.dart';
import '../domain/repositories/library_repository.dart';
import '../domain/repositories/playback_session_repository.dart';
import '../domain/repositories/playlist_repository.dart';
import '../domain/repositories/settings_repository.dart';
import '../domain/repositories/song_cache_repository.dart';
import '../utils/runtime_platform.dart';
import '../utils/song_cache_storage.dart';
import '/services/constant.dart';
import '/services/crash_diagnostics_service.dart';
import '/services/playback_queue_order.dart';
import '/services/playback_preload_service.dart';
import '/services/playback_start_trace.dart';
import '/services/previous_track_policy.dart';
import '/services/equalizer.dart';
import '/services/desktop_audio_platform.dart';
import '/services/stream_service.dart';
import '/models/hm_streaming_data.dart';
import '/services/background_task.dart';
import '/services/permission_service.dart';
import 'resolver/resolver_audio_source.dart';
import 'resolver/resolver_playback_client.dart';
import 'resolver/resolver_source_mode.dart';
import '../utils/helper.dart';
import '/models/media_Item_builder.dart';
import '/services/utils.dart';
import '../ui/screens/Library/library_controller.dart';

const _androidNotificationArtSize = 256;
const _fallbackCompletionGrace = Duration(milliseconds: 1250);
// How long playback may sit in ProcessingState.buffering without the position
// moving before the stall watchdog regenerates the stream URL. Initial song
// starts are covered by isSongLoading, so this only fires on post-start
// stalls (e.g. a silently dropped or throttled CDN connection).
const _bufferingStallThreshold = Duration(seconds: 12);
const _bufferingStallPositionTolerance = Duration(milliseconds: 300);

Future<AudioHandler> initAudioService({
  required SettingsRepository settingsRepository,
  required LibraryRepository libraryRepository,
  required DownloadRepository downloadRepository,
  required SongCacheRepository songCacheRepository,
  required PlaylistRepository playlistRepository,
  required PlaybackSessionRepository playbackSessionRepository,
  ResolverPlaybackClient? resolverPlaybackClient,
}) async {
  final handler = await MyAudioHandler.create(
    settingsRepository: settingsRepository,
    libraryRepository: libraryRepository,
    downloadRepository: downloadRepository,
    songCacheRepository: songCacheRepository,
    playlistRepository: playlistRepository,
    playbackSessionRepository: playbackSessionRepository,
    resolverPlaybackClient:
        resolverPlaybackClient ??
        ResolverPlaybackClient(
          settings: settingsRepository,
          accessToken: () async => null,
          enabled: false,
        ),
  );
  // audio_service configures a native media session. Its platform channel has
  // no browser implementation, while MyAudioHandler itself uses just_audio's
  // web backend directly. Avoid waiting on that unavailable channel before
  // the Flutter UI can mount.
  if (kIsWeb) return handler;
  return await AudioService.init(
    builder: () => handler,
    config: const AudioServiceConfig(
      androidNotificationIcon: 'mipmap/ic_launcher_monochrome',
      androidNotificationChannelId: 'com.mycompany.myapp.audio',
      androidNotificationChannelName: 'Harmony Music Notification',
      // Keep the service in the foreground while paused: a call-induced pause
      // must not demote it into an OOM-kill target mid-call, and just_audio's
      // in-memory resume-after-interruption flag must survive the call.
      // The AudioServiceConfig assert requires androidNotificationOngoing to
      // be false when androidStopForegroundOnPause is false.
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      artDownscaleWidth: _androidNotificationArtSize,
      artDownscaleHeight: _androidNotificationArtSize,
    ),
  );
}

class MyAudioHandler extends BaseAudioHandler {
  // ignore: prefer_typing_uninitialized_variables
  /// Scratch space that may legitimately be reclaimed: preload prefixes are
  /// re-fetched on demand.
  late final _cacheDir;

  /// Cached song audio, which may not. See [songCacheDirectory].
  late final String _cachedSongsDir;
  late AudioPlayer _player;
  late MediaLibrary _mediaLibrary;
  PlaybackPreloadService? _preloadService;
  late final SettingsRepository _settingsRepository;
  late final LibraryRepository _libraryRepository;
  late final DownloadRepository _downloadRepository;
  late final SongCacheRepository _songCacheRepository;
  late final PlaylistRepository _playlistRepository;
  late final PlaybackSessionRepository _playbackSessionRepository;
  late final ResolverPlaybackClient _resolverPlaybackClient;
  final Map<String, ResolverAudioSource> _resolverSources = {};
  ResolverOpenCancellation? _activeResolverCancellation;
  PlaybackStartTrace? _activePlaybackTrace;
  PlaybackSourceCategory _currentPlaybackSource =
      PlaybackSourceCategory.pending;

  // ignore: prefer_typing_uninitialized_variables
  dynamic currentIndex;
  late String? currentSongUrl;
  bool isPlayingUsingLockCachingSource = false;
  bool loopModeEnabled = false;
  bool queueLoopModeEnabled = true;
  bool shuffleModeEnabled = false;
  bool loudnessNormalizationEnabled = false;

  // var networkErrorPause = false;
  bool isSongLoading = true;
  bool _lastPreloadPlaying = false;
  bool _completionInProgress = false;
  bool _completionHandlingScheduled = false;
  bool _completionHandlingAllowEndPosition = false;
  bool _completionRetryScheduled = false;
  Timer? _completionWatchdogTimer;
  DateTime? _earlyCompletionDetectedAt;
  Duration? _earlyCompletionDelay;
  Duration? _stallWatchPosition;
  DateTime? _stallWatchSince;
  bool _stallRecoveryInFlight = false;
  bool _sourceSwitchInProgress = false;
  bool _sourceSwitchWasPlaying = false;
  DateTime? _previousRestartedAt;
  bool _remoteNotificationMirrorActive = false;
  MediaItem? _mediaItemBeforeRemoteNotification;
  PlaybackState? _playbackStateBeforeRemoteNotification;
  Timer? _sessionSaveDebounce;
  Timer? _periodicPositionSaveTimer;
  // Suppresses the automatic session-save triggers while a saved session is
  // being restored, so the persisted position isn't clobbered with 0.
  bool _suppressSessionSave = false;
  bool _wasPlayingForSessionSave = false;
  int _playbackGeneration = 0;
  bool _preEndWindowActive = false;
  Future<void>? _prepareNextSourceTask;
  int? _preparedForGeneration;
  int? _preparedNextIndex;
  String? _preparedNextSongId;
  HMStreamingData? _preparedNextStreamInfo;
  static const _androidTargetBufferBytes = 8 * 1024 * 1024;

  /// Backstop on resolving a song's stream before playback starts.
  ///
  /// The inner paths have their own, tighter bounds; this exists so that no
  /// combination of them can leave the await unsettled. `playByIndex` and
  /// `setSourceNPlay` tear down the previous source *before* this completes, so
  /// a future that never settles is a permanently wedged player showing a
  /// spinner and no error, which is what issue #66 reported. A TimeoutException
  /// here lands in the same catch as any other failure and gets the existing
  /// error surfacing for free.
  ///
  /// Sits above every inner bound — including the resolver's 30s ingestion
  /// poll — so it only ever fires on a genuine stall, never on a slow song.
  static const _sourceResolveTimeout = Duration(seconds: 60);

  List<MediaItem>? _queueBeforeShuffle;

  final _playList =
      // ignore: deprecated_member_use
      ConcatenatingAudioSource(children: [], useLazyPreparation: false);

  MyAudioHandler._({
    required SettingsRepository settingsRepository,
    required LibraryRepository libraryRepository,
    required DownloadRepository downloadRepository,
    required SongCacheRepository songCacheRepository,
    required PlaylistRepository playlistRepository,
    required PlaybackSessionRepository playbackSessionRepository,
    required ResolverPlaybackClient resolverPlaybackClient,
  }) {
    _settingsRepository = settingsRepository;
    _libraryRepository = libraryRepository;
    _downloadRepository = downloadRepository;
    _songCacheRepository = songCacheRepository;
    _playlistRepository = playlistRepository;
    _playbackSessionRepository = playbackSessionRepository;
    _resolverPlaybackClient = resolverPlaybackClient;

    if (RuntimePlatform.isWindows || RuntimePlatform.isLinux) {
      DesktopAudioPlatform.configure(
        onDiagnostic: (category, message) {
          CrashDiagnosticsService.instance.recordLog(
            'info',
            'windows-audio/$category',
            message,
          );
        },
      );
    }

    _mediaLibrary = MediaLibrary(
      libraryRepository: _libraryRepository,
      playlistRepository: _playlistRepository,
      settingsRepository: _settingsRepository,
    );

    _player = AudioPlayer(
      audioLoadConfiguration: const AudioLoadConfiguration(
        androidLoadControl: AndroidLoadControl(
          minBufferDuration: Duration(seconds: 15),
          maxBufferDuration: Duration(seconds: 45),
          bufferForPlaybackDuration: Duration(milliseconds: 200),
          bufferForPlaybackAfterRebufferDuration: Duration(seconds: 2),
          targetBufferBytes: _androidTargetBufferBytes,
        ),
      ),
    );
  }

  static Future<MyAudioHandler> create({
    required SettingsRepository settingsRepository,
    required LibraryRepository libraryRepository,
    required DownloadRepository downloadRepository,
    required SongCacheRepository songCacheRepository,
    required PlaylistRepository playlistRepository,
    required PlaybackSessionRepository playbackSessionRepository,
    required ResolverPlaybackClient resolverPlaybackClient,
  }) async {
    final handler = MyAudioHandler._(
      settingsRepository: settingsRepository,
      libraryRepository: libraryRepository,
      downloadRepository: downloadRepository,
      songCacheRepository: songCacheRepository,
      playlistRepository: playlistRepository,
      playbackSessionRepository: playbackSessionRepository,
      resolverPlaybackClient: resolverPlaybackClient,
    );
    await handler._init();
    return handler;
  }

  Future<void> _init() async {
    unawaited(_resolverPlaybackClient.warmUp());
    if (!kIsWeb) {
      await _createCacheDir();
      _preloadService = PlaybackPreloadService(
        preloadDirectory: Directory("$_cacheDir/preloadedSongs"),
        resolveStreamInfo:
            (songId, {generateNewUrl = false, offlineReplacementUrl = false}) =>
                checkNGetUrl(
                  songId,
                  generateNewUrl: generateNewUrl,
                  offlineReplacementUrl: offlineReplacementUrl,
                  allowResolver:
                      _effectiveResolverSourceMode() ==
                      ResolverSourceMode.resolverOnly,
                ),
        settingsRepository: _settingsRepository,
        songCacheRepository: _songCacheRepository,
      );
      await _preloadService!.init();
    }
    await _addEmptyList();

    _notifyAudioHandlerAboutPlaybackEvents();
    _listenToPlaybackForNextSong();
    _listenForEndPositionFallback();
    _listenForSequenceStateChanges();

    // Skip-silence is implemented by the Android player only. Calling it on
    // the browser throws before the application can render.
    if (!kIsWeb) {
      await _player.setSkipSilenceEnabled(
        _settingsRepository.getSkipSilenceEnabled(),
      );
    }

    loopModeEnabled = _settingsRepository.getLoopModeEnabled();
    shuffleModeEnabled = _settingsRepository.getShuffleModeEnabled();
    queueLoopModeEnabled = _settingsRepository.getQueueLoopModeEnabled();
    loudnessNormalizationEnabled = _settingsRepository
        .getLoudnessNormalizationEnabled();
    await _player.setLoopMode(loopModeEnabled ? LoopMode.one : LoopMode.off);

    _listenForDurationChanges();
    _listenForSessionPersistence();
    _player.positionStream.listen((position) {
      if (position > Duration.zero) {
        _activePlaybackTrace?.positivePlaybackPosition();
      }
    });

    if (RuntimePlatform.isAndroid) {
      _listenSessionIdStream();
    }
  }

  // Keeps the persisted session fresh outside of app-lifecycle events, so an
  // ungraceful process kill (e.g. OOM during a phone call) still restores the
  // actual current song and a recent position.
  void _listenForSessionPersistence() {
    // Track change (auto-advance, skip, shuffle, setSourceNPlay). A newly
    // started song begins at zero and _player.position is unreliable mid
    // source-switch, so persist position 0 explicitly.
    mediaItem.distinct((a, b) => a?.id == b?.id).listen((_) {
      if (_remoteNotificationMirrorActive) return;
      _scheduleSessionSave(positionOverride: Duration.zero);
    });

    // Any playing -> not-playing transition. A phone-call pause comes from
    // just_audio's internal interruption handler calling _player.pause()
    // directly, bypassing this handler's pause() override, so hook the player
    // stream rather than the override.
    _player.playingStream.listen((playing) {
      if (_wasPlayingForSessionSave && !playing) {
        // _player.stop() during a source switch also emits playing=false, but
        // the position would still belong to the previous song.
        if (!_sourceSwitchInProgress && !isSongLoading) {
          _scheduleSessionSave();
        }
      }
      _wasPlayingForSessionSave = playing;
      _syncPeriodicPositionSaves(playing);
    });

    // Queue mutations (reorder, play next, clear) — keeps the persisted queue
    // consistent with the index/position-only saves below.
    queue.listen((_) => _scheduleSessionSave());
  }

  void _scheduleSessionSave({Duration? positionOverride}) {
    // Never fabricate index 0 before a song was actually selected.
    if (_suppressSessionSave || currentIndex is! int) return;
    _sessionSaveDebounce?.cancel();
    _sessionSaveDebounce = Timer(const Duration(milliseconds: 800), () {
      if (_suppressSessionSave || currentIndex is! int) return;
      unawaited(saveSessionData(positionOverride: positionOverride));
    });
  }

  void _syncPeriodicPositionSaves(bool playing) {
    if (playing) {
      _periodicPositionSaveTimer ??= Timer.periodic(
        const Duration(seconds: 30),
        (_) {
          if (_suppressSessionSave ||
              currentIndex is! int ||
              !_player.playing) {
            return;
          }
          if (!_settingsRepository.getRestorePlaybackSession()) return;
          unawaited(
            _playbackSessionRepository.savePosition(
              index: currentIndex as int,
              position: _player.position.inMilliseconds,
            ),
          );
        },
      );
    } else {
      _periodicPositionSaveTimer?.cancel();
      _periodicPositionSaveTimer = null;
    }
  }

  /// Records that cached audio was used, so housekeeping ages it from last
  /// play rather than from when it was first written.
  ///
  /// LockCachingAudioSource writes the file once, so its modification time
  /// would otherwise expire a daily favourite thirty days after it was cached.
  /// Last-access time cannot stand in for this: NTFS ships with
  /// NtfsDisableLastAccessUpdate on.
  Future<void> _markCachedAudioPlayed(File file) async {
    try {
      await file.setLastModified(DateTime.now());
    } catch (_) {
      // Advisory only. A cache hit must never fail over its own bookkeeping.
    }
  }

  Future<void> _createCacheDir() async {
    _cacheDir = (await getTemporaryDirectory()).path;
    // Not under _cacheDir any more: songCacheDirectory picks a durable root,
    // because the OS empties the temporary one out from under the Songs
    // library. Preload prefixes above stay in temp, where they belong.
    _cachedSongsDir = (await songCacheDirectory()).path;
  }

  Future<void> _addEmptyList() async {
    try {
      await _player.setAudioSource(_playList);
    } catch (r) {
      printERROR(r.toString(), tag: LogTags.audioHandler);
    }
  }

  void _schedulePreloadWindow() {
    final queueSnapshot = queue.value.toList();
    final currentQueueIndex = currentIndex is int ? currentIndex as int : null;
    if (_player.playing && currentQueueIndex != null) {
      final nextIds = <String>[];
      for (var offset = 1; offset <= 3; offset++) {
        var index = currentQueueIndex + offset;
        if (queueLoopModeEnabled && queueSnapshot.isNotEmpty) {
          index %= queueSnapshot.length;
        }
        if (index < 0 || index >= queueSnapshot.length) break;
        final id = queueSnapshot[index].id;
        if (!nextIds.contains(id)) nextIds.add(id);
      }
      if (_effectiveResolverSourceMode().usesResolver) {
        unawaited(_resolverPlaybackClient.warmUp());
        unawaited(_resolverPlaybackClient.prefetch(nextIds));
      }
    }
    final preloadService = _preloadService;
    if (preloadService == null) return;
    final candidateIndices = currentQueueIndex == null
        ? <int>[]
        : _preloadCandidateIndices(preloadService.range);
    preloadService.schedule(
      queue: queueSnapshot,
      candidateIndices: candidateIndices,
      isPlaying: _player.playing,
      currentIndex: currentQueueIndex,
    );
  }

  void _clearPreloadWindow() {
    final preloadService = _preloadService;
    if (preloadService != null) {
      unawaited(preloadService.clear());
    }
  }

  List<int> _preloadCandidateIndices(int range) {
    final currentQueue = queue.value;
    if (range <= 0 || currentIndex is! int || currentQueue.isEmpty) {
      return const <int>[];
    }

    final center = currentIndex as int;
    final indices = <int>[];
    void addIndex(int index) {
      if (index < 0 ||
          index >= currentQueue.length ||
          indices.contains(index)) {
        return;
      }
      indices.add(index);
    }

    void addQueueOffset(int offset) {
      var queueIndex = center + offset;
      if (queueLoopModeEnabled) {
        queueIndex =
            ((queueIndex % currentQueue.length) + currentQueue.length) %
            currentQueue.length;
      } else if (queueIndex < 0 || queueIndex >= currentQueue.length) {
        return;
      }
      addIndex(queueIndex);
    }

    for (var distance = 1; distance <= range; distance++) {
      addQueueOffset(distance);
      addQueueOffset(-distance);
    }
    addIndex(center);
    return indices;
  }

  Future<HMStreamingData> _streamInfoForSong(
    MediaItem song, {
    bool generateNewUrl = false,
  }) {
    final preloadService = _preloadService;
    if (preloadService == null) {
      return checkNGetUrl(song.id, generateNewUrl: generateNewUrl);
    }
    return preloadService.streamInfoFor(
      song,
      generateNewUrl: generateNewUrl,
      fallback: () => checkNGetUrl(song.id, generateNewUrl: generateNewUrl),
    );
  }

  void _listenSessionIdStream() {
    _player.androidAudioSessionIdStream.listen((int? id) {
      if (id != null) {
        EqualizerService.initAudioEffect(id);
      }
    });
  }

  void _notifyAudioHandlerAboutPlaybackEvents() {
    _player.playbackEventStream.listen(
      (PlaybackEvent event) {
        // While this Android device controls a remote target, audio_service is
        // deliberately showing a notification-only mirror. Events from the
        // phone's parked local player must not overwrite that notification.
        if (_remoteNotificationMirrorActive) return;
        if (event.processingState == ProcessingState.ready) {
          _activePlaybackTrace?.playerReady();
        }
        // `stop()` is necessary while replacing the one-song source, but it
        // also emits an idle event. Android treats an idle audio_service state
        // as an instruction to tear down the media session. Keep reporting a
        // non-idle, playing state until the *new* source has actually started;
        // a delayed idle event from the old source must never dismiss the
        // lock-screen/notification controls between tracks.
        final sourceSwitchHasStarted =
            _sourceSwitchInProgress &&
            _sourceSwitchWasPlaying &&
            !isSongLoading &&
            _player.playing &&
            event.processingState == ProcessingState.ready;
        if (sourceSwitchHasStarted) {
          _endSourceSwitch();
        }
        final preservingMediaSession =
            _sourceSwitchInProgress && _sourceSwitchWasPlaying;
        final playing = preservingMediaSession ? true : _player.playing;
        final updatePosition = isSongLoading ? Duration.zero : _player.position;
        final bufferedPosition = isSongLoading
            ? Duration.zero
            : _player.bufferedPosition;
        playbackState.add(
          playbackState.value.copyWith(
            controls: [
              MediaControl.skipToPrevious,
              if (playing) MediaControl.pause else MediaControl.play,
              MediaControl.skipToNext,
            ],
            systemActions: const {MediaAction.seek},
            androidCompactActionIndices: const [0, 1, 2],
            processingState: preservingMediaSession
                ? AudioProcessingState.ready
                : isSongLoading
                ? AudioProcessingState.loading
                : const {
                    ProcessingState.idle: AudioProcessingState.idle,
                    ProcessingState.loading: AudioProcessingState.loading,
                    ProcessingState.buffering: AudioProcessingState.buffering,
                    ProcessingState.ready: AudioProcessingState.ready,
                    ProcessingState.completed: AudioProcessingState.completed,
                  }[_player.processingState]!,
            // Single source of truth for repeat is the loopModeEnabled field
            // (always written together with _player.setLoopMode) — keeps this
            // event in agreement with _emitPlaybackSnapshot.
            repeatMode: loopModeEnabled
                ? AudioServiceRepeatMode.one
                : AudioServiceRepeatMode.none,
            shuffleMode: shuffleModeEnabled
                ? AudioServiceShuffleMode.all
                : AudioServiceShuffleMode.none,
            playing: playing,
            updatePosition: updatePosition,
            bufferedPosition: bufferedPosition,
            speed: _player.speed,
            queueIndex: currentIndex,
          ),
        );

        if (RuntimePlatform.supportsPlaybackPreloading &&
            playing &&
            !_lastPreloadPlaying) {
          _lastPreloadPlaying = true;
          _schedulePreloadWindow();
        } else if (!playing) {
          _lastPreloadPlaying = false;
        }
        if (playing) {
          _startCompletionWatchdog();
        } else {
          _stopCompletionWatchdog();
        }

        if (event.processingState == ProcessingState.completed) {
          _scheduleCompletionHandling();
        }

        //print("set ${playbackState.value.queueIndex},${event.currentIndex}");
      },
      onError: (Object e, StackTrace st) async {
        if (e is PlayerException) {
          printERROR('Error code: ${e.code}', tag: LogTags.audioHandler);
          printERROR('Error message: ${e.message}', tag: LogTags.audioHandler);
        } else {
          printERROR('An error occurred: $e', tag: LogTags.audioHandler);
          Duration curPos = _player.position;
          await _player.stop();

          if (isPlayingUsingLockCachingSource &&
              e.toString().contains("Connection closed while receiving data")) {
            await _player.seek(curPos, index: 0);
            _startPlayerPlayback();
            _startCompletionWatchdog();
            return;
          }

          //Workaround when 403 error encountered
          await _recoverFromStalledSource(curPos);
        }
      },
    );
  }

  AudioProcessingState _processingStateForPlayer() {
    return const {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[_player.processingState]!;
  }

  void _emitPlaybackSnapshot({
    AudioProcessingState? processingState,
    bool? playing,
    int? errorCode,
    String? errorMessage,
  }) {
    if (_remoteNotificationMirrorActive) return;
    final isPlaying = playing ?? _player.playing;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        processingState: processingState ?? _processingStateForPlayer(),
        repeatMode: loopModeEnabled
            ? AudioServiceRepeatMode.one
            : AudioServiceRepeatMode.none,
        shuffleMode: shuffleModeEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        playing: isPlaying,
        queueIndex: currentIndex is int ? currentIndex as int : null,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        errorCode: errorCode,
        errorMessage: errorMessage,
      ),
    );
  }

  bool _forwardRemoteNotificationCommand(
    String action, [
    Map<String, Object?> payload = const {},
  ]) {
    if (!_remoteNotificationMirrorActive) return false;
    customEvent.add({
      'eventType': 'remoteNotificationCommand',
      'action': action,
      ...payload,
    });
    return true;
  }

  void _setRemoteNotificationPlaying(bool playing) {
    if (!_remoteNotificationMirrorActive) return;
    playbackState.add(
      playbackState.value.copyWith(
        playing: playing,
        processingState: AudioProcessingState.ready,
      ),
    );
  }

  void _setRemoteNotificationMirror(
    MediaItem remoteItem, {
    required bool playing,
    required bool loading,
    required Duration position,
  }) {
    if (!_remoteNotificationMirrorActive) {
      _mediaItemBeforeRemoteNotification = mediaItem.value;
      _playbackStateBeforeRemoteNotification = playbackState.value;
    }
    _remoteNotificationMirrorActive = true;

    final visibleItem = mediaItem.value;
    if (visibleItem?.id != remoteItem.id ||
        visibleItem?.title != remoteItem.title ||
        visibleItem?.artist != remoteItem.artist ||
        visibleItem?.album != remoteItem.album ||
        visibleItem?.duration != remoteItem.duration ||
        visibleItem?.artUri != remoteItem.artUri) {
      mediaItem.add(remoteItem);
    }
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: loading
            ? AudioProcessingState.buffering
            : AudioProcessingState.ready,
        playing: playing,
        updatePosition: position,
        bufferedPosition: position,
        speed: 1,
      ),
    );
  }

  void _clearRemoteNotificationMirror() {
    if (!_remoteNotificationMirrorActive) return;
    final localItem = _mediaItemBeforeRemoteNotification;
    final localState = _playbackStateBeforeRemoteNotification;
    _remoteNotificationMirrorActive = false;
    _mediaItemBeforeRemoteNotification = null;
    _playbackStateBeforeRemoteNotification = null;
    if (localItem != null) mediaItem.add(localItem);
    if (localState != null) playbackState.add(localState);
  }

  AudioProcessingState _nonLoadingProcessingState() {
    final state = _processingStateForPlayer();
    return switch (state) {
      AudioProcessingState.loading ||
      AudioProcessingState.buffering => AudioProcessingState.ready,
      _ => state,
    };
  }

  Map<String, dynamic> _handlerDebugSnapshot() {
    final playback = playbackState.value;
    final current = mediaItem.value;
    final currentQueue = queue.value;
    return {
      'mediaItem': _mediaItemDebug(current),
      'queueLength': currentQueue.length,
      'queueIndex': playback.queueIndex,
      'currentIndex': currentIndex,
      'currentIndexType': currentIndex.runtimeType.toString(),
      'playing': playback.playing,
      'processingState': playback.processingState.name,
      'playerProcessingState': _player.processingState.name,
      'playerPlaying': _player.playing,
      'playerLoopMode': _player.loopMode.name,
      'repeatMode': playback.repeatMode.name,
      'shuffleMode': playback.shuffleMode.name,
      'loopModeEnabled': loopModeEnabled,
      'queueLoopModeEnabled': queueLoopModeEnabled,
      'shuffleModeEnabled': shuffleModeEnabled,
      'isSongLoading': isSongLoading,
      'completionInProgress': _completionInProgress,
      'completionHandlingScheduled': _completionHandlingScheduled,
      'completionRetryScheduled': _completionRetryScheduled,
      'completionWatchdogActive': _completionWatchdogTimer != null,
      'earlyCompletionDetectedAt': _earlyCompletionDetectedAt
          ?.toIso8601String(),
      'earlyCompletionDelayMs': _earlyCompletionDelay?.inMilliseconds,
      'stallWatchPositionMs': _stallWatchPosition?.inMilliseconds,
      'stallWatchSince': _stallWatchSince?.toIso8601String(),
      'stallRecoveryInFlight': _stallRecoveryInFlight,
      'sourceSwitchInProgress': _sourceSwitchInProgress,
      'sourceSwitchWasPlaying': _sourceSwitchWasPlaying,
      'playbackGeneration': _playbackGeneration,
      'positionMs': _player.position.inMilliseconds,
      'durationMs': _player.duration?.inMilliseconds,
      'mediaDurationMs': current?.duration?.inMilliseconds,
      'bufferedPositionMs': _player.bufferedPosition.inMilliseconds,
      'speed': _player.speed,
      'volume': _player.volume,
      'updatePositionMs': playback.updatePosition.inMilliseconds,
      'playbackBufferedPositionMs': playback.bufferedPosition.inMilliseconds,
      'isAtEndPosition': _isAtEndPosition(),
      'playListChildren': _playList.children.length,
      'currentSongUrlState': _urlDebug(currentSongUrl),
      'isPlayingUsingLockCachingSource': isPlayingUsingLockCachingSource,
      'preEndWindowActive': _preEndWindowActive,
      'prepareNextSourceActive': _prepareNextSourceTask != null,
      'preparedForGeneration': _preparedForGeneration,
      'preparedNextIndex': _preparedNextIndex,
      'preparedNextSongId': _preparedNextSongId,
      'preloadRange': _preloadService?.range ?? 0,
      'lastPreloadPlaying': _lastPreloadPlaying,
      'queueBeforeShuffleLength': _queueBeforeShuffle?.length,
      'errorCode': playback.errorCode,
      'errorMessage': playback.errorMessage,
    };
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
      'extrasKeys': item.extras?.keys.toList(),
      'hasUrlExtra': item.extras?['url'] != null,
    };
  }

  Map<String, dynamic>? _urlDebug(String? url) {
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    return {
      'isEmpty': url.isEmpty,
      'scheme': uri?.scheme,
      'host': uri?.host,
      'pathLength': uri?.path.length,
      'queryParameterCount': uri?.queryParameters.length,
    };
  }

  void _emitSourceStartedSnapshot() {
    CrashDiagnosticsService.instance.record(
      'audio',
      'source-started song=${mediaItem.value?.id} index=$currentIndex queue=${queue.value.length}',
      includeMemory: true,
    );
    _emitPlaybackSnapshot(
      processingState: AudioProcessingState.ready,
      playing: true,
    );
  }

  void _handleSourcePlaybackFailure({
    required String actionName,
    required MediaItem song,
    required Object error,
    required StackTrace stackTrace,
  }) {
    currentSongUrl = null;
    isSongLoading = false;
    final message = error.toString();
    printERROR(
      '$actionName failed for ${song.id}: $message\n$stackTrace',
      tag: LogTags.audioHandler,
    );
    CrashDiagnosticsService.instance.record(
      'audio',
      '$actionName failed song=${song.id} index=$currentIndex queue=${queue.value.length}',
      error: error,
      stackTrace: stackTrace,
      includeMemory: true,
      flush: true,
    );
    _schedulePreloadWindow();
    customEvent.add({
      'eventType': 'playError',
      'message': message.isEmpty ? 'networkError' : message,
    });
    _emitPlaybackSnapshot(
      processingState: AudioProcessingState.error,
      playing: false,
      errorCode: 500,
      errorMessage: message,
    );
  }

  Future<HMStreamingData> _freshStreamInfoAfterSourceLoadFailure({
    required String actionName,
    required MediaItem song,
    required Object error,
    required StackTrace stackTrace,
  }) async {
    printERROR(
      '$actionName source load failed for ${song.id}; retrying with a fresh URL: $error\n$stackTrace',
      tag: LogTags.audioHandler,
    );
    CrashDiagnosticsService.instance.record(
      'audio',
      '$actionName source-load-retry song=${song.id} index=$currentIndex queue=${queue.value.length}',
      error: error,
      stackTrace: stackTrace,
      includeMemory: true,
    );
    return checkNGetUrl(song.id, generateNewUrl: true);
  }

  Future<void> _replaceCurrentSourceWithStreamInfo({
    required String actionName,
    required MediaItem song,
    required HMStreamingData streamInfo,
  }) async {
    if (!streamInfo.playable) {
      throw StateError(streamInfo.statusMSG);
    }
    currentSongUrl = song.extras!['url'] = streamInfo.audio!.url;
    printINFO(
      '$actionName retry selected audio url empty=${streamInfo.audio!.url.isEmpty}',
      tag: LogTags.audioHandler,
    );
    await _clearCurrentSourceForReplacement();
    await _playList.add(_createAudioSource(song));
  }

  Future<void> _clearCurrentSourceForReplacement() async {
    // just_audio deactivates and recreates its platform player after stop().
    // Keeping the desktop player paused preserves the WASAPI endpoint between
    // songs and avoids a short burst of invalid audio while it is reopened.
    if (RuntimePlatform.isDesktop) {
      await _player.pause();
    } else {
      await _player.stop();
    }
    await _playList.clear();
  }

  void _listenToPlaybackForNextSong() {
    _player.processingStateStream.listen((state) async {
      if (state == ProcessingState.completed) {
        _scheduleCompletionHandling();
      }
    });
  }

  void _scheduleCompletionHandling({bool allowEndPosition = false}) {
    // Repeat is owned by just_audio's native LoopMode.one. Some Android
    // backends briefly report completed while that loop is being reopened;
    // scheduling Harmony's queue/completion flow during that window can seek
    // the already-restarted song back to zero a second time.
    if (loopModeEnabled) return;
    if (allowEndPosition) {
      _completionHandlingAllowEndPosition = true;
    }
    if (_completionHandlingScheduled || _completionInProgress) return;
    _completionHandlingAllowEndPosition = allowEndPosition;
    _completionHandlingScheduled = true;
    scheduleMicrotask(() {
      _completionHandlingScheduled = false;
      final allowEndPosition = _completionHandlingAllowEndPosition;
      _completionHandlingAllowEndPosition = false;
      unawaited(_handlePlaybackCompleted(allowEndPosition: allowEndPosition));
    });
  }

  Future<void> _handlePlaybackCompleted({bool allowEndPosition = false}) async {
    if (_completionInProgress ||
        (_player.processingState != ProcessingState.completed &&
            !(allowEndPosition && _isAtEndPosition()))) {
      return;
    }
    if (isSongLoading) {
      _scheduleCompletionRetry();
      return;
    }

    _completionRetryScheduled = false;
    _completionInProgress = true;
    CrashDiagnosticsService.instance.record(
      'audio',
      'completion song=${mediaItem.value?.id} index=$currentIndex queue=${queue.value.length}',
      includeMemory: true,
      flush: true,
    );
    try {
      if (loopModeEnabled) {
        // LoopMode.one already restarts the source inside the native player.
        // Seeking here races that restart and replays the first second twice.
        return;
      }

      await skipToNext();
    } finally {
      _completionInProgress = false;
    }
  }

  void _scheduleCompletionRetry() {
    if (_completionRetryScheduled) return;
    _completionRetryScheduled = true;
    Timer(const Duration(milliseconds: 100), () {
      _completionRetryScheduled = false;
      if (_player.processingState == ProcessingState.completed) {
        unawaited(_handlePlaybackCompleted());
      }
    });
  }

  void _startCompletionWatchdog() {
    if (_completionWatchdogTimer != null) return;
    _completionWatchdogTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) {
        _checkCompletionWatchdog();
        _checkBufferingStallWatchdog();
      },
    );
  }

  void _stopCompletionWatchdog() {
    _completionWatchdogTimer?.cancel();
    _completionWatchdogTimer = null;
    _resetEarlyCompletionDeferral();
    _resetBufferingStallWatch();
  }

  void _checkCompletionWatchdog() {
    if (isSongLoading || _completionInProgress || _sourceSwitchInProgress) {
      return;
    }
    if (_player.processingState == ProcessingState.completed) {
      if (_shouldHonorCompletedStateNow()) {
        _scheduleCompletionHandling();
      }
      return;
    }
    _resetEarlyCompletionDeferral();
    if (_player.playing && _isAtEndPosition()) {
      _scheduleCompletionHandling(allowEndPosition: true);
    }
  }

  bool _shouldHonorCompletedStateNow() {
    final expectedDuration = _expectedEndDuration();
    final position = _player.position;
    if (expectedDuration == null || position >= expectedDuration) {
      _resetEarlyCompletionDeferral();
      return true;
    }

    _earlyCompletionDetectedAt ??= DateTime.now();
    _earlyCompletionDelay ??=
        expectedDuration - position + _fallbackCompletionGrace;
    return DateTime.now().difference(_earlyCompletionDetectedAt!) >=
        _earlyCompletionDelay!;
  }

  void _resetEarlyCompletionDeferral() {
    _earlyCompletionDetectedAt = null;
    _earlyCompletionDelay = null;
  }

  void _checkBufferingStallWatchdog() {
    if (isSongLoading ||
        _completionInProgress ||
        _sourceSwitchInProgress ||
        _stallRecoveryInFlight) {
      _resetBufferingStallWatch();
      return;
    }
    if (!_player.playing ||
        _player.processingState != ProcessingState.buffering) {
      _resetBufferingStallWatch();
      return;
    }

    final position = _player.position;
    final watchedPosition = _stallWatchPosition;
    if (watchedPosition == null ||
        (position - watchedPosition).abs() > _bufferingStallPositionTolerance) {
      _stallWatchPosition = position;
      _stallWatchSince = DateTime.now();
      return;
    }
    if (DateTime.now().difference(_stallWatchSince!) <
        _bufferingStallThreshold) {
      return;
    }

    _resetBufferingStallWatch();
    _stallRecoveryInFlight = true;
    printERROR(
      'Buffering stalled at ${position.inMilliseconds}ms for '
      'song=${mediaItem.value?.id}; recovering with a fresh stream URL',
      tag: LogTags.audioHandler,
    );
    CrashDiagnosticsService.instance.record(
      'audio',
      'buffering-stall-recovery song=${mediaItem.value?.id} '
          'position=${position.inMilliseconds}ms',
      includeMemory: true,
      flush: true,
    );
    unawaited(() async {
      try {
        await _recoverFromStalledSource(position);
      } catch (error, stackTrace) {
        printERROR(
          'Buffering stall recovery failed: $error\n$stackTrace',
          tag: LogTags.audioHandler,
        );
      } finally {
        _stallRecoveryInFlight = false;
      }
    }());
  }

  void _resetBufferingStallWatch() {
    _stallWatchPosition = null;
    _stallWatchSince = null;
  }

  Future<void> _recoverFromStalledSource(Duration resumePosition) async {
    await customAction("playByIndex", {'index': currentIndex, 'newUrl': true});
    await _player.seek(resumePosition, index: 0);
  }

  void _listenForEndPositionFallback() {
    _player
        .createPositionStream(
          steps: 400,
          minPeriod: const Duration(milliseconds: 100),
          maxPeriod: const Duration(milliseconds: 250),
        )
        .listen((position) {
          if (!_player.playing ||
              isSongLoading ||
              _completionInProgress ||
              _sourceSwitchInProgress) {
            return;
          }
          _prepareNextSourceWhenNearEnd(position);
          if (_isAtEndPosition(position)) {
            _scheduleCompletionHandling(allowEndPosition: true);
          }
        });
  }

  bool _isAtEndPosition([Duration? position]) {
    final duration = _expectedEndDuration();
    if (duration == null || duration.inMilliseconds <= 0) return false;

    final currentPosition = position ?? _player.position;
    return currentPosition >= duration;
  }

  Duration? _expectedEndDuration() {
    final playerDuration = _player.duration;
    final mediaDuration = mediaItem.value?.duration;
    if (playerDuration == null) return mediaDuration;
    if (mediaDuration == null) return playerDuration;
    return playerDuration > mediaDuration ? playerDuration : mediaDuration;
  }

  void _beginSourceSwitch() {
    _sourceSwitchWasPlaying = playbackState.value.playing || _player.playing;
    _sourceSwitchInProgress = true;
  }

  void _beginPlaybackStartTrace(PlaybackTransitionCategory transition) {
    _activeResolverCancellation?.cancel();
    _activeResolverCancellation = null;
    _activePlaybackTrace = PlaybackStartTrace(transition: transition);
  }

  PlaybackTransitionCategory _playbackTransition(
    Object? value, {
    PlaybackTransitionCategory fallback = PlaybackTransitionCategory.tap,
  }) {
    return switch (value) {
      'skip' => PlaybackTransitionCategory.skip,
      'queue_transition' => PlaybackTransitionCategory.queueTransition,
      'resume' => PlaybackTransitionCategory.resume,
      'tap' => PlaybackTransitionCategory.tap,
      _ => fallback,
    };
  }

  void _traceCurrentSource(PlaybackTransitionCategory transition) {
    _beginPlaybackStartTrace(transition);
    _activePlaybackTrace?.sourceSelected(_currentPlaybackSource);
    if (_player.processingState == ProcessingState.ready) {
      _activePlaybackTrace?.playerReady();
    }
  }

  void _endSourceSwitch() {
    _sourceSwitchInProgress = false;
    _sourceSwitchWasPlaying = false;
  }

  void _finishSourceSwitchAfterPlaybackRequest() {
    // A playing switch ends from the playback event listener only after the
    // replacement source is non-idle. Until then Android sees ready + playing,
    // keeping the lock-screen card stable while the internal player changes
    // source. A switch that started paused has no playing session to preserve.
    if (!_sourceSwitchWasPlaying) {
      _endSourceSwitch();
    }
  }

  void _resetPreparedNextSource() {
    _preEndWindowActive = false;
    _prepareNextSourceTask = null;
    _preparedForGeneration = null;
    _preparedNextIndex = null;
    _preparedNextSongId = null;
    _preparedNextStreamInfo = null;
    _resetEarlyCompletionDeferral();
  }

  void _prepareNextSourceWhenNearEnd(Duration position) {
    final duration = _player.duration ?? mediaItem.value?.duration;
    if (duration == null || duration.inMilliseconds <= 0) return;

    final remaining = duration - position;
    if (remaining > const Duration(seconds: 5)) {
      if (_preEndWindowActive) {
        _resetPreparedNextSource();
      }
      return;
    }
    if (remaining <= Duration.zero || _preEndWindowActive) return;

    _preEndWindowActive = true;
    _startPreparingNextSource();
  }

  void _startPreparingNextSource() {
    if (_prepareNextSourceTask != null ||
        currentIndex is! int ||
        queue.value.isEmpty) {
      return;
    }

    final nextIndex = _getNextSongIndex();
    if (nextIndex == currentIndex && !queueLoopModeEnabled) return;
    if (nextIndex < 0 || nextIndex >= queue.value.length) return;

    final generation = _playbackGeneration;
    final song = queue.value[nextIndex];
    final task = _sourceInfoForPlayback(song, allowPrepared: false);
    _prepareNextSourceTask = task
        .then((streamInfo) {
          if (generation != _playbackGeneration ||
              nextIndex < 0 ||
              nextIndex >= queue.value.length ||
              queue.value[nextIndex].id != song.id) {
            return;
          }
          if (!streamInfo.playable) return;
          _preparedForGeneration = generation;
          _preparedNextIndex = nextIndex;
          _preparedNextSongId = song.id;
          _preparedNextStreamInfo = streamInfo;
        })
        .whenComplete(() {
          if (identical(_prepareNextSourceTask, task)) {
            _prepareNextSourceTask = null;
          }
        });
    unawaited(_prepareNextSourceTask);
  }

  HMStreamingData? _takePreparedStreamInfoFor(int index, String songId) {
    if (_preparedForGeneration != _playbackGeneration ||
        _preparedNextIndex != index ||
        _preparedNextSongId != songId) {
      return null;
    }
    final streamInfo = _preparedNextStreamInfo;
    _resetPreparedNextSource();
    return streamInfo;
  }

  Future<HMStreamingData> _sourceInfoForPlayback(
    MediaItem song, {
    bool generateNewUrl = false,
    bool allowPrepared = true,
    HMStreamingData? preparedStreamInfo,
  }) async {
    if (!generateNewUrl && allowPrepared && preparedStreamInfo != null) {
      return preparedStreamInfo;
    }
    if (!generateNewUrl) {
      final offlineStreamInfo = await _offlineStreamInfoForSong(song);
      if (offlineStreamInfo != null) return offlineStreamInfo;
    }
    return _streamInfoForSong(song, generateNewUrl: generateNewUrl);
  }

  Future<HMStreamingData?> _offlineStreamInfoForSong(MediaItem song) async {
    final downloaded = await _downloadedStreamInfoForSong(song.id);
    if (downloaded != null) return downloaded;

    final cached = await _cachedStreamInfoForSong(song.id);
    if (cached != null) return cached;

    final url = song.extras?['url'];
    if (url is String &&
        _isLocalSourceUrl(url) &&
        await _localSourceFileExists(url)) {
      return _streamInfoFromLocalUrl(song, url);
    }
    return null;
  }

  /// A persisted MediaItem can carry a local path that no longer exists —
  /// e.g. a backup restored from another package/device still points into
  /// that app's private storage. Playing it blind makes ExoPlayer fail with
  /// ENOENT; returning null here lets resolution fall through to streaming.
  Future<bool> _localSourceFileExists(String url) async {
    try {
      final uri = Uri.tryParse(url);
      final path = uri != null && uri.scheme == 'file' ? uri.toFilePath() : url;
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }

  Future<HMStreamingData?> _cachedStreamInfoForSong(String songId) async {
    if (!await _songCacheRepository.containsCachedSong(songId)) return null;
    // Same trap as checkNGetUrl: a cache entry can outlive the file it points
    // at, and preloading a missing file stalls the player instead of failing.
    final cachedFile = File("$_cachedSongsDir/$songId.mp3");
    if (!await cachedFile.exists()) return null;
    await _markCachedAudioPlayed(cachedFile);

    final cachedSongJson = await _songCacheRepository.getCachedSongJson(songId);
    final streamInfo = cachedSongJson?["streamInfo"];
    Audio audio;
    if (streamInfo != null && streamInfo.isNotEmpty) {
      streamInfo[1]['url'] = "file://$_cachedSongsDir/$songId.mp3";
      audio = Audio.fromJson(streamInfo[1]);
    } else {
      audio = Audio(
        audioCodec: Codec.mp4a,
        bitrate: 0,
        loudnessDb: 0,
        duration: 0,
        size: 0,
        url: "file://$_cachedSongsDir/$songId.mp3",
        itag: 0,
      );
    }
    return HMStreamingData(
      playable: true,
      statusMSG: "OK",
      lowQualityAudio: audio,
      highQualityAudio: audio,
    );
  }

  Future<HMStreamingData?> _downloadedStreamInfoForSong(String songId) async {
    if (!await _downloadRepository.containsDownload(songId)) return null;

    final song = await _downloadRepository.getDownloadJson(songId);
    if (song == null) return null;

    final path = song['url'];
    if (path is! String || path.isEmpty) return null;

    final supportMusicPath =
        "${(await getApplicationSupportDirectory()).path}/Music";
    final isInSupportDir = path.contains(supportMusicPath);
    final hasExternalAccess = await PermissionService.getExtStoragePermission();
    // Being inside our own directory does not exempt the file from having to
    // exist — same trap as checkNGetUrl, and preloading a missing file stalls
    // the player instead of failing.
    final reachable = isInSupportDir
        ? await _localSourceFileExists(path)
        : hasExternalAccess && await File(path).exists();
    if (!reachable) {
      return null;
    }

    final streamInfoJson = song["streamInfo"];
    Audio audio;
    if (streamInfoJson is List &&
        streamInfoJson.length > 1 &&
        streamInfoJson[1] is Map) {
      final audioJson = Map<String, dynamic>.from(streamInfoJson[1] as Map);
      audioJson['url'] = path;
      audio = Audio.fromJson(audioJson);
    } else {
      audio = Audio(
        itag: 140,
        audioCodec: Codec.mp4a,
        bitrate: 0,
        duration: 0,
        loudnessDb: 0,
        url: path,
        size: 0,
      );
    }
    return HMStreamingData(
      playable: true,
      statusMSG: "OK",
      highQualityAudio: audio,
      lowQualityAudio: audio,
    );
  }

  bool _isLocalSourceUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (uri.scheme == 'file') return true;
    if (uri.scheme == 'http' || uri.scheme == 'https') return false;
    return url.startsWith('/') || url.contains('/cache');
  }

  HMStreamingData _streamInfoFromLocalUrl(MediaItem song, String url) {
    final audio = Audio(
      itag: 140,
      audioCodec: Codec.mp4a,
      bitrate: 0,
      duration: song.duration?.inMilliseconds ?? 0,
      loudnessDb: 0,
      url: url,
      size: 0,
    );
    return HMStreamingData(
      playable: true,
      statusMSG: "OK",
      highQualityAudio: audio,
      lowQualityAudio: audio,
    );
  }

  Future<void> _loadCurrentSourceFromStartAndPlay({
    Duration startPosition = Duration.zero,
  }) async {
    await _player.load();
    _activePlaybackTrace?.playerReady();
    await _player.seek(startPosition, index: 0);
    _startPlayerPlayback();
    _startCompletionWatchdog();
  }

  void _startPlayerPlayback() {
    unawaited(
      _player.play().catchError((Object error, StackTrace stackTrace) {
        printERROR(error, tag: LogTags.audioHandler);
        printERROR(stackTrace, tag: LogTags.audioHandler);
      }),
    );
  }

  void _listenForSequenceStateChanges() {
    _player.sequenceStateStream.listen((SequenceState? sequenceState) {
      final sequence = sequenceState?.effectiveSequence;
      if (sequence == null || sequence.isEmpty) return;
    });
  }

  void _listenForDurationChanges() {
    _player.durationStream.listen((duration) async {
      final currQueue = queue.value;
      if (currentIndex == null || currQueue.isEmpty || duration == null) return;
      final currentSong = queue.value[currentIndex];
      if (currentSong.duration == null || currentIndex == 0) {
        final newMediaItem = currentSong.copyWith(duration: duration);
        mediaItem.add(newMediaItem);
      }
    });
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    _queueBeforeShuffle?.addAll(mediaItems);
    // notify system
    final newQueue = queue.value..addAll(mediaItems);
    queue.add(newQueue);
    _schedulePreloadWindow();
  }

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    final currentSongId = mediaItem.value?.id;
    if (shuffleModeEnabled) {
      _queueBeforeShuffle = List<MediaItem>.from(queue);
    } else {
      _queueBeforeShuffle = null;
    }
    final newQueue = this.queue.value
      ..replaceRange(0, this.queue.value.length, queue);
    this.queue.add(newQueue);
    if (currentSongId != null) {
      final nextIndex = newQueue.indexWhere((item) => item.id == currentSongId);
      if (nextIndex >= 0) {
        currentIndex = nextIndex;
      } else if (newQueue.isNotEmpty) {
        final oldIndex = currentIndex is int ? currentIndex as int : 0;
        currentIndex = oldIndex.clamp(0, newQueue.length - 1).toInt();
      }
    }
    _schedulePreloadWindow();
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    _queueBeforeShuffle?.add(mediaItem);
    // notify system
    final newQueue = queue.value..add(mediaItem);
    queue.add(newQueue);
    _schedulePreloadWindow();
  }

  AudioSource _createAudioSource(MediaItem mediaItem) {
    final url = mediaItem.extras!['url'] as String;
    if (url.startsWith('resolver://')) {
      final source = _resolverSources.remove(mediaItem.id);
      if (source != null) {
        isPlayingUsingLockCachingSource = false;
        _currentPlaybackSource = PlaybackSourceCategory.resolver;
        _activePlaybackTrace?.sourceSelected(_currentPlaybackSource);
        _activePlaybackTrace?.responseHeaders(source: _currentPlaybackSource);
        _activePlaybackTrace?.firstEncodedByte(source: _currentPlaybackSource);
        return source.withTag(mediaItem);
      }
      // A miss is reachable: _resetResolverSources() clears the whole map and
      // runs at the top of both resolver entry points, including from the
      // preload path, so preparing the next song can drop a source this one
      // has not consumed yet.
      //
      // Deliberately falls through rather than throwing. This method is
      // synchronous, so it cannot re-resolve here, and it is called *outside*
      // the try that wraps _loadCurrentSourceFromStartAndPlay — the one whose
      // catch fetches a fresh URL. Throwing therefore skips the recovery and
      // lands in the outer handler, stopping the player outright. Falling
      // through lets the load fail where the retry can see it, which recovers
      // and plays. Logged because the miss itself is worth knowing about.
      printWarning(
        'Resolver source for ${mediaItem.id} was gone before playback; '
        'falling through so the load retry can re-resolve it',
        tag: LogTags.audioHandler,
      );
    }
    final cacheSongsEnabled = _settingsRepository.getCacheSongs();
    final trace = _activePlaybackTrace;
    final preloadedSource = _preloadService?.createAudioSource(
      mediaItem,
      cacheSongsEnabled: cacheSongsEnabled,
      onResponseReady: () =>
          trace?.responseHeaders(source: PlaybackSourceCategory.preloaded),
      onFirstEncodedByte: () =>
          trace?.firstEncodedByte(source: PlaybackSourceCategory.preloaded),
    );
    if (preloadedSource != null) {
      isPlayingUsingLockCachingSource = false;
      _currentPlaybackSource = PlaybackSourceCategory.preloaded;
      trace?.sourceSelected(_currentPlaybackSource);
      return preloadedSource;
    }

    if (url.contains('/cache') || (cacheSongsEnabled && url.contains("http"))) {
      printINFO("Playing Using LockCaching", tag: LogTags.audioHandler);
      isPlayingUsingLockCachingSource = true;
      _currentPlaybackSource = PlaybackSourceCategory.lockCaching;
      trace?.sourceSelected(_currentPlaybackSource);
      // ignore: experimental_member_use
      return LockCachingAudioSource(
        _playableUri(url),
        cacheFile: File("$_cachedSongsDir/${mediaItem.id}.mp3"),
        tag: mediaItem,
      );
    }

    printINFO("Playing Using AudioSource.uri", tag: LogTags.audioHandler);
    isPlayingUsingLockCachingSource = false;
    _currentPlaybackSource =
        _isLocalSourceUrl(url) || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(url)
        ? PlaybackSourceCategory.local
        : PlaybackSourceCategory.network;
    trace?.sourceSelected(_currentPlaybackSource);
    return AudioSource.uri(_playableUri(url), tag: mediaItem);
  }

  /// Local file paths can contain '#' or '?' from song titles; Uri.parse
  /// treats those as fragment/query separators and truncates the path, so
  /// build file URIs with Uri.file instead.
  Uri _playableUri(String url) {
    if (url.startsWith('file://')) {
      return Uri.file(url.substring('file://'.length));
    }
    if (_isLocalSourceUrl(url) || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(url)) {
      return Uri.file(url);
    }
    return Uri.parse(url);
  }

  @override
  // ignore: avoid_renaming_method_parameters
  Future<void> removeQueueItem(MediaItem mediaItem_) async {
    _queueBeforeShuffle?.removeWhere((item) => item.id == mediaItem_.id);
    final currentQueue = queue.value;
    final currentSong = mediaItem.value;
    final itemIndex = currentQueue.indexOf(mediaItem_);
    if (currentIndex > itemIndex) {
      currentIndex -= 1;
    }
    currentQueue.remove(mediaItem_);
    queue.add(currentQueue);
    mediaItem.add(currentSong);
    _schedulePreloadWindow();
  }

  @override
  Future<void> play() async {
    if (_forwardRemoteNotificationCommand('play')) {
      _setRemoteNotificationPlaying(true);
      return;
    }
    if (currentSongUrl == null ||
        (RuntimePlatform.isDesktop &&
            (_player.duration == null ||
                _player.duration?.inMilliseconds == 0))) {
      await customAction("playByIndex", {
        'index': currentIndex,
        'transition': 'tap',
      });
      return;
    }
    // Workaround for network error pause in case of PlayingUsingLockCachingSource
    // if (isPlayingUsingLockCachingSource && networkErrorPause) {
    //   await _player.play();
    //   Future.delayed(const Duration(seconds: 2)).then((value) {
    //     if (_player.playing) {
    //       networkErrorPause = false;
    //     }
    //   });
    //   await _player.play();
    //   return;
    // }
    _traceCurrentSource(PlaybackTransitionCategory.resume);
    _startPlayerPlayback();
    _startCompletionWatchdog();
    _schedulePreloadWindow();
  }

  @override
  Future<void> pause() async {
    if (_forwardRemoteNotificationCommand('pause')) {
      _setRemoteNotificationPlaying(false);
      return;
    }
    await _player.pause();
    isSongLoading = false;
    CrashDiagnosticsService.instance.record(
      'audio',
      'pause position=${_player.position.inMilliseconds}ms song=${mediaItem.value?.id}',
      includeMemory: true,
    );
    _emitPlaybackSnapshot(
      processingState: _nonLoadingProcessingState(),
      playing: false,
    );
    _clearPreloadWindow();
    _stopCompletionWatchdog();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_forwardRemoteNotificationCommand('seek', {
      'positionMs': position.inMilliseconds,
    })) {
      playbackState.add(
        playbackState.value.copyWith(
          updatePosition: position,
          bufferedPosition: position,
        ),
      );
      return;
    }
    _previousRestartedAt = null;
    await _player.seek(position);
    Timer(const Duration(milliseconds: 400), () {
      if (_player.playing && _isAtEndPosition()) {
        _scheduleCompletionHandling(allowEndPosition: true);
      }
    });
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= queue.value.length) return;
    await customAction("playByIndex", {'index': index, 'transition': 'skip'});
  }

  int _getNextSongIndex() {
    if (queue.value.length > currentIndex + 1) {
      return currentIndex + 1;
    } else if (queueLoopModeEnabled) {
      return 0;
    } else {
      return currentIndex;
    }
  }

  int _getPrevSongIndex() {
    if (currentIndex - 1 >= 0) {
      return currentIndex - 1;
    } else if (queueLoopModeEnabled && queue.value.isNotEmpty) {
      return queue.value.length - 1;
    } else {
      return currentIndex;
    }
  }

  @override
  Future<void> skipToNext() async {
    if (_forwardRemoteNotificationCommand('next')) return;
    final index = _getNextSongIndex();
    if (index != currentIndex) {
      printINFO(
        "Completion advancing from $currentIndex to $index",
        tag: LogTags.audioHandler,
      );
      await customAction("playByIndex", {
        'index': index,
        'transition': _completionInProgress ? 'queue_transition' : 'skip',
      });
    } else if (queueLoopModeEnabled) {
      printINFO(
        "Completion restarting current queue item because queue loop is enabled",
        tag: LogTags.audioHandler,
      );
      _beginPlaybackStartTrace(
        _completionInProgress
            ? PlaybackTransitionCategory.queueTransition
            : PlaybackTransitionCategory.skip,
      );
      _activePlaybackTrace?.sourceSelected(_currentPlaybackSource);
      await _player.seek(Duration.zero);
      _activePlaybackTrace?.playerReady();
      _startPlayerPlayback();
      _startCompletionWatchdog();
    } else {
      printINFO(
        "Completion reached queue end; pausing at start of current item",
        tag: LogTags.audioHandler,
      );
      await _player.seek(Duration.zero);
      await pause();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_forwardRemoteNotificationCommand('previous')) return;
    final restartedAt = _previousRestartedAt;
    final decisionPosition =
        restartedAt != null &&
            DateTime.now().difference(restartedAt) <=
                previousTrackRestartThreshold
        ? (_player.playing
              ? DateTime.now().difference(restartedAt)
              : Duration.zero)
        : _player.position;
    if (shouldRestartCurrentTrack(decisionPosition)) {
      _beginPlaybackStartTrace(PlaybackTransitionCategory.skip);
      _activePlaybackTrace?.sourceSelected(_currentPlaybackSource);
      await _player.seek(Duration.zero);
      // media_kit can briefly continue reporting its pre-seek position on
      // Windows. Remember the restart so another press uses the position the
      // user actually sees and can select the preceding queue item.
      _previousRestartedAt = DateTime.now();
      _activePlaybackTrace?.playerReady();
      return;
    }
    _previousRestartedAt = null;
    final index = _getPrevSongIndex();
    if (index != currentIndex) {
      await customAction("playByIndex", {'index': index, 'transition': 'skip'});
      return;
    }
    _beginPlaybackStartTrace(PlaybackTransitionCategory.skip);
    _activePlaybackTrace?.sourceSelected(_currentPlaybackSource);
    await _player.seek(Duration.zero);
    _activePlaybackTrace?.playerReady();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final enabled = repeatMode != AudioServiceRepeatMode.none;
    if (enabled != loopModeEnabled) {
      // A *change* arriving here first is typically an external controller —
      // e.g. Ford SYNC replays its stored repeat state over AVRCP on connect.
      printINFO(
        'setRepeatMode -> $repeatMode (media session / external controller)',
        tag: LogTags.audioHandler,
      );
    }
    loopModeEnabled = enabled;
    await _player.setLoopMode(enabled ? LoopMode.one : LoopMode.off);
    // Intentionally no settings write: external repeat commands (car/BT AVRCP
    // replays) must not overwrite the user's chosen default. In-app toggles
    // persist separately via PlaybackCommandService.toggleLoop.
    // Broadcast so UI observers (PlayerController) see the new repeatMode —
    // _player.setLoopMode alone produces no playbackEventStream event.
    _emitPlaybackSnapshot();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    if (shuffleMode == AudioServiceShuffleMode.none) {
      _restoreQueueBeforeShuffle();
      shuffleModeEnabled = false;
    } else {
      shuffleModeEnabled = true;
      _shuffleVisibleQueueFromIndex(currentIndex is int ? currentIndex : 0);
    }
    _emitPlaybackSnapshot();
    _schedulePreloadWindow();
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    switch (name) {
      case 'playbackDebugSnapshot':
        return _handlerDebugSnapshot();

      case 'setRemoteNotificationMirror':
        final remoteItem = extras?['mediaItem'];
        if (remoteItem is! MediaItem) {
          throw const FormatException(
            'Remote notification mirror requires a MediaItem',
          );
        }
        _setRemoteNotificationMirror(
          remoteItem,
          playing: extras?['playing'] == true,
          loading: extras?['loading'] == true,
          position: Duration(
            milliseconds: (extras?['positionMs'] as num?)?.toInt() ?? 0,
          ),
        );
        break;

      case 'setShuffleModePreservingQueue':
        final enabled = extras?['enabled'] == true;
        shuffleModeEnabled = enabled;
        _queueBeforeShuffle = enabled
            ? List<MediaItem>.from(queue.value)
            : null;
        _emitPlaybackSnapshot();
        _schedulePreloadWindow();
        break;

      case 'clearRemoteNotificationMirror':
        _clearRemoteNotificationMirror();
        break;
      case 'resolveHeosStreamUrl':
        final song = extras!['mediaItem'] as MediaItem;
        final generateNewUrl = extras['newUrl'] == true;
        final streamInfo = await checkNGetUrl(
          song.id,
          generateNewUrl: generateNewUrl,
        );
        if (!streamInfo.playable) {
          return {'playable': false, 'statusMSG': streamInfo.statusMSG};
        }
        final audio = _heosCompatibleAudio(streamInfo);
        return {
          'playable': audio != null,
          'statusMSG': audio == null ? 'No HEOS-compatible stream' : 'OK',
          'url': audio?.url,
          'audioCodec': audio?.audioCodec.name,
        };

      case 'dispose':
        _activeResolverCancellation?.cancel();
        _activeResolverCancellation = null;
        _stopCompletionWatchdog();
        _sessionSaveDebounce?.cancel();
        _periodicPositionSaveTimer?.cancel();
        _periodicPositionSaveTimer = null;
        await _preloadService?.clear();
        await _player.dispose();
        await _resetResolverSources();
        _resolverPlaybackClient.dispose();
        await super.stop();
        break;

      case 'warmResolverConnection':
        unawaited(_resolverPlaybackClient.warmUp());
        break;

      case 'playByIndex':
        final songIndex = extras!['index'];
        final requestedPositionMs = ((extras['position'] as num?)?.toInt() ?? 0)
            .clamp(0, 1 << 53)
            .toInt();
        final requestedPosition = Duration(milliseconds: requestedPositionMs);
        _beginPlaybackStartTrace(_playbackTransition(extras['transition']));
        currentIndex = songIndex;
        final isNewUrlReq = extras['newUrl'] ?? false;
        final currentSong = queue.value[currentIndex];
        final bool restoreSession = extras['restoreSession'] ?? false;
        if (restoreSession) _suppressSessionSave = true;
        final hadExistingSource = _playList.children.isNotEmpty;
        final preparedStreamInfo = !isNewUrlReq
            ? _takePreparedStreamInfoFor(songIndex, currentSong.id)
            : null;
        final requestGeneration = ++_playbackGeneration;
        _resetPreparedNextSource();
        try {
          if (hadExistingSource) {
            _beginSourceSwitch();
          }
          isSongLoading = true;
          mediaItem.add(currentSong);
          playbackState.add(
            playbackState.value.copyWith(
              processingState: AudioProcessingState.loading,
              playing: _sourceSwitchWasPlaying || playbackState.value.playing,
              queueIndex: currentIndex,
              updatePosition: Duration.zero,
              bufferedPosition: Duration.zero,
            ),
          );
          printINFO(
            'playByIndex resolving stream info for ${currentSong.id}',
            tag: LogTags.audioHandler,
          );
          final futureStreamInfo = _sourceInfoForPlayback(
            currentSong,
            generateNewUrl: isNewUrlReq,
            preparedStreamInfo: preparedStreamInfo,
          );
          if (_playList.children.isNotEmpty) {
            await _clearCurrentSourceForReplacement();
          }

          var streamInfo = await futureStreamInfo.timeout(
            _sourceResolveTimeout,
          );
          if (requestGeneration != _playbackGeneration ||
              songIndex != currentIndex) {
            isSongLoading = false;
            _endSourceSwitch();
            return;
          }
          if (!streamInfo.playable && !isNewUrlReq) {
            streamInfo = await checkNGetUrl(
              currentSong.id,
              generateNewUrl: true,
            ).timeout(_sourceResolveTimeout);
            if (requestGeneration != _playbackGeneration ||
                songIndex != currentIndex) {
              isSongLoading = false;
              _endSourceSwitch();
              return;
            }
          }
          if (!streamInfo.playable) {
            currentSongUrl = null;
            isSongLoading = false;
            _endSourceSwitch();
            _schedulePreloadWindow();
            customEvent.add({
              'eventType': 'playError',
              'message': streamInfo.statusMSG,
            });
            playbackState.add(
              playbackState.value.copyWith(
                processingState: AudioProcessingState.error,
                errorCode: 404,
                errorMessage: streamInfo.statusMSG,
              ),
            );
            return;
          }
          currentSongUrl = currentSong.extras!['url'] = streamInfo.audio!.url;
          printINFO(
            'playByIndex selected audio url empty=${streamInfo.audio!.url.isEmpty}',
            tag: LogTags.audioHandler,
          );
          playbackState.add(
            playbackState.value.copyWith(queueIndex: currentIndex),
          );
          printINFO(
            'playByIndex adding audio source for ${currentSong.id}',
            tag: LogTags.audioHandler,
          );
          await _playList.add(_createAudioSource(currentSong));

          if (loudnessNormalizationEnabled && RuntimePlatform.isAndroid) {
            await _normalizeVolume(streamInfo.audio!.loudnessDb);
          }

          if (restoreSession) {
            if (!RuntimePlatform.isDesktop) {
              final position = extras['position'];
              try {
                await _player.load();
              } catch (error, stackTrace) {
                if (isNewUrlReq) rethrow;
                final retryStreamInfo =
                    await _freshStreamInfoAfterSourceLoadFailure(
                      actionName: 'playByIndex(restore)',
                      song: currentSong,
                      error: error,
                      stackTrace: stackTrace,
                    );
                if (requestGeneration != _playbackGeneration ||
                    songIndex != currentIndex) {
                  isSongLoading = false;
                  _endSourceSwitch();
                  return;
                }
                await _replaceCurrentSourceWithStreamInfo(
                  actionName: 'playByIndex(restore)',
                  song: currentSong,
                  streamInfo: retryStreamInfo,
                );
                if (loudnessNormalizationEnabled && RuntimePlatform.isAndroid) {
                  await _normalizeVolume(retryStreamInfo.audio!.loudnessDb);
                }
                await _player.load();
              }
              _activePlaybackTrace?.playerReady();
              await _player.seek(Duration(milliseconds: position));
              await _player.seek(Duration(milliseconds: position));
            }
            isSongLoading = false;
            _emitPlaybackSnapshot(processingState: AudioProcessingState.ready);
            _endSourceSwitch();
          } else {
            printINFO('playByIndex seek and play', tag: LogTags.audioHandler);
            try {
              await _loadCurrentSourceFromStartAndPlay(
                startPosition: requestedPosition,
              );
            } catch (error, stackTrace) {
              if (isNewUrlReq) rethrow;
              final retryStreamInfo =
                  await _freshStreamInfoAfterSourceLoadFailure(
                    actionName: 'playByIndex',
                    song: currentSong,
                    error: error,
                    stackTrace: stackTrace,
                  );
              if (requestGeneration != _playbackGeneration ||
                  songIndex != currentIndex) {
                isSongLoading = false;
                _endSourceSwitch();
                return;
              }
              await _replaceCurrentSourceWithStreamInfo(
                actionName: 'playByIndex',
                song: currentSong,
                streamInfo: retryStreamInfo,
              );
              if (loudnessNormalizationEnabled && RuntimePlatform.isAndroid) {
                await _normalizeVolume(retryStreamInfo.audio!.loudnessDb);
              }
              await _loadCurrentSourceFromStartAndPlay(
                startPosition: requestedPosition,
              );
            }
            isSongLoading = false;
            _emitSourceStartedSnapshot();
            _finishSourceSwitchAfterPlaybackRequest();
            _schedulePreloadWindow();
          }
        } catch (error, stackTrace) {
          _endSourceSwitch();
          _handleSourcePlaybackFailure(
            actionName: 'playByIndex',
            song: currentSong,
            error: error,
            stackTrace: stackTrace,
          );
        } finally {
          if (restoreSession) _suppressSessionSave = false;
        }
        break;

      case 'checkWithCacheDb':
        if (isPlayingUsingLockCachingSource) {
          final song = extras!['mediaItem'] as MediaItem;
          if (!await _songCacheRepository.containsCachedSong(song.id) &&
              await File("$_cachedSongsDir/${song.id}.mp3").exists()) {
            song.extras!['url'] = currentSongUrl;
            song.extras!['date'] = DateTime.now().millisecondsSinceEpoch;
            final dbStreamData = await _songCacheRepository.getStreamCacheEntry(
              song.id,
            );
            final jsonData = MediaItemBuilder.toJson(song);
            jsonData['duration'] = _player.duration!.inSeconds;
            // playability status and info
            jsonData['streamInfo'] = dbStreamData != null
                ? [
                    true,
                    dbStreamData[_settingsRepository
                                .getStreamingQualityIndex() ==
                            0
                        ? 'lowQualityAudio'
                        : "highQualityAudio"],
                  ]
                : null;
            await _songCacheRepository.saveCachedSongJson(song.id, jsonData);
            LibrarySongsControllerRegistry.current?.addSongToLibraryList(song);
          }
        }
        break;

      case 'setSourceNPlay':
        final currMed = extras!['mediaItem'] as MediaItem;
        _beginPlaybackStartTrace(PlaybackTransitionCategory.tap);
        final requestGeneration = ++_playbackGeneration;
        _resetPreparedNextSource();
        try {
          if (_playList.children.isNotEmpty) {
            _beginSourceSwitch();
          }
          isSongLoading = true;
          currentIndex = 0;
          mediaItem.add(currMed);
          queue.add([currMed]);
          playbackState.add(
            playbackState.value.copyWith(
              processingState: AudioProcessingState.loading,
              playing: _sourceSwitchWasPlaying || playbackState.value.playing,
              queueIndex: currentIndex,
              updatePosition: Duration.zero,
              bufferedPosition: Duration.zero,
            ),
          );
          printINFO(
            'setSourceNPlay resolving stream info for ${currMed.id}',
            tag: LogTags.audioHandler,
          );
          final futureStreamInfo = _sourceInfoForPlayback(currMed);
          await _clearCurrentSourceForReplacement();
          var streamInfo = await futureStreamInfo.timeout(
            _sourceResolveTimeout,
          );
          if (requestGeneration != _playbackGeneration) {
            isSongLoading = false;
            _endSourceSwitch();
            return;
          }
          if (!streamInfo.playable) {
            streamInfo = await checkNGetUrl(
              currMed.id,
              generateNewUrl: true,
            ).timeout(_sourceResolveTimeout);
          }
          if (!streamInfo.playable) {
            currentSongUrl = null;
            isSongLoading = false;
            _endSourceSwitch();
            _schedulePreloadWindow();
            customEvent.add({
              'eventType': 'playError',
              'message': streamInfo.statusMSG,
            });
            playbackState.add(
              playbackState.value.copyWith(
                processingState: AudioProcessingState.error,
                errorCode: 404,
                errorMessage: streamInfo.statusMSG,
              ),
            );
            return;
          }
          currentSongUrl = currMed.extras!['url'] = streamInfo.audio!.url;
          printINFO(
            'setSourceNPlay selected audio url empty=${streamInfo.audio!.url.isEmpty}',
            tag: LogTags.audioHandler,
          );

          printINFO(
            'setSourceNPlay adding audio source for ${currMed.id}',
            tag: LogTags.audioHandler,
          );
          await _playList.add(_createAudioSource(currMed));

          // Normalize audio
          if (loudnessNormalizationEnabled && RuntimePlatform.isAndroid) {
            await _normalizeVolume(streamInfo.audio!.loudnessDb);
          }

          printINFO('setSourceNPlay seek and play', tag: LogTags.audioHandler);
          try {
            await _loadCurrentSourceFromStartAndPlay();
          } catch (error, stackTrace) {
            final retryStreamInfo =
                await _freshStreamInfoAfterSourceLoadFailure(
                  actionName: 'setSourceNPlay',
                  song: currMed,
                  error: error,
                  stackTrace: stackTrace,
                );
            if (requestGeneration != _playbackGeneration) {
              isSongLoading = false;
              _endSourceSwitch();
              return;
            }
            await _replaceCurrentSourceWithStreamInfo(
              actionName: 'setSourceNPlay',
              song: currMed,
              streamInfo: retryStreamInfo,
            );
            if (loudnessNormalizationEnabled && RuntimePlatform.isAndroid) {
              await _normalizeVolume(retryStreamInfo.audio!.loudnessDb);
            }
            await _loadCurrentSourceFromStartAndPlay();
          }
          isSongLoading = false;
          _emitSourceStartedSnapshot();
          _finishSourceSwitchAfterPlaybackRequest();
          _schedulePreloadWindow();
        } catch (error, stackTrace) {
          _endSourceSwitch();
          _handleSourcePlaybackFailure(
            actionName: 'setSourceNPlay',
            song: currMed,
            error: error,
            stackTrace: stackTrace,
          );
        }
        break;

      case 'toggleSkipSilence':
        final enable = extras!['enable'] as bool;
        await _player.setSkipSilenceEnabled(enable);
        break;

      case 'toggleLoudnessNormalization':
        loudnessNormalizationEnabled = extras!['enable'] as bool;
        if (!loudnessNormalizationEnabled) {
          await _player.setVolume(1.0);
          return;
        }

        if (loudnessNormalizationEnabled) {
          try {
            final currentSongId = queue.value[currentIndex].id;
            final songJson = await _songCacheRepository.getStreamCacheEntry(
              currentSongId,
            );
            if (songJson != null) {
              await _normalizeVolume(
                songJson["highQualityAudio"]["loudnessDb"],
              );
              return;
            }

            if (await _downloadRepository.containsDownload(currentSongId)) {
              final streamInfo = (await _downloadRepository.getDownloadJson(
                currentSongId,
              ))["streamInfo"];

              await _normalizeVolume(
                streamInfo == null ? 0 : streamInfo[1]["loudnessDb"],
              );
            }
          } catch (e) {
            printERROR(e, tag: LogTags.audioHandler);
          }
        }
        break;

      case 'shuffleQueue':
        final currentQueue = queue.value;
        final currentItem = currentQueue[currentIndex];
        currentQueue.remove(currentItem);
        currentQueue.shuffle();
        currentQueue.insert(0, currentItem);
        queue.add(currentQueue);
        mediaItem.add(currentItem);
        currentIndex = 0;
        _schedulePreloadWindow();
        break;

      case 'reorderQueue':
        final oldIndex = extras!['oldIndex'];
        int newIndex = extras['newIndex'];

        if (oldIndex < newIndex) {
          newIndex--;
        }

        final currentQueue = queue.value;
        final currentItem = currentQueue[currentIndex];
        final item = currentQueue.removeAt(oldIndex);
        currentQueue.insert(newIndex, item);
        currentIndex = currentQueue.indexOf(currentItem);
        queue.add(currentQueue);
        mediaItem.add(currentItem);
        _schedulePreloadWindow();
        break;

      case 'addPlayNextItem':
        final song = extras!['mediaItem'] as MediaItem;
        final currentQueue = queue.value;
        currentQueue.insert(currentIndex + 1, song);
        queue.add(currentQueue);
        _queueBeforeShuffle?.add(song);
        _schedulePreloadWindow();
        break;

      case 'openEqualizer':
        EqualizerService.openEqualizer(_player.androidAudioSessionId!);
        break;

      case 'saveSession':
        await saveSessionData();
        break;

      case 'setVolume':
        await _player.setVolume(extras!['value'] / 100);
        break;

      case 'shuffleCmd':
        final songIndex = extras!['index'];
        shuffleModeEnabled = true;
        _shuffleVisibleQueueFromIndex(songIndex);
        _emitPlaybackSnapshot();
        _schedulePreloadWindow();
        break;

      case 'updateMediaItemInAudioService':
        //added to update media item from player controller
        final songIndex = extras!['index'];
        currentIndex = songIndex;
        mediaItem.add(queue.value[currentIndex]);
        _schedulePreloadWindow();
        break;

      case 'toggleQueueLoopMode':
        queueLoopModeEnabled = extras!['enable'];
        _schedulePreloadWindow();
        break;

      case 'clearQueue':
        await customAction("reorderQueue", {
          'oldIndex': currentIndex,
          'newIndex': 0,
        });
        final newQueue = queue.value;
        newQueue.removeRange(1, newQueue.length);
        queue.add(newQueue);
        _queueBeforeShuffle = shuffleModeEnabled
            ? List<MediaItem>.from(newQueue)
            : null;
        _schedulePreloadWindow();
        break;

      case 'updatePlaybackPreloadRange':
        final range = extras?['range'];
        await _preloadService?.setRange(range is int ? range : 0);
        _schedulePreloadWindow();
        break;

      case 'updatePlaybackMode':
        final modeIndex = extras?['mode'];
        final mode =
            modeIndex is int &&
                modeIndex >= 0 &&
                modeIndex < PlaybackMode.values.length
            ? PlaybackMode.values[modeIndex]
            : PlaybackMode.classic;
        await _preloadService?.setMode(mode);
        _schedulePreloadWindow();
        break;

      case 'preloadConfigChanged':
        await _preloadService?.clear();
        _schedulePreloadWindow();
        break;
      default:
        break;
    }
  }

  Audio? _heosCompatibleAudio(HMStreamingData streamInfo) {
    final candidates = [
      streamInfo.highQualityAudio,
      streamInfo.lowQualityAudio,
      streamInfo.audio,
    ];
    for (final audio in candidates) {
      if (audio?.audioCodec == Codec.mp4a) return audio;
    }
    return streamInfo.audio;
  }

  void _shuffleVisibleQueueFromIndex(int index) {
    final currentQueue = List<MediaItem>.from(queue.value);
    if (currentQueue.isEmpty || index < 0 || index >= currentQueue.length) {
      return;
    }
    _queueBeforeShuffle ??= List<MediaItem>.from(currentQueue);
    final shuffledQueue = PlaybackQueueOrder.shuffledFromCurrent(
      currentQueue,
      index,
    );
    _setQueueAndCurrent(shuffledQueue, 0);
  }

  void _restoreQueueBeforeShuffle() {
    final originalQueue = _queueBeforeShuffle;
    if (originalQueue == null || originalQueue.isEmpty || queue.value.isEmpty) {
      _queueBeforeShuffle = null;
      return;
    }

    final currentQueue = queue.value;
    final currentQueueIndex = currentIndex is int ? currentIndex as int : 0;
    final safeCurrentIndex =
        currentQueueIndex >= 0 && currentQueueIndex < currentQueue.length
        ? currentQueueIndex
        : 0;
    final currentItem = currentQueue[safeCurrentIndex];
    final restoredIndex = PlaybackQueueOrder.indexOfSongId(
      originalQueue,
      currentItem.id,
    );
    _setQueueAndCurrent(
      List<MediaItem>.from(originalQueue),
      restoredIndex < 0 ? 0 : restoredIndex,
    );
    _queueBeforeShuffle = null;
  }

  void _setQueueAndCurrent(List<MediaItem> nextQueue, int nextIndex) {
    if (nextQueue.isEmpty) {
      queue.add(nextQueue);
      currentIndex = 0;
      return;
    }

    final clampedIndex = nextIndex < 0
        ? 0
        : nextIndex >= nextQueue.length
        ? nextQueue.length - 1
        : nextIndex;
    queue.add(List<MediaItem>.from(nextQueue));
    currentIndex = clampedIndex;
    // When the current song stays the same (shuffle/unshuffle), rebroadcast
    // the live mediaItem rather than the queue copy: the queue copy can still
    // carry duration == null (the resolved duration is only broadcast, never
    // written back into the queue), which would collapse the progress bar
    // total to zero and pin the bar at 0:00 for the rest of the song.
    final nextItem = nextQueue[clampedIndex];
    final current = mediaItem.value;
    mediaItem.add(
      current != null && current.id == nextItem.id ? current : nextItem,
    );
  }

  Future<void> _normalizeVolume(double currentLoudnessDb) async {
    // 0 means "no loudness data", not "0 dB". Every source that cannot supply
    // a real measurement writes this sentinel: the Resolver, the cached-song
    // and download placeholders, and the extractor whenever the player
    // response omits the field. Treating it as a genuine reading applied
    // 10^(-5/20) = 0.56 to *every* track — no normalization at all, just a
    // permanent ~44% volume cut. Skipping is the only honest response.
    if (currentLoudnessDb == 0) {
      return;
    }

    // Converted loudness difference to a volume multiplier
    // We use a factor to convert dB difference to a linear scale
    // 10^(difference / 20) converts dB difference to a linear volume factor
    final loudnessDifference = -5 - currentLoudnessDb;
    final volumeAdjustment = pow(10.0, loudnessDifference / 20.0);

    // Relative to what the user actually asked for. Assigning the adjustment
    // outright made normalization and the volume slider fight over the same
    // player property, so a mid-song volume change survived only until the
    // next track started and then snapped back.
    final userVolume = _settingsRepository.getVolume() / 100;
    // Attenuate only. Most tracks measure quieter than the -5 dB target, so
    // the raw adjustment is usually >1; multiplying by it would push a user
    // sitting at 50% up towards 100% — louder than they asked for — because
    // the clamp only catches the result, not the intent.
    final target = userVolume * min(volumeAdjustment.toDouble(), 1.0);
    printINFO(
      "loudness:$currentLoudnessDb adjustment:$volumeAdjustment "
      "userVolume:$userVolume -> $target",
      tag: LogTags.audioHandler,
    );
    await _player.setVolume(target.toDouble());
  }

  Future<void> saveSessionData({Duration? positionOverride}) async {
    if (!_settingsRepository.getRestorePlaybackSession()) {
      return;
    }
    final currQueue = queue.value;
    if (currQueue.isNotEmpty) {
      final currIndex = currentIndex ?? 0;
      final position =
          positionOverride?.inMilliseconds ?? _player.position.inMilliseconds;
      await _playbackSessionRepository.saveSession(
        queue: currQueue,
        index: currIndex,
        position: position,
      );
      printINFO("Saved session data", tag: LogTags.audioHandler);
    }
  }

  /// Android Auto
  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    return _mediaLibrary.getByRootId(parentMediaId);
  }

  @override
  ValueStream<Map<String, dynamic>> subscribeToChildren(String parentMediaId) {
    return Stream.fromFuture(
      _mediaLibrary.getByRootId(parentMediaId).then((items) => items),
    ).map((_) => <String, dynamic>{}).shareValue();
  }

  // only for Android Auto
  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    customEvent.add({
      'eventType': 'playFromMediaId',
      'songId': mediaId,
      'libraryId': extras!['libraryId'],
    });
  }

  @override
  Future<void> onTaskRemoved() async {
    final stopForegroundService = _settingsRepository
        .getStopPlaybackOnSwipeAway();
    if (stopForegroundService) {
      customEvent.add({'eventType': 'cacheHomeScreenData'});
      await saveSessionData();
      await stop();
    }
  }

  @override
  Future<void> stop() async {
    if (_forwardRemoteNotificationCommand('pause')) {
      _setRemoteNotificationPlaying(false);
      return;
    }
    await _player.stop();
    isSongLoading = false;
    _clearPreloadWindow();
    _stopCompletionWatchdog();
    CrashDiagnosticsService.instance.record(
      'audio',
      'stop position=${_player.position.inMilliseconds}ms song=${mediaItem.value?.id}',
      includeMemory: true,
      flush: true,
    );
    _emitPlaybackSnapshot(
      processingState: AudioProcessingState.idle,
      playing: false,
    );
    return super.stop();
  }

  // Work around used [useNewInstanceOfExplode = false] to Fix Connection closed before full header was received issue
  Future<HMStreamingData> checkNGetUrl(
    String songId, {
    bool generateNewUrl = false,
    bool offlineReplacementUrl = false,
    bool allowResolver = true,
  }) async {
    printINFO("Requested id : $songId", tag: LogTags.audioHandler);
    if (!offlineReplacementUrl &&
        await _songCacheRepository.containsCachedSong(songId)) {
      // The Hive entry is not proof the audio is still on disk. On Windows the
      // cache lives in %TEMP%, which Storage Sense empties behind the app's
      // back, leaving entries pointing at files that no longer exist. Handing
      // just_audio a missing file does not raise — it sits in `loading`
      // forever, which looks exactly like a hung handoff.
      final cachedPath = "$_cachedSongsDir/$songId.mp3";
      final cachedFile = File(cachedPath);
      if (!await cachedFile.exists()) {
        printWarning(
          "Cached audio for $songId is missing from disk; dropping the stale "
          "cache entry and resolving online",
          tag: LogTags.audioHandler,
        );
        await _songCacheRepository.deleteCachedSong(songId);
        return checkNGetUrl(
          songId,
          generateNewUrl: generateNewUrl,
          allowResolver: allowResolver,
        );
      }
      await _markCachedAudioPlayed(cachedFile);
      printINFO("Got Song from cachedbox ($songId)", tag: LogTags.audioHandler);
      // if contains stream Info
      final cachedSongJson = await _songCacheRepository.getCachedSongJson(
        songId,
      );
      final streamInfo = cachedSongJson["streamInfo"];
      Audio? cacheAudioPlaceholder;
      if (streamInfo != null && streamInfo.isNotEmpty) {
        streamInfo[1]['url'] = "file://$_cachedSongsDir/$songId.mp3";
        cacheAudioPlaceholder = Audio.fromJson(streamInfo[1]);
      } else {
        cacheAudioPlaceholder = Audio(
          audioCodec: Codec.mp4a,
          bitrate: 0,
          loudnessDb: 0,
          duration: 0,
          size: 0,
          url: "file://$_cachedSongsDir/$songId.mp3",
          itag: 0,
        );
      }

      return HMStreamingData(
        playable: true,
        statusMSG: "OK",
        lowQualityAudio: cacheAudioPlaceholder,
        highQualityAudio: cacheAudioPlaceholder,
      );
    } else if (!offlineReplacementUrl &&
        await _downloadRepository.containsDownload(songId)) {
      final song = await _downloadRepository.getDownloadJson(songId);
      if (song == null) {
        printWarning(
          "Download entry for $songId disappeared during stream lookup",
          tag: LogTags.audioHandler,
        );
        return checkNGetUrl(
          songId,
          generateNewUrl: generateNewUrl,
          offlineReplacementUrl: true,
          allowResolver: allowResolver,
        );
      }

      final path = song['url'];
      if (path is! String || path.isEmpty) {
        printWarning(
          "Download entry for $songId has invalid path: $path",
          tag: LogTags.audioHandler,
        );
        return checkNGetUrl(
          songId,
          generateNewUrl: generateNewUrl,
          offlineReplacementUrl: true,
          allowResolver: allowResolver,
        );
      }

      final streamInfoJson = song["streamInfo"];
      Audio? audio;
      if (streamInfoJson is List &&
          streamInfoJson.length > 1 &&
          streamInfoJson[1] is Map) {
        final audioJson = Map<String, dynamic>.from(streamInfoJson[1] as Map);
        audioJson['url'] = path;
        audio = Audio.fromJson(audioJson);
      } else {
        printWarning(
          "Download entry for $songId has no usable streamInfo; using file path placeholder",
          tag: LogTags.audioHandler,
        );
        audio = Audio(
          itag: 140,
          audioCodec: Codec.mp4a,
          bitrate: 0,
          duration: 0,
          loudnessDb: 0,
          url: path,
          size: 0,
        );
      }

      final streamInfo = HMStreamingData(
        playable: true,
        statusMSG: "OK",
        highQualityAudio: audio,
        lowQualityAudio: audio,
      );

      final supportMusicPath =
          "${(await getApplicationSupportDirectory()).path}/Music";
      if (path.contains(supportMusicPath)) {
        // A path inside our own directory is not proof the file is still
        // there: OS storage cleanup, a manual delete, or a restored backup
        // whose paths were rewritten can all outlive the Hive entry. Skipping
        // this check does not fail loudly — just_audio parks in `loading`
        // forever on a missing file, which reads as a hung player rather than
        // an error, so fall through to online resolution instead.
        if (await _localSourceFileExists(path)) {
          return streamInfo;
        }
        printWarning(
          "Download entry for $songId points at a missing file; resolving online",
          tag: LogTags.audioHandler,
        );
        return checkNGetUrl(
          songId,
          generateNewUrl: generateNewUrl,
          offlineReplacementUrl: true,
          allowResolver: allowResolver,
        );
      }
      //check file access and if file exist in storage
      final status = await PermissionService.getExtStoragePermission();
      if (status && await File(path).exists()) {
        return streamInfo;
      }
      //in case file doesnot found in storage, song will be played online
      return checkNGetUrl(
        songId,
        generateNewUrl: generateNewUrl,
        offlineReplacementUrl: true,
        allowResolver: allowResolver,
      );
    } else {
      //check if song stream url is cached and allocate url accordingly
      final qualityIndex = _settingsRepository.getStreamingQualityIndex();
      final sourceMode = _effectiveResolverSourceMode(
        allowResolver: allowResolver,
      );
      HMStreamingData? streamInfo;
      final streamInfoJson = sourceMode == ResolverSourceMode.resolverOnly
          ? null
          : await _songCacheRepository.getStreamCacheEntry(songId);
      if (streamInfoJson != null && !generateNewUrl) {
        if (streamInfoJson.runtimeType.toString().contains("Map") &&
            !isExpired(url: streamInfoJson['lowQualityAudio']['url']) &&
            _cachedUrlStillPlayable(streamInfoJson['lowQualityAudio']['url'])) {
          printINFO("Got cached Url ($songId)", tag: LogTags.audioHandler);
          streamInfo = HMStreamingData.fromJson(streamInfoJson);
        }
      }

      if (streamInfo == null) {
        streamInfo = switch (sourceMode) {
          ResolverSourceMode.both => await _raceOnlineResolvers(songId),
          ResolverSourceMode.resolverOnly => await _resolveWithResolver(songId),
          ResolverSourceMode.existingOnly => await _resolveLocalOnline(songId),
        };
        if (streamInfo.playable &&
            !streamInfo.audio!.url.startsWith('resolver://')) {
          await _songCacheRepository.saveStreamCacheEntry(
            songId,
            streamInfo.toJson(),
          );
        }
      }

      streamInfo.setQualityIndex(qualityIndex);
      return streamInfo;
    }
  }

  ResolverSourceMode _effectiveResolverSourceMode({bool allowResolver = true}) {
    if (!allowResolver) return ResolverSourceMode.existingOnly;
    if (!kDebugMode) return ResolverSourceMode.both;
    return _settingsRepository.getResolverSourceMode();
  }

  Future<void> _resetResolverSources() async {
    for (final pending in _resolverSources.values.toList()) {
      await pending.disposeInitial();
    }
    _resolverSources.clear();
  }

  /// Records *why* a resolution attempt failed.
  ///
  /// Both branches of the race report failure through the same opaque
  /// `resolverPlaybackFailed` status, so by the time anything is user-visible
  /// a rate limit, an unplayable video, a dropped connection and a 403 are
  /// indistinguishable. Working out that YouTube was merely rate limiting the
  /// device took a round trip of state dumps that this line would have
  /// answered on its own.
  ///
  /// Deliberately goes through `recordLog` rather than only `printERROR`:
  /// `printERROR` returns immediately in release builds, which is exactly
  /// where these failures are reported from.
  void _recordResolutionFailure(
    String songId,
    String branch,
    Object? cause,
    StackTrace? stackTrace,
  ) {
    final message = '$branch resolution failed for $songId: $cause';
    CrashDiagnosticsService.instance.recordLog(
      'error',
      LogTags.audioHandler,
      message,
    );
    printERROR(message, tag: LogTags.audioHandler);
    if (stackTrace != null) {
      printWarning(stackTrace.toString(), tag: LogTags.audioHandler);
    }
  }

  /// Asks the Resolver to ingest a track it did not have.
  ///
  /// The prefetch that runs on every song change covers the *next* three
  /// queue entries only, never the one being played. So a track the Resolver
  /// has never ingested answers 404, the local fallback carries that one
  /// playback, and nothing ever tells the Resolver the track exists - the next
  /// attempt hits the same 404, and the one after that. Issue #81 is a track
  /// the Resolver has no record of at all.
  ///
  /// Fire-and-forget, exactly as the downloader already does on the same miss.
  /// It cannot help the attempt in flight; it is what makes the next one work.
  void _requestResolverIngestion(String songId) {
    if (!_effectiveResolverSourceMode().usesResolver) return;
    unawaited(_resolverPlaybackClient.prefetch([songId]));
  }

  Future<HMStreamingData> _resolveWithResolver(String songId) async {
    await _resetResolverSources();
    final cancellation = ResolverOpenCancellation();
    _activeResolverCancellation?.cancel();
    _activeResolverCancellation = cancellation;
    try {
      final source = await _openResolver(songId, cancellation);
      if (source == null) {
        _requestResolverIngestion(songId);
        return HMStreamingData(
          playable: false,
          statusMSG: 'resolverPlaybackFailed',
        );
      }
      return _resolverStreamInfo(songId, source);
    } catch (error, stackTrace) {
      // Every distinct cause — rate limiting, an unplayable video, a network
      // drop, a 403 — collapses into one opaque status by the time it reaches
      // the UI. Without this line a failure is indistinguishable from any
      // other, which has already cost a round trip of state dumps to work out
      // that YouTube was simply rate limiting the device.
      _recordResolutionFailure(songId, 'resolver', error, stackTrace);
      return HMStreamingData(
        playable: false,
        statusMSG: 'resolverPlaybackFailed',
      );
    } finally {
      if (identical(_activeResolverCancellation, cancellation)) {
        _activeResolverCancellation = null;
      }
    }
  }

  Future<ResolverAudioSource?> _openResolver(
    String songId,
    ResolverOpenCancellation cancellation,
  ) {
    final trace = _activePlaybackTrace;
    return _resolverPlaybackClient.open(
      songId,
      cancellation: cancellation,
      onResponseHeaders: () =>
          trace?.responseHeaders(source: PlaybackSourceCategory.resolver),
      onFirstEncodedByte: () =>
          trace?.firstEncodedByte(source: PlaybackSourceCategory.resolver),
    );
  }

  HMStreamingData _resolverStreamInfo(
    String songId,
    ResolverAudioSource source,
  ) {
    _resolverSources[songId] = source;
    final audio = Audio(
      itag: 0,
      audioCodec: Codec.opus,
      bitrate: 0,
      duration: 0,
      loudnessDb: 0,
      url: 'resolver:///$songId',
      size: 0,
    );
    return HMStreamingData(
      playable: true,
      statusMSG: 'OK',
      lowQualityAudio: audio,
      highQualityAudio: audio,
    );
  }

  Future<HMStreamingData> _raceOnlineResolvers(String songId) async {
    await _resetResolverSources();
    final completer = Completer<HMStreamingData>();
    final cancellation = ResolverOpenCancellation();
    _activeResolverCancellation?.cancel();
    _activeResolverCancellation = cancellation;
    var failures = 0;

    void failed() {
      failures++;
      if (failures == 2 && !completer.isCompleted) {
        completer.complete(
          HMStreamingData(playable: false, statusMSG: 'resolverPlaybackFailed'),
        );
      }
    }

    final resolver = _openResolver(songId, cancellation);

    // Local extraction is the fallback, not a co-equal racer.
    //
    // Starting it unconditionally meant every online song cost a watch-page
    // fetch and a player-API call against YouTube from this device — even for
    // tracks the Resolver already held and could serve from its own storage
    // without touching YouTube at all. Roughly double the request volume for
    // no benefit, and request volume is what gets an IP rate limited, which is
    // exactly what took playback down.
    //
    // So the Resolver gets a head start. A track it already holds comes back
    // well inside it and local extraction never runs. Only a Resolver that is
    // slow (a cold ingestion) or failing pays for the fallback — precisely
    // when the fallback is worth having.
    var localStarted = false;
    Future<void> runLocalExtraction() async {
      // Guarded rather than scheduled once: the head start and the resolver's
      // failure paths can both reach for this, and it must run at most once.
      if (localStarted || completer.isCompleted) return;
      localStarted = true;
      try {
        final result = await _resolveLocalOnline(songId);
        if (result.playable && !completer.isCompleted) {
          cancellation.cancel();
          if (identical(_activeResolverCancellation, cancellation)) {
            _activeResolverCancellation = null;
          }
          completer.complete(result);
        } else if (!result.playable) {
          _recordResolutionFailure(songId, 'local', result.statusMSG, null);
          failed();
        }
      } catch (error, stackTrace) {
        _recordResolutionFailure(songId, 'local', error, stackTrace);
        failed();
      }
    }

    unawaited(() async {
      await Future<void>.delayed(_resolverHeadStart);
      await runLocalExtraction();
    }());
    unawaited(() async {
      try {
        final source = await resolver;
        if (source == null) {
          _requestResolverIngestion(songId);
          if (identical(_activeResolverCancellation, cancellation)) {
            _activeResolverCancellation = null;
          }
          // Do not sit out the rest of the head start. It exists to spare a
          // *working* Resolver the duplicate request, and `failed()` cannot
          // reach two until local extraction has had its turn.
          unawaited(runLocalExtraction());
          failed();
          return;
        }
        if (completer.isCompleted) {
          await source.disposeInitial();
          return;
        }
        if (identical(_activeResolverCancellation, cancellation)) {
          _activeResolverCancellation = null;
        }
        completer.complete(_resolverStreamInfo(songId, source));
      } catch (error, stackTrace) {
        _recordResolutionFailure(songId, 'resolver', error, stackTrace);
        if (identical(_activeResolverCancellation, cancellation)) {
          _activeResolverCancellation = null;
        }
        unawaited(runLocalExtraction());
        failed();
      }
    }());
    // Both branches report failure through `failed()`, so the completer settles
    // on its own in every case either of them actually reports. This bound is
    // for the case neither does: the resolver's ingestion poll is capped, but a
    // stalled response-body read is not, and a branch that goes silent rather
    // than failing leaves `failures` short of 2 forever. The caller has already
    // torn down the previous source by this point, so an unsettled future here
    // is a permanently wedged player rather than a slow song (issue #66).
    try {
      return await completer.future.timeout(_onlineResolveTimeout);
    } on TimeoutException {
      cancellation.cancel();
      if (identical(_activeResolverCancellation, cancellation)) {
        _activeResolverCancellation = null;
      }
      printWarning(
        'Online resolve for $songId exceeded '
        '${_onlineResolveTimeout.inSeconds}s with no branch reporting back',
        tag: LogTags.audioHandler,
      );
      return HMStreamingData(
        playable: false,
        statusMSG: 'resolverPlaybackFailed',
      );
    }
  }

  /// The point at which a race in which neither branch reported back is given
  /// up on. Above the resolver's own 30s ingestion poll, so a cold track it is
  /// still fetching is never cut off by this.
  /// How long the Resolver gets before local extraction joins in.
  ///
  /// Long enough that a track the Resolver already holds is served without
  /// this device touching YouTube at all, short enough that a cold ingestion
  /// still falls back quickly. A cached Resolver hit returns well under a
  /// second; local extraction alone measured 2.5-3s, so waiting this long
  /// costs a stalled Resolver very little.
  static const _resolverHeadStart = Duration(seconds: 2);

  static const _onlineResolveTimeout = Duration(seconds: 45);

  /// How long the app's own extraction may take before it forfeits the race.
  ///
  /// youtube_explode's client sets no read timeout, so a half-open socket
  /// neither returns nor throws. `_raceOnlineResolvers` only completes when a
  /// branch succeeds or *both* report failure, so one silent branch used to
  /// wedge playback permanently: the caller awaited a future that could never
  /// settle, having already torn down the previous source (issue #66).
  ///
  /// Deliberately below the Resolver's own 30s ingestion poll, so a cold track
  /// the Resolver is still ingesting stays able to win rather than being cut
  /// off by this branch giving up.
  static const _localExtractionTimeout = Duration(seconds: 20);

  /// Whether a cached URL came from a client whose URLs still play.
  ///
  /// Expiry alone is not enough. When YouTube gated the older clients behind a
  /// proof-of-origin token, every URL already in the cache kept its unexpired
  /// `expire` stamp while quietly becoming unplayable — so the cache served
  /// them, ExoPlayer got a 403, and playback only recovered on the retry that
  /// re-resolves. One wasted load per previously-played song.
  ///
  /// Keying on the issuing client (`c=`) instead means a client switch
  /// invalidates its own cache entries automatically, here and on the next
  /// switch. Non-http entries (offline replacements, cached files) are left
  /// alone: they have no client and never go stale this way.
  static bool _cachedUrlStillPlayable(Object? url) {
    if (url is! String || !url.startsWith('http')) return true;
    final client = Uri.tryParse(url)?.queryParameters['c'];
    if (client == null) return true;
    return client == _streamClientName;
  }

  /// The innertube client [StreamProvider] requests first. Cached URLs issued
  /// by any other client are treated as stale.
  static const _streamClientName = 'VISIONOS';

  Future<HMStreamingData> _resolveLocalOnline(String songId) async {
    final token = RootIsolateToken.instance;
    try {
      // Off the UI thread deliberately: extraction is slow enough that running
      // it on the main isolate blocks input long enough to ANR. The VISIONOS
      // client needs no signature deciphering, so nothing here requires the
      // Flutter bindings a background isolate lacks.
      final json = await Isolate.run(
        () => getStreamInfo(songId, token),
      ).timeout(_localExtractionTimeout);
      return HMStreamingData.fromJson(json);
    } on TimeoutException {
      // Losing the race is the useful outcome: it lets the caller's `failed()`
      // run, so the Resolver's answer can still play the song.
      printWarning(
        'Local extraction for $songId exceeded '
        '${_localExtractionTimeout.inSeconds}s; forfeiting to the resolver',
        tag: LogTags.audioHandler,
      );
      // `networkError`, not a new status: a read that never returns is a
      // network failure, and `notifyPlayError` shows any unrecognised status
      // to the user verbatim. In `existingOnly` mode this value is what the
      // caller gets back, so an invented one would put a raw identifier in a
      // snackbar.
      return HMStreamingData(playable: false, statusMSG: 'networkError');
    }
  }
}

// for Android Auto
class MediaLibrary {
  MediaLibrary({
    required LibraryRepository libraryRepository,
    required PlaylistRepository playlistRepository,
    required SettingsRepository settingsRepository,
  }) : _libraryRepository = libraryRepository,
       _playlistRepository = playlistRepository,
       _settingsRepository = settingsRepository;

  final LibraryRepository _libraryRepository;
  final PlaylistRepository _playlistRepository;
  final SettingsRepository _settingsRepository;

  static const albumsRootId = 'albums';
  static const songsRootId = 'songs';
  static const favoritesRootId = "LIBFAV";
  static const playlistsRootId = 'playlists';

  Future<List<MediaItem>> getByRootId(String id) async {
    switch (id) {
      case AudioService.browsableRootId:
        return Future.value(getRoot());
      case songsRootId:
        return getLibSongs(BoxNames.songDownloads);
      case favoritesRootId:
        return getLibSongs(BoxNames.libFav);
      case BoxNames.libFavNotDownloaded:
        return getLikedNotDownloadedSongs();
      case BoxNames.libImportDuplicates:
        return getLibSongs(BoxNames.libImportDuplicates);
      case BoxNames.libImportReview:
        return getLibSongs(BoxNames.libImportReview);
      case albumsRootId:
        return getAlbums();
      case playlistsRootId:
        return getPlaylists();
      case AudioService.recentRootId:
        return getLibSongs(BoxNames.libRP);
      default:
        return getLibSongs(id);
    }
  }

  List<MediaItem> getRoot() {
    final l10n = _localizations;
    return [
      MediaItem(id: songsRootId, title: l10n.songs, playable: false),
      MediaItem(id: favoritesRootId, title: l10n.favorites, playable: false),
      MediaItem(id: albumsRootId, title: l10n.albums, playable: false),
      MediaItem(id: playlistsRootId, title: l10n.playlists, playable: false),
    ];
  }

  Future<List<MediaItem>> getAlbums() async {
    return (await _libraryRepository.getAlbums())
        .map((album) => album.toMediaItem())
        .toList();
  }

  Future<List<MediaItem>> getPlaylists() async {
    final l10n = _localizations;
    final playlists =
        LibraryPlaylistsController.withInitialPlaylistsTail(
          (await _playlistRepository.getPlaylists()).reversed,
        ).map((playlist) {
          final item = playlist.toMediaItem();
          final title = switch (playlist.playlistId) {
            BoxNames.libRP => l10n.recentlyPlayed,
            BoxNames.libFav => l10n.favorites,
            BoxNames.libFavNotDownloaded => l10n.likedNotDownloaded,
            BoxNames.libImportDuplicates => l10n.importConflicts,
            BoxNames.libImportReview => l10n.importNeedsReview,
            BoxNames.songsCache => l10n.cachedOrOffline,
            BoxNames.songDownloads => l10n.downloads,
            _ => playlist.title,
          };
          return item.copyWith(title: title);
        }).toList();
    return playlists;
  }

  AppLocalizations get _localizations =>
      appLocalizationsForLanguageCode(_settingsRepository.getLanguageCode());

  Future<List<MediaItem>> getLibSongs(String libId) async {
    final songs = switch (libId) {
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
      _ => await _playlistRepository.getPlaylistSongs(libId),
    };
    final mediaItems = songs.map((song) {
      return MediaItem(
        id: song.id,
        title: song.title,
        artist: song.artist,
        artUri: song.artUri,
        extras: {"libraryId": libId},
        playable: true,
      );
    }).toList();

    if (libId == BoxNames.libRP) {
      return mediaItems.reversed.toList();
    }

    return mediaItems;
  }

  Future<List<MediaItem>> getLikedNotDownloadedSongs() async {
    return (await _libraryRepository.getFavoriteNotDownloadedSongs())
        .map(
          (song) => MediaItem(
            id: song.id,
            title: song.title,
            artist: song.artist,
            artUri: song.artUri,
            extras: {"libraryId": BoxNames.libFavNotDownloaded},
            playable: true,
          ),
        )
        .toList();
  }
}
