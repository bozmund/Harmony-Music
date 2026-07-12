import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/services.dart';

import 'package:harmonymusic/l10n/app_localizations.dart';
import 'package:harmonymusic/l10n/l10n.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
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
import '/services/constant.dart';
import '/services/crash_diagnostics_service.dart';
import '/services/playback_queue_order.dart';
import '/services/playback_preload_service.dart';
import '/services/equalizer.dart';
import '/services/stream_service.dart';
import '/models/hm_streaming_data.dart';
import '/services/background_task.dart';
import '/services/permission_service.dart';
import 'resolver/resolver_audio_source.dart';
import 'resolver/resolver_playback_client.dart';
import '../utils/helper.dart';
import '/models/media_Item_builder.dart';
import '/services/utils.dart';
import '../ui/screens/Library/library_controller.dart';

// ignore: unused_import, implementation_imports, depend_on_referenced_packages
import "package:media_kit/src/player/platform_player.dart" show MPVLogLevel;

const _androidNotificationArtSize = 256;
const _fallbackCompletionGrace = Duration(milliseconds: 1250);

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
  return await AudioService.init(
    builder: () => handler,
    config: const AudioServiceConfig(
      androidNotificationIcon: 'mipmap/ic_launcher_monochrome',
      androidNotificationChannelId: 'com.mycompany.myapp.audio',
      androidNotificationChannelName: 'Harmony Music Notification',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      artDownscaleWidth: _androidNotificationArtSize,
      artDownscaleHeight: _androidNotificationArtSize,
    ),
  );
}

class MyAudioHandler extends BaseAudioHandler {
  // ignore: prefer_typing_uninitialized_variables
  late final _cacheDir;
  late AudioPlayer _player;
  late MediaLibrary _mediaLibrary;
  late PlaybackPreloadService _preloadService;
  late final SettingsRepository _settingsRepository;
  late final LibraryRepository _libraryRepository;
  late final DownloadRepository _downloadRepository;
  late final SongCacheRepository _songCacheRepository;
  late final PlaylistRepository _playlistRepository;
  late final PlaybackSessionRepository _playbackSessionRepository;
  late final ResolverPlaybackClient _resolverPlaybackClient;
  final Map<String, ResolverAudioSource> _resolverSources = {};

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
  bool _sourceSwitchInProgress = false;
  bool _sourceSwitchWasPlaying = false;
  int _playbackGeneration = 0;
  bool _preEndWindowActive = false;
  Future<void>? _prepareNextSourceTask;
  int? _preparedForGeneration;
  int? _preparedNextIndex;
  String? _preparedNextSongId;
  HMStreamingData? _preparedNextStreamInfo;
  static const _androidTargetBufferBytes = 8 * 1024 * 1024;

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
      JustAudioMediaKit.title = 'Harmony music';
      JustAudioMediaKit.protocolWhitelist = const ['http', 'https', 'file'];
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
          bufferForPlaybackDuration: Duration(milliseconds: 500),
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
    await _createCacheDir();
    _preloadService = PlaybackPreloadService(
      preloadDirectory: Directory("$_cacheDir/preloadedSongs"),
      resolveStreamInfo:
          (songId, {generateNewUrl = false, offlineReplacementUrl = false}) =>
              checkNGetUrl(
                songId,
                generateNewUrl: generateNewUrl,
                offlineReplacementUrl: offlineReplacementUrl,
                allowResolver: false,
              ),
      settingsRepository: _settingsRepository,
      songCacheRepository: _songCacheRepository,
    );
    await _preloadService.init();
    await _addEmptyList();

    _notifyAudioHandlerAboutPlaybackEvents();
    _listenToPlaybackForNextSong();
    _listenForEndPositionFallback();
    _listenForSequenceStateChanges();

    await _player.setSkipSilenceEnabled(
      _settingsRepository.getSkipSilenceEnabled(),
    );

    loopModeEnabled = _settingsRepository.getLoopModeEnabled();
    shuffleModeEnabled = _settingsRepository.getShuffleModeEnabled();
    queueLoopModeEnabled = _settingsRepository.getQueueLoopModeEnabled();
    loudnessNormalizationEnabled = _settingsRepository
        .getLoudnessNormalizationEnabled();
    await _player.setLoopMode(loopModeEnabled ? LoopMode.one : LoopMode.off);

    _listenForDurationChanges();

