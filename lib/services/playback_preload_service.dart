import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';

import '../domain/repositories/app_repositories.dart';
import '/models/hm_streaming_data.dart';
import '/services/constant.dart';
import '/services/playback_preload_manager.dart';
import '/services/preloaded_prefix_audio_source.dart';
import '/utils/helper.dart';

class PlaybackPreloadService {
  PlaybackPreloadService({
    required Directory preloadDirectory,
    required StreamInfoResolver resolveStreamInfo,
    required SettingsRepository settingsRepository,
    required SongCacheRepository songCacheRepository,
  }) : _manager = PlaybackPreloadManager(
         preloadDirectory: preloadDirectory,
         resolveStreamInfo: resolveStreamInfo,
         songCacheRepository: songCacheRepository,
       ),
       _settingsRepository = settingsRepository;

  final PlaybackPreloadManager _manager;
  final SettingsRepository _settingsRepository;
  Timer? _debounce;
  String? _lastWindowKey;

  Future<void> init() => _manager.init();

  bool get isEnabled {
    if (!GetPlatform.isAndroid) return false;
    return _playbackMode() == PlaybackMode.preloaded && range > 0;
  }

  int get range {
    return _settingsRepository.getPlaybackPreloadRange();
  }

  Future<void> setMode(PlaybackMode mode) async {
    await _settingsRepository.setPlaybackMode(mode);
    if (!isEnabled) await clear();
  }

  Future<void> setRange(int value) async {
    await _settingsRepository.setPlaybackPreloadRange(value);
    if (!isEnabled) await clear();
  }

  Future<HMStreamingData> streamInfoFor(
    MediaItem song, {
    required Future<HMStreamingData> Function() fallback,
    bool generateNewUrl = false,
  }) async {
    if (isEnabled && !generateNewUrl) {
      final preloaded = _manager.streamInfoFor(song.id);
      if (preloaded != null) {
        printINFO(
          "Using preloaded stream info (${song.id})",
          tag: LogTags.preload,
        );
        return preloaded;
      }
    }

    return fallback();
  }

  AudioSource? createAudioSource(
    MediaItem mediaItem, {
    required bool cacheSongsEnabled,
  }) {
    if (!isEnabled || cacheSongsEnabled) return null;

    final url = mediaItem.extras!['url'] as String;
    final preloadedPrefix = _manager.prefixForSync(mediaItem.id);
    if (preloadedPrefix == null ||
        preloadedPrefix.url != url ||
        !isPreloadableNetworkUrl(url)) {
      return null;
    }

    printINFO("Playing using preloaded prefix", tag: LogTags.preload);
    return PreloadedPrefixAudioSource(
      Uri.parse(url),
      prefixFile: preloadedPrefix.prefixFile,
      contentType: preloadedPrefix.contentType,
      sourceLength: preloadedPrefix.streamInfo.audio?.size == 0
          ? null
          : preloadedPrefix.streamInfo.audio?.size,
      tag: mediaItem,
    );
  }

  void schedule({
    required List<MediaItem> queue,
    required List<int> candidateIndices,
    required bool isPlaying,
    required int? currentIndex,
  }) {
    if (!isEnabled) {
      _debounce?.cancel();
      _lastWindowKey = null;
      unawaited(_manager.clear());
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _update(
        queue: queue,
        candidateIndices: candidateIndices,
        isPlaying: isPlaying,
        currentIndex: currentIndex,
      );
    });
  }

  void _update({
    required List<MediaItem> queue,
    required List<int> candidateIndices,
    required bool isPlaying,
    required int? currentIndex,
  }) {
    if (!isEnabled) {
      unawaited(clear());
      return;
    }

    final candidateIds = candidateIndices
        .where((index) => index >= 0 && index < queue.length)
        .map((index) => queue[index].id)
        .join(',');
    final windowKey = '$range|$isPlaying|$currentIndex|$candidateIds';
    if (windowKey == _lastWindowKey) return;
    _lastWindowKey = windowKey;

    unawaited(
      _manager.update(
        queue: queue,
        candidateIndices: candidateIndices,
        range: range,
        isPlaying: isPlaying,
        currentIndex: currentIndex,
      ),
    );
  }

  Future<void> clear() async {
    _debounce?.cancel();
    _lastWindowKey = null;
    await _manager.clear();
  }

  PlaybackMode _playbackMode() {
    return _settingsRepository.getPlaybackMode();
  }
}
