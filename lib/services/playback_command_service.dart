import 'package:audio_service/audio_service.dart';

import '../domain/repositories/settings_repository.dart';

class PlaybackCommandService {
  PlaybackCommandService({
    required AudioHandler audioHandler,
    required SettingsRepository settingsRepository,
  }) : _audioHandler = audioHandler,
       _settingsRepository = settingsRepository;

  final AudioHandler _audioHandler;
  final SettingsRepository _settingsRepository;

  Future<void> play() => _audioHandler.play();

  Future<void> pause() => _audioHandler.pause();

  Future<void> stop() => _audioHandler.stop();

  Future<void> seek(Duration position) => _audioHandler.seek(position);

  Future<void> next() => _audioHandler.skipToNext();

  Future<void> previous() => _audioHandler.skipToPrevious();

  Future<void> playPause({required bool isPlaying}) {
    return isPlaying ? pause() : play();
  }

  Future<void> playByIndex(
    int index, {
    int? position,
    bool restoreSession = false,
    bool generateNewUrl = false,
  }) {
    return _audioHandler.customAction("playByIndex", {
      "index": index,
      if (position != null) "position": position,
      if (restoreSession) "restoreSession": true,
      if (generateNewUrl) "newUrl": true,
    });
  }

  Future<void> setSourceAndPlay(MediaItem mediaItem) {
    return _audioHandler.customAction("setSourceNPlay", {
      "mediaItem": mediaItem,
    });
  }

  Future<void> updateQueue(List<MediaItem> queue) {
    return _audioHandler.updateQueue(queue);
  }

  Future<void> addQueueItem(MediaItem mediaItem) {
    return _audioHandler.addQueueItem(mediaItem);
  }

  Future<void> addQueueItems(List<MediaItem> mediaItems) {
    return _audioHandler.addQueueItems(mediaItems);
  }

  Future<void> removeQueueItem(MediaItem mediaItem) {
    return _audioHandler.removeQueueItem(mediaItem);
  }

  Future<void> clearQueue() {
    return _audioHandler.customAction("clearQueue");
  }

  Future<void> shuffleQueue() {
    return _audioHandler.customAction("shuffleQueue");
  }

  Future<void> reorderQueue({required int oldIndex, required int newIndex}) {
    return _audioHandler.customAction("reorderQueue", {
      "oldIndex": oldIndex,
      "newIndex": newIndex,
    });
  }

  Future<void> addPlayNextItem(MediaItem mediaItem) {
    return _audioHandler.customAction("addPlayNextItem", {
      "mediaItem": mediaItem,
    });
  }

  Future<void> shuffleFromIndex(int index) {
    return _audioHandler.customAction("shuffleCmd", {"index": index});
  }

  Future<bool> toggleShuffle({required bool enabled}) async {
    final nextEnabled = !enabled;
    await _audioHandler.setShuffleMode(
      nextEnabled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    );
    await _settingsRepository.setShuffleModeEnabled(nextEnabled);
    return nextEnabled;
  }

  Future<bool> toggleLoop({required bool enabled}) async {
    final nextEnabled = !enabled;
    await _audioHandler.setRepeatMode(
      nextEnabled ? AudioServiceRepeatMode.one : AudioServiceRepeatMode.none,
    );
    await _settingsRepository.setLoopModeEnabled(nextEnabled);
    return nextEnabled;
  }

  Future<void> setQueueLoopMode(bool enabled) async {
    await _audioHandler.customAction("toggleQueueLoopMode", {
      "enable": enabled,
    });
    await _settingsRepository.setQueueLoopModeEnabled(enabled);
  }

  Future<void> toggleSkipSilence(bool enable) {
    return _audioHandler.customAction("toggleSkipSilence", {"enable": enable});
  }

  Future<void> toggleLoudnessNormalization(bool enable) {
    return _audioHandler.customAction("toggleLoudnessNormalization", {
      "enable": enable,
    });
  }

  Future<void> setVolume(int value) {
    return _audioHandler.customAction("setVolume", {"value": value});
  }
}
