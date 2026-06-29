import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/services.dart';

import 'package:get/get.dart';
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
import '/services/constant.dart';
import '/services/playback_preload_service.dart';
import '/services/equalizer.dart';
import '/services/stream_service.dart';
import '/models/hm_streaming_data.dart';
import '/ui/player/player_controller.dart';
import '../ui/screens/Home/home_screen_controller.dart';
import '/services/background_task.dart';
import '/services/permission_service.dart';
import '../utils/helper.dart';
import '/models/media_Item_builder.dart';
import '/services/utils.dart';
import '../ui/screens/Settings/settings_screen_controller.dart';
import '../ui/screens/Library/library_controller.dart';

// ignore: unused_import, implementation_imports, depend_on_referenced_packages
import "package:media_kit/src/player/platform_player.dart" show MPVLogLevel;

Future<AudioHandler> initAudioService() async {
  final handler = await MyAudioHandler.create(
    settingsRepository: Get.find<SettingsRepository>(),
    libraryRepository: Get.find<LibraryRepository>(),
    downloadRepository: Get.find<DownloadRepository>(),
    songCacheRepository: Get.find<SongCacheRepository>(),
    playlistRepository: Get.find<PlaylistRepository>(),
    playbackSessionRepository: Get.find<PlaybackSessionRepository>(),
  );
  return await AudioService.init(
    builder: () => handler,
    config: const AudioServiceConfig(
      androidNotificationIcon: 'mipmap/ic_launcher_monochrome',
      androidNotificationChannelId: 'com.mycompany.myapp.audio',
      androidNotificationChannelName: 'Harmony Music Notification',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
}

class MyAudioHandler extends BaseAudioHandler with GetxServiceMixin {
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

  // ignore: prefer_typing_uninitialized_variables
  dynamic currentIndex;
  int currentShuffleIndex = 0;
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

  // list of shuffled queue songs ids
  List<String> shuffledQueue = [];

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
  }) {
    _settingsRepository = settingsRepository;
    _libraryRepository = libraryRepository;
    _downloadRepository = downloadRepository;
    _songCacheRepository = songCacheRepository;
    _playlistRepository = playlistRepository;
    _playbackSessionRepository = playbackSessionRepository;

    if (GetPlatform.isWindows || GetPlatform.isLinux) {
      JustAudioMediaKit.title = 'Harmony music';
      JustAudioMediaKit.protocolWhitelist = const ['http', 'https', 'file'];
    }

    _mediaLibrary = MediaLibrary(
      libraryRepository: _libraryRepository,
      playlistRepository: _playlistRepository,
    );

    _player = AudioPlayer(
      audioLoadConfiguration: const AudioLoadConfiguration(
        androidLoadControl: AndroidLoadControl(
          minBufferDuration: Duration(seconds: 50),
          maxBufferDuration: Duration(seconds: 120),
          bufferForPlaybackDuration: Duration(milliseconds: 50),
          bufferForPlaybackAfterRebufferDuration: Duration(seconds: 2),
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
  }) async {
    final handler = MyAudioHandler._(
      settingsRepository: settingsRepository,
      libraryRepository: libraryRepository,
      downloadRepository: downloadRepository,
      songCacheRepository: songCacheRepository,
      playlistRepository: playlistRepository,
      playbackSessionRepository: playbackSessionRepository,
    );
    await handler._init();
    return handler;
  }

  Future<void> _init() async {
    await _createCacheDir();
    _preloadService = PlaybackPreloadService(
      preloadDirectory: Directory("$_cacheDir/preloadedSongs"),
      resolveStreamInfo: checkNGetUrl,
      settingsRepository: _settingsRepository,
      songCacheRepository: _songCacheRepository,
    );
    await _preloadService.init();
    await _addEmptyList();

    _notifyAudioHandlerAboutPlaybackEvents();
    _listenToPlaybackForNextSong();
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

    if (GetPlatform.isAndroid) {
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

    if (shuffleModeEnabled && shuffledQueue.isNotEmpty) {
      final currentId = currentQueue[center].id;
      final sequenceCenter = shuffledQueue.indexOf(currentId);
      if (sequenceCenter != -1) {
        void addShuffleOffset(int offset) {
          var sequenceIndex = sequenceCenter + offset;
          if (queueLoopModeEnabled) {
            sequenceIndex =
                ((sequenceIndex % shuffledQueue.length) +
                    shuffledQueue.length) %
                shuffledQueue.length;
          } else if (sequenceIndex < 0 ||
              sequenceIndex >= shuffledQueue.length) {
            return;
          }
          final queueIndex = currentQueue.indexWhere(
            (item) => item.id == shuffledQueue[sequenceIndex],
          );
          addIndex(queueIndex);
        }

        for (var distance = 1; distance <= range; distance++) {
          addShuffleOffset(distance);
          addShuffleOffset(-distance);
        }
        addIndex(center);
        return indices;
      }
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
        final playing = _player.playing;
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
                : const {
                    ProcessingState.idle: AudioProcessingState.idle,
                    ProcessingState.loading: AudioProcessingState.loading,
                    ProcessingState.buffering: AudioProcessingState.buffering,
                    ProcessingState.ready: AudioProcessingState.ready,
                    ProcessingState.completed: AudioProcessingState.completed,
                  }[_player.processingState]!,
            repeatMode: const {
              LoopMode.off: AudioServiceRepeatMode.none,
              LoopMode.one: AudioServiceRepeatMode.one,
              LoopMode.all: AudioServiceRepeatMode.all,
            }[_player.loopMode]!,
            shuffleMode: shuffleModeEnabled
                ? AudioServiceShuffleMode.all
                : AudioServiceShuffleMode.none,
            playing: playing,
            updatePosition: _player.position,
            bufferedPosition: _player.bufferedPosition,
            speed: _player.speed,
            queueIndex: currentIndex,
          ),
        );

        if (GetPlatform.isAndroid && playing && !_lastPreloadPlaying) {
          _lastPreloadPlaying = true;
          _schedulePreloadWindow();
        } else if (!playing) {
          _lastPreloadPlaying = false;
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
            await _player.play();
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

  void _listenToPlaybackForNextSong() {
    _player.processingStateStream.listen((state) async {
      if (state != ProcessingState.completed ||
          isSongLoading ||
          _completionInProgress) {
        return;
      }

      _completionInProgress = true;
      try {
        if (loopModeEnabled) {
          await _repeatCurrentSongFromStart();
          return;
        }

        await skipToNext();
      } finally {
        _completionInProgress = false;
      }
    });
  }

  Future<void> _repeatCurrentSongFromStart() async {
    if (_playList.children.isEmpty || currentSongUrl == null) return;

    await _player.seek(Duration.zero, index: 0);
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
    // notify system
    final newQueue = queue.value..addAll(mediaItems);
    queue.add(newQueue);

    if (shuffleModeEnabled) {
      final mediaItemsIds = mediaItems.toList().map((item) => item.id).toList();
      final notPlayedshuffledQueue = shuffledQueue.isNotEmpty
          ? shuffledQueue.toList().sublist(currentShuffleIndex + 1)
          : shuffledQueue;
      notPlayedshuffledQueue.addAll(mediaItemsIds);
      notPlayedshuffledQueue.shuffle();
      shuffledQueue.replaceRange(
        currentShuffleIndex,
        shuffledQueue.length,
        notPlayedshuffledQueue,
      );
    }
    _schedulePreloadWindow();
  }

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    final newQueue = this.queue.value
      ..replaceRange(0, this.queue.value.length, queue);
    this.queue.add(newQueue);
    _schedulePreloadWindow();
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    if (shuffleModeEnabled) {
      shuffledQueue.add(mediaItem.id);
    }

    // notify system
    final newQueue = queue.value..add(mediaItem);
    queue.add(newQueue);
    _schedulePreloadWindow();
  }

  AudioSource _createAudioSource(MediaItem mediaItem) {
    final url = mediaItem.extras!['url'] as String;
    final cacheSongsEnabled =
        Get.find<SettingsScreenController>().cacheSongs.isTrue;
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
    if (shuffleModeEnabled) {
      final id = mediaItem_.id;
      final itemIndex = shuffledQueue.indexOf(id);
      if (currentShuffleIndex > itemIndex) {
        currentShuffleIndex -= 1;
      }
      shuffledQueue.remove(id);
    }

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
        (GetPlatform.isDesktop &&
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
    await _player.play();
    _schedulePreloadWindow();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _clearPreloadWindow();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= queue.value.length) return;
    await customAction("playByIndex", {'index': index});
  }

  int _getNextSongIndex() {
    if (shuffleModeEnabled) {
      if (currentShuffleIndex + 1 >= shuffledQueue.length) {
        shuffledQueue.shuffle();
        currentShuffleIndex = 0;
      } else {
        currentShuffleIndex += 1;
      }
      return queue.value.indexWhere(
        (item) => item.id == shuffledQueue[currentShuffleIndex],
      );
    }

    if (queue.value.length > currentIndex + 1) {
      return currentIndex + 1;
    } else if (queueLoopModeEnabled) {
      return 0;
    } else {
      return currentIndex;
    }
  }

  int _getPrevSongIndex() {
    if (shuffleModeEnabled) {
      if (currentShuffleIndex - 1 < 0) {
        shuffledQueue.shuffle();
        currentShuffleIndex = shuffledQueue.length - 1;
      } else {
        currentShuffleIndex -= 1;
      }
      return queue.value.indexWhere(
        (item) => item.id == shuffledQueue[currentShuffleIndex],
      );
    }

    if (currentIndex - 1 >= 0) {
      return currentIndex - 1;
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
      await _player.play();
    } else {
      printINFO(
        "Completion reached queue end; pausing at start of current item",
        tag: LogTags.audioHandler,
      );
      await _player.seek(Duration.zero);
      await _player.pause();
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
    loopModeEnabled = repeatMode != AudioServiceRepeatMode.none;
    await _player.setLoopMode(loopModeEnabled ? LoopMode.one : LoopMode.off);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    if (shuffleMode == AudioServiceShuffleMode.none) {
      shuffleModeEnabled = false;
      shuffledQueue.clear();
    } else {
      _shuffleCmd(currentIndex);
      shuffleModeEnabled = true;
    }
    _schedulePreloadWindow();
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'dispose':
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
        isSongLoading = true;
        mediaItem.add(currentSong);
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.loading,
            queueIndex: currentIndex,
          ),
        );
        final futureStreamInfo = _streamInfoForSong(
          currentSong,
          generateNewUrl: isNewUrlReq,
        );
        if (_playList.children.isNotEmpty) {
          await _player.stop();
          await _playList.clear();
        }

        var streamInfo = await futureStreamInfo;
        if (songIndex != currentIndex) return;
        if (!streamInfo.playable && !isNewUrlReq) {
          streamInfo = await checkNGetUrl(currentSong.id, generateNewUrl: true);
          if (songIndex != currentIndex) return;
        }
        if (!streamInfo.playable) {
          currentSongUrl = null;
          isSongLoading = false;
          _schedulePreloadWindow();
          Get.find<PlayerController>().notifyPlayError(streamInfo.statusMSG);
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
        playbackState.add(
          playbackState.value.copyWith(queueIndex: currentIndex),
        );
        await _playList.add(_createAudioSource(currentSong));

        isSongLoading = false;
        if (loudnessNormalizationEnabled && GetPlatform.isAndroid) {
          await _normalizeVolume(streamInfo.audio!.loudnessDb);
        }

        if (restoreSession) {
          if (!GetPlatform.isDesktop) {
            final position = extras['position'];
            await _player.load();
            await _player.seek(Duration(milliseconds: position));
            await _player.seek(Duration(milliseconds: position));
          }
        } else {
          await _player.seek(Duration.zero, index: 0);
          await _player.play();
          _schedulePreloadWindow();
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
            // playbility status and info
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
            LibrarySongsController librarySongsController =
                Get.find<LibrarySongsController>();
            if (!librarySongsController.isClosed) {
              librarySongsController.addSongToLibraryList(song);
            }
          }
        }
        break;

      case 'setSourceNPlay':
        final currMed = extras!['mediaItem'] as MediaItem;
        isSongLoading = true;
        currentIndex = 0;
        mediaItem.add(currMed);
        queue.add([currMed]);
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.loading,
            queueIndex: currentIndex,
          ),
        );
        final futureStreamInfo = _streamInfoForSong(currMed);
        await _player.stop();
        await _playList.clear();
        var streamInfo = await futureStreamInfo;
        if (!streamInfo.playable) {
          streamInfo = await checkNGetUrl(currMed.id, generateNewUrl: true);
        }
        if (!streamInfo.playable) {
          currentSongUrl = null;
          isSongLoading = false;
          _schedulePreloadWindow();
          Get.find<PlayerController>().notifyPlayError(streamInfo.statusMSG);
          playbackState.add(
            playbackState.value.copyWith(
              processingState: AudioProcessingState.error,
            ),
          );
          return;
        }
        currentSongUrl = currMed.extras!['url'] = streamInfo.audio!.url;

        await _playList.add(_createAudioSource(currMed));
        isSongLoading = false;

        // Normalize audio
        if (loudnessNormalizationEnabled && GetPlatform.isAndroid) {
          await _normalizeVolume(streamInfo.audio!.loudnessDb);
        }

        await _player.seek(Duration.zero, index: 0);
        await _player.play();
        _schedulePreloadWindow();
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
        if (shuffleModeEnabled) {
          shuffledQueue.insert(currentShuffleIndex + 1, song.id);
        }
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
        _shuffleCmd(songIndex);
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
        if (shuffleModeEnabled) {
          shuffledQueue.clear();
          shuffledQueue.add(newQueue[0].id);
          currentShuffleIndex = 0;
        }
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

  void _shuffleCmd(int index) {
    final queueIds = queue.value.toList().map((item) => item.id).toList();
    final currentSongId = queueIds.removeAt(index);
    queueIds.shuffle();
    queueIds.insert(0, currentSongId);
    shuffledQueue.replaceRange(0, shuffledQueue.length, queueIds);
    currentShuffleIndex = 0;
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
    if (Get.find<SettingsScreenController>().restorePlaybackSession.isFalse) {
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
    final stopForegroundService =
        Get.find<SettingsScreenController>().stopPlaybackOnSwipeAway.value;
    if (stopForegroundService) {
      await Get.find<HomeScreenController>().cachedHomeScreenData();
      await saveSessionData();
      await stop();
    }
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

  // Work around used [useNewInstanceOfExplode = false] to Fix Connection closed before full header was received issue
  Future<HMStreamingData> checkNGetUrl(
    String songId, {
    bool generateNewUrl = false,
    bool offlineReplacementUrl = false,
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
        return checkNGetUrl(songId, offlineReplacementUrl: true);
      }

      final path = song['url'];
      if (path is! String || path.isEmpty) {
        printWarning(
          "Download entry for $songId has invalid path: $path",
          tag: LogTags.audioHandler,
        );
        return checkNGetUrl(songId, offlineReplacementUrl: true);
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

      if (path.contains(
        "${Get.find<SettingsScreenController>().supportDirPath}/Music",
      )) {
        return streamInfo;
      }
      //check file access and if file exist in storage
      final status = await PermissionService.getExtStoragePermission();
      if (status && await File(path).exists()) {
        return streamInfo;
      }
      //in case file doesnot found in storage, song will be played online
      return checkNGetUrl(songId, offlineReplacementUrl: true);
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
        final token = RootIsolateToken.instance;
        final streamInfoJson = await Isolate.run(
          () => getStreamInfo(songId, token),
        );
        streamInfo = HMStreamingData.fromJson(streamInfoJson);
        if (streamInfo.playable)
          await _songCacheRepository.saveStreamCacheEntry(
            songId,
            streamInfoJson,
          );
      }

      streamInfo.setQualityIndex(qualityIndex);
      return streamInfo;
    }
  }
}

class UrlError extends Error {
  String message() => 'Unable to fetch url';
}

// for Android Auto
class MediaLibrary {
  MediaLibrary({
    required LibraryRepository libraryRepository,
    required PlaylistRepository playlistRepository,
  }) : _libraryRepository = libraryRepository,
       _playlistRepository = playlistRepository;

  final LibraryRepository _libraryRepository;
  final PlaylistRepository _playlistRepository;

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
    return [
      MediaItem(id: songsRootId, title: "songs".tr, playable: false),
      MediaItem(id: favoritesRootId, title: "favorites".tr, playable: false),
      MediaItem(id: albumsRootId, title: "albums".tr, playable: false),
      MediaItem(id: playlistsRootId, title: "playlists".tr, playable: false),
    ];
  }

  Future<List<MediaItem>> getAlbums() async {
    return (await _libraryRepository.getAlbums())
        .map((album) => album.toMediaItem())
        .toList();
  }

  Future<List<MediaItem>> getPlaylists() async {
    final playlists = LibraryPlaylistsController.withInitialPlaylistsTail(
      (await _playlistRepository.getPlaylists()).reversed,
    ).map((e) => e.toMediaItem()).toList();
    return playlists;
  }

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