    if (RuntimePlatform.isAndroid) {
      _listenSessionIdStream();
    }
  }

  Future<void> _createCacheDir() async {
    _cacheDir = (await getTemporaryDirectory()).path;
    if (!Directory("$_cacheDir/cachedSongs/").existsSync()) {
      Directory("$_cacheDir/cachedSongs/").createSync(recursive: true);
    }
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
    final candidateIndices = currentQueueIndex == null
        ? <int>[]
        : _preloadCandidateIndices(_preloadService.range);
    _preloadService.schedule(
      queue: queueSnapshot,
      candidateIndices: candidateIndices,
      isPlaying: _player.playing,
      currentIndex: currentQueueIndex,
    );
  }

  void _clearPreloadWindow() {
    unawaited(_preloadService.clear());
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
  }) => _preloadService.streamInfoFor(
    song,
    generateNewUrl: generateNewUrl,
    fallback: () => checkNGetUrl(song.id, generateNewUrl: generateNewUrl),
  );

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
        final playing = _sourceSwitchInProgress && _sourceSwitchWasPlaying
            ? true
            : _player.playing;
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
            processingState: isSongLoading
                ? AudioProcessingState.loading
                : _sourceSwitchInProgress && _sourceSwitchWasPlaying
                ? AudioProcessingState.ready
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

        if (RuntimePlatform.isAndroid && playing && !_lastPreloadPlaying) {
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
          // customAction("playByIndex", {'index': currentIndex, 'newUrl': true})
          //     .whenComplete(() async {
          //   await _player.stop();
          //   if (currentSongUrl == null) {
          //     networkErrorPause = true;
          //   } else {
          //     _player.play();
          //   }
          // });
          await customAction("playByIndex", {
            'index': currentIndex,
            'newUrl': true,
          });
          await _player.seek(curPos, index: 0);
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
      'preloadRange': _preloadService.range,
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
    await _player.stop();
    await _playList.clear();
    await _playList.add(_createAudioSource(song));
  }

  void _listenToPlaybackForNextSong() {
    _player.processingStateStream.listen((state) async {
      if (state == ProcessingState.completed) {
        _scheduleCompletionHandling();
      }
    });
  }

  void _scheduleCompletionHandling({bool allowEndPosition = false}) {
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
        await _repeatCurrentSongFromStart();
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
      (_) => _checkCompletionWatchdog(),
    );
  }

  void _stopCompletionWatchdog() {
    _completionWatchdogTimer?.cancel();
    _completionWatchdogTimer = null;
    _resetEarlyCompletionDeferral();
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

  void _endSourceSwitch({bool defer = false}) {
    if (defer) {
      Timer(const Duration(milliseconds: 500), _endSourceSwitch);
      return;
    }
    _sourceSwitchInProgress = false;
    _sourceSwitchWasPlaying = false;
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

    final cachedSongJson = await _songCacheRepository.getCachedSongJson(songId);
    final streamInfo = cachedSongJson?["streamInfo"];
    Audio audio;
    if (streamInfo != null && streamInfo.isNotEmpty) {
      streamInfo[1]['url'] = "file://$_cacheDir/cachedSongs/$songId.mp3";
      audio = Audio.fromJson(streamInfo[1]);
    } else {
      audio = Audio(
        audioCodec: Codec.mp4a,
        bitrate: 0,
        loudnessDb: 0,
        duration: 0,
        size: 0,
        url: "file://$_cacheDir/cachedSongs/$songId.mp3",
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
    if (!isInSupportDir && !(hasExternalAccess && await File(path).exists())) {
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

  Future<void> _repeatCurrentSongFromStart() async {
    if (_playList.children.isEmpty || currentSongUrl == null) return;

    await _player.seek(Duration.zero, index: 0);
    _startPlayerPlayback();
    _startCompletionWatchdog();
  }

  Future<void> _loadCurrentSourceFromStartAndPlay() async {
    await _player.load();
    await _player.seek(Duration.zero, index: 0);
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
    if (shuffleModeEnabled) {
      _queueBeforeShuffle = List<MediaItem>.from(queue);
    } else {
      _queueBeforeShuffle = null;
    }
    final newQueue = this.queue.value
      ..replaceRange(0, this.queue.value.length, queue);
    this.queue.add(newQueue);
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
      if (source != null) return source.withTag(mediaItem);
    }
    final cacheSongsEnabled = _settingsRepository.getCacheSongs();
    final preloadedSource = _preloadService.createAudioSource(
      mediaItem,
      cacheSongsEnabled: cacheSongsEnabled,
    );
    if (preloadedSource != null) return preloadedSource;

    if (url.contains('/cache') || (cacheSongsEnabled && url.contains("http"))) {
      printINFO("Playing Using LockCaching", tag: LogTags.audioHandler);
      isPlayingUsingLockCachingSource = true;
      // ignore: experimental_member_use
      return LockCachingAudioSource(
        Uri.parse(url),
        cacheFile: File("$_cacheDir/cachedSongs/${mediaItem.id}.mp3"),
        tag: mediaItem,
      );
    }

    printINFO("Playing Using AudioSource.uri", tag: LogTags.audioHandler);
    isPlayingUsingLockCachingSource = false;
    return AudioSource.uri(Uri.tryParse(url)!, tag: mediaItem);
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
    if (currentSongUrl == null ||
        (RuntimePlatform.isDesktop &&
            (_player.duration == null ||
                _player.duration?.inMilliseconds == 0))) {
      await customAction("playByIndex", {'index': currentIndex});
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
    _startPlayerPlayback();
    _startCompletionWatchdog();
    _schedulePreloadWindow();
  }

  @override
  Future<void> pause() async {
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
    await customAction("playByIndex", {'index': index});
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
    final index = _getNextSongIndex();
    if (index != currentIndex) {
      printINFO(
        "Completion advancing from $currentIndex to $index",
        tag: LogTags.audioHandler,
      );
      await customAction("playByIndex", {'index': index});
    } else if (queueLoopModeEnabled) {
      printINFO(
        "Completion restarting current queue item because queue loop is enabled",
        tag: LogTags.audioHandler,
      );
      await _player.seek(Duration.zero);
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
    if (_player.position.inMilliseconds > 5000) {
      await _player.seek(Duration.zero);
      return;
    }
    final index = _getPrevSongIndex();
    if (index != currentIndex) {
      await customAction("playByIndex", {'index': index});
      return;
    }
    await _player.seek(Duration.zero);
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

      case 'dispose':
        _stopCompletionWatchdog();
        await _preloadService.clear();
        await _player.dispose();
        await super.stop();
        break;

      case 'playByIndex':
        final songIndex = extras!['index'];
        currentIndex = songIndex;
        final isNewUrlReq = extras['newUrl'] ?? false;
        final currentSong = queue.value[currentIndex];
        final bool restoreSession = extras['restoreSession'] ?? false;
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
            await _player.stop();
            await _playList.clear();
          }

          var streamInfo = await futureStreamInfo;
          if (requestGeneration != _playbackGeneration ||
              songIndex != currentIndex) {
            _endSourceSwitch();
            return;
          }
          if (!streamInfo.playable && !isNewUrlReq) {
            streamInfo = await checkNGetUrl(
              currentSong.id,
              generateNewUrl: true,
            );
            if (requestGeneration != _playbackGeneration ||
                songIndex != currentIndex) {
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
              await _player.load();
              await _player.seek(Duration(milliseconds: position));
              await _player.seek(Duration(milliseconds: position));
            }
            isSongLoading = false;
            _emitPlaybackSnapshot(processingState: AudioProcessingState.ready);
            _endSourceSwitch();
          } else {
            printINFO('playByIndex seek and play', tag: LogTags.audioHandler);
            try {
              await _loadCurrentSourceFromStartAndPlay();
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
              await _loadCurrentSourceFromStartAndPlay();
            }
            isSongLoading = false;
            _emitSourceStartedSnapshot();
            _endSourceSwitch(defer: true);
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
        }
        break;

      case 'checkWithCacheDb':
        if (isPlayingUsingLockCachingSource) {
          final song = extras!['mediaItem'] as MediaItem;
          if (!await _songCacheRepository.containsCachedSong(song.id) &&
              await File("$_cacheDir/cachedSongs/${song.id}.mp3").exists()) {
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
          await _player.stop();
          await _playList.clear();
          var streamInfo = await futureStreamInfo;
          if (requestGeneration != _playbackGeneration) {
            _endSourceSwitch();
            return;
          }
          if (!streamInfo.playable) {
            streamInfo = await checkNGetUrl(currMed.id, generateNewUrl: true);
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
          _endSourceSwitch(defer: true);
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
        await _preloadService.setRange(range is int ? range : 0);
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
        await _preloadService.setMode(mode);
        _schedulePreloadWindow();
        break;

      case 'preloadConfigChanged':
        await _preloadService.clear();
        _schedulePreloadWindow();
        break;
      default:
        break;
    }
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
    double loudnessDifference = -5 - currentLoudnessDb;

    // Converted loudness difference to a volume multiplier
    // We use a factor to convert dB difference to a linear scale
    // 10^(difference / 20) converts dB difference to a linear volume factor
    final volumeAdjustment = pow(10.0, loudnessDifference / 20.0);
    printINFO(
      "loudness:$currentLoudnessDb Normalized volume: $volumeAdjustment",
      tag: LogTags.audioHandler,
    );
    await _player.setVolume(volumeAdjustment.toDouble().clamp(0, 1.0));
  }

  Future<void> saveSessionData() async {
    if (!_settingsRepository.getRestorePlaybackSession()) {
      return;
    }
    final currQueue = queue.value;
    if (currQueue.isNotEmpty) {
      final currIndex = currentIndex ?? 0;
      final position = _player.position.inMilliseconds;
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
      printINFO("Got Song from cachedbox ($songId)", tag: LogTags.audioHandler);
      // if contains stream Info
      final cachedSongJson = await _songCacheRepository.getCachedSongJson(
        songId,
      );
      final streamInfo = cachedSongJson["streamInfo"];
      Audio? cacheAudioPlaceholder;
      if (streamInfo != null && streamInfo.isNotEmpty) {
        streamInfo[1]['url'] = "file://$_cacheDir/cachedSongs/$songId.mp3";
        cacheAudioPlaceholder = Audio.fromJson(streamInfo[1]);
      } else {
        cacheAudioPlaceholder = Audio(
          audioCodec: Codec.mp4a,
          bitrate: 0,
          loudnessDb: 0,
          duration: 0,
          size: 0,
          url: "file://$_cacheDir/cachedSongs/$songId.mp3",
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
        return streamInfo;
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
      HMStreamingData? streamInfo;
      final streamInfoJson = await _songCacheRepository.getStreamCacheEntry(
        songId,
      );
      if (streamInfoJson != null && !generateNewUrl) {
        if (streamInfoJson.runtimeType.toString().contains("Map") &&
            !isExpired(url: streamInfoJson['lowQualityAudio']['url'])) {
          printINFO("Got cached Url ($songId)", tag: LogTags.audioHandler);
          streamInfo = HMStreamingData.fromJson(streamInfoJson);
        }
      }

      if (streamInfo == null) {
        streamInfo = allowResolver
            ? await _raceOnlineResolvers(songId)
            : await _resolveLocalOnline(songId);
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

  Future<HMStreamingData> _raceOnlineResolvers(String songId) async {
    for (final pending in _resolverSources.values.toList()) {
      await pending.disposeInitial();
    }
    _resolverSources.clear();
    final completer = Completer<HMStreamingData>();
    var failures = 0;

    void failed() {
      failures++;
      if (failures == 2 && !completer.isCompleted) {
        completer.complete(
          HMStreamingData(playable: false, statusMSG: 'resolverPlaybackFailed'),
        );
      }
    }

    final local = _resolveLocalOnline(songId);
    final resolver = _resolverPlaybackClient.open(songId);

    unawaited(() async {
      try {
        final result = await local;
        if (result.playable && !completer.isCompleted) {
          completer.complete(result);
        } else if (!result.playable) {
          failed();
        }
      } catch (_) {
        failed();
      }
    }());
    unawaited(() async {
      try {
        final source = await resolver;
        if (source == null) {
          failed();
          return;
        }
        if (completer.isCompleted) {
          await source.disposeInitial();
          return;
        }
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
        completer.complete(
          HMStreamingData(
            playable: true,
            statusMSG: 'OK',
            lowQualityAudio: audio,
            highQualityAudio: audio,
          ),
        );
      } catch (_) {
        failed();
      }
    }());
    final winner = await completer.future;
    return winner;
  }

  Future<HMStreamingData> _resolveLocalOnline(String songId) async {
    final token = RootIsolateToken.instance;
    final json = await Isolate.run(() => getStreamInfo(songId, token));
    return HMStreamingData.fromJson(json);
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
