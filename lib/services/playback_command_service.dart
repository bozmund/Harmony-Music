import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../domain/repositories/settings_repository.dart';
import 'cloud/playback_modes.dart';
import 'cloud/cloud_playback_gateway.dart';
import 'local_playback_commands.dart';
import '../utils/helper.dart';
import 'constant.dart';
import 'playback_queue_order.dart';
import 'playback_video_id.dart';
import 'previous_track_policy.dart';

class PlaybackCommandService {
  PlaybackCommandService({
    required AudioHandler audioHandler,
    required SettingsRepository settingsRepository,
    CloudPlaybackGateway? cloudSync,
  }) : _audioHandler = audioHandler,
       _settingsRepository = settingsRepository,
       _cloudSync = cloudSync,
       local = LocalPlaybackCommands(
         audioHandler: audioHandler,
         settingsRepository: settingsRepository,
       );

  /// Non-forwarding view of this device's own player.
  ///
  /// Every method on this service forks on [_remoteTargetDeviceId] — correct for
  /// user input, wrong for anything that arrived *from* the network, which would
  /// otherwise be bounced back to the peer. The cloud receiver uses this instead.
  final LocalPlaybackCommands local;

  final AudioHandler _audioHandler;
  final SettingsRepository _settingsRepository;
  final CloudPlaybackGateway? _cloudSync;
  String? _remoteTargetDeviceId;
  List<MediaItem> _remoteQueue = const [];
  String? _remoteCurrentVideoId;
  final StreamController<String?> _localSongSelections =
      StreamController<String?>.broadcast(sync: true);
  final StreamController<CloudPlaybackModes> _localModeChanges =
      StreamController<CloudPlaybackModes>.broadcast(sync: true);

  bool get isRemoteControlActive => _remoteTargetDeviceId != null;
  bool get isPlaying => _audioHandler.playbackState.value.playing;

  /// Songs selected through this device's UI while commands are staying local.
  ///
  /// The cloud receiver uses this explicit signal to cancel an older handoff or
  /// queue backfill before the local media-item event arrives. Inferring the
  /// selection from that later event is racy because a receiver-owned queue
  /// update can still be in flight at the same time.
  Stream<String?> get localSongSelections => _localSongSelections.stream;

  /// Player modes changed through this device's own UI.
  ///
  /// The cloud target listens to this separately from playback state because
  /// queue-loop has no audio_service field and therefore emits no media-session
  /// event of its own.
  Stream<CloudPlaybackModes> get localModeChanges => _localModeChanges.stream;

  /// Live progress, published over the socket on a tick.
  ///
  /// Carries `durationMs` and `publishedAtMs` so a controller can extrapolate
  /// position locally between samples instead of showing a bar that jumps once a
  /// second — or, as before, never moves at all because `total` was never sent.
  Map<String, Object?> progressFrame() => local.progressFrame();

  /// The durable session document (schema v2): ordered ids only, no per-song
  /// metadata. `queueRevision` lets the server reject an out-of-order write and
  /// lets peers skip re-resolving a queue they already hold.
  /// [queueVideoIds] overrides the video ids taken from [queue]. The cloud
  /// session is the
  /// authoritative queue; the local handler may hold only the song currently
  /// loaded, and publishing that would collapse the shared queue to one track.
  /// [currentVideoId] locates the playing song inside the ids actually being
  /// published. An index is only meaningful against the list it was computed
  /// from — pairing one list's index with another's ids is what made a handoff
  /// start the previously played song instead of the selected one.
  Map<String, Object?> sessionState({
    required List<MediaItem> queue,
    required int index,
    List<String>? queueVideoIds,
    String? currentVideoId,
  }) {
    final videoIds = queueVideoIds != null
        ? queueVideoIds.map(requirePlaybackVideoIdValue).toList()
        : queue.map(requirePlaybackVideoId).toList();
    final validatedCurrentVideoId = currentVideoId == null
        ? null
        : requirePlaybackVideoIdValue(currentVideoId);
    final located = validatedCurrentVideoId == null
        ? -1
        : videoIds.indexOf(validatedCurrentVideoId);
    final safeIndex = located >= 0
        ? located
        : (videoIds.isEmpty ? 0 : index.clamp(0, videoIds.length - 1));
    return {
      'schemaVersion': 2,
      // These server keys predate the explicit contract. Their values are
      // always YouTube video IDs, never generic entity/song identifiers.
      'queueIds': videoIds,
      'index': safeIndex,
      if (videoIds.isNotEmpty) 'currentSongId': videoIds[safeIndex],
      'shuffle': _settingsRepository.getShuffleModeEnabled(),
      'repeat': _settingsRepository.getLoopModeEnabled(),
      'queueLoop': _settingsRepository.getQueueLoopModeEnabled(),
      'queueRevision': ++_queueRevision,
    };
  }

  int _queueRevision = 0;

  /// Adopts a revision observed from the cloud so a later local write always
  /// sorts after it.
  void observeQueueRevision(int revision) {
    if (revision > _queueRevision) _queueRevision = revision;
  }

  void startRemoteControl(String targetDeviceId) {
    _remoteTargetDeviceId = targetDeviceId;
  }

  Future<String?> startSharedSession({
    required String targetDeviceId,
    required List<MediaItem> queue,
    required int index,
    required int positionMs,
    required bool playing,
    List<String>? queueVideoIds,
    String? currentVideoId,
  }) async {
    final cloud = _cloudSync;
    if (cloud == null || queue.isEmpty || index < 0 || index >= queue.length) {
      return null;
    }
    // The source is intentionally paused before this call by the UI. Cloud
    // stores ordered ids only; the target resolves both metadata and playable
    // media for itself.
    final state = sessionState(
      queue: queue,
      index: index,
      queueVideoIds: queueVideoIds,
      currentVideoId: currentVideoId,
    );
    final sessionId = await cloud.startPlaybackSession(
      targetDeviceId: targetDeviceId,
      state: {
        ...state,
        'positionMs': positionMs,
        'playing': playing,
        if (queue[index].duration != null)
          'initialDurationMs': queue[index].duration!.inMilliseconds,
      },
    );
    if (sessionId.isEmpty) return null;
    _remoteTargetDeviceId = targetDeviceId;
    _remoteQueue = List<MediaItem>.from(queue);
    _remoteCurrentVideoId = state['currentSongId']?.toString();
    return sessionId;
  }

  Future<void> switchSharedTarget(
    String targetDeviceId, {
    required List<MediaItem> queue,
    required int index,
    required int positionMs,
    required bool playing,
    List<String>? queueVideoIds,
    String? currentVideoId,
  }) async {
    final cloud = _cloudSync;
    if (cloud == null) return;
    final state = sessionState(
      queue: queue,
      index: index,
      queueVideoIds: queueVideoIds,
      currentVideoId: currentVideoId,
    );
    await cloud.switchPlaybackTarget(
      targetDeviceId: targetDeviceId,
      state: {...state, 'positionMs': positionMs, 'playing': playing},
    );
    _remoteTargetDeviceId = targetDeviceId;
    _remoteQueue = List<MediaItem>.from(queue);
    _remoteCurrentVideoId = state['currentSongId']?.toString();
  }

  void stopRemoteControl() {
    _remoteTargetDeviceId = null;
    _remoteQueue = const [];
    _remoteCurrentVideoId = null;
  }

  Future<void> play() => _sendRemoteOrLocal('play', _audioHandler.play);

  Future<void> pause() => _sendRemoteOrLocal('pause', _audioHandler.pause);

  /// Normal controls treat Stop as Pause so playback can resume at its
  /// current position. Lifecycle teardown uses [AudioHandler.stop] directly.
  Future<void> stop() => pause();

  Future<void> seek(Duration position) => _sendRemoteOrLocal(
    'seek',
    () => _audioHandler.seek(position),
    {'positionMs': position.inMilliseconds},
  );

  Future<void> next({String? desiredVideoId}) async {
    final target = _remoteTargetDeviceId;
    if (target == null || _cloudSync == null) {
      _localSongSelections.add(null);
      await _audioHandler.skipToNext();
      return;
    }
    await _sendRemoteCommand('next', {
      if (desiredVideoId != null) 'desiredVideoId': desiredVideoId,
    });
    if (desiredVideoId != null) _remoteCurrentVideoId = desiredVideoId;
  }

  Future<void> previous({
    PreviousTrackIntent? remoteIntent,
    String? desiredVideoId,
  }) async {
    final target = _remoteTargetDeviceId;
    if (target == null || _cloudSync == null) {
      _localSongSelections.add(desiredVideoId);
      await _audioHandler.skipToPrevious();
      return;
    }
    await _sendRemoteCommand('previous', {
      if (remoteIntent != null) 'intent': remoteIntent.name,
      if (desiredVideoId != null) 'desiredVideoId': desiredVideoId,
    });
    if (desiredVideoId != null) _remoteCurrentVideoId = desiredVideoId;
  }

  Future<void> playPause({required bool isPlaying}) {
    return _sendRemoteOrLocal(
      'playPause',
      () => isPlaying ? _audioHandler.pause() : _audioHandler.play(),
    );
  }

  Future<void> playByIndex(
    int index, {
    int? position,
    bool restoreSession = false,
    bool generateNewUrl = false,
  }) async {
    final target = _remoteTargetDeviceId;
    if (target != null) {
      if (index < 0 || index >= _remoteQueue.length) return;
      await _sendRemoteHandoff(
        target,
        _remoteQueue,
        index,
        position ?? 0,
        origin: 'playByIndex',
      );
      return;
    }
    final queue = _audioHandler.queue.value;
    _localSongSelections.add(
      index >= 0 && index < queue.length ? queue[index].id : null,
    );
    return _audioHandler.customAction("playByIndex", {
      "index": index,
      if (position != null) "position": position,
      if (restoreSession) "restoreSession": true,
      if (generateNewUrl) "newUrl": true,
    });
  }

  /// While synced, everything on the mirrored UI drives the remote target —
  /// picking a song plays it THERE, like any cast UX. Leaving the session is an
  /// explicit act: the "Leave sync" button in the devices sheet.
  Future<void> setSourceAndPlay(MediaItem mediaItem) {
    final target = _remoteTargetDeviceId;
    if (target != null) {
      final remoteIndex = _remoteQueue.indexWhere(
        (item) => item.id == mediaItem.id,
      );
      final queue = remoteIndex < 0 ? [mediaItem] : _remoteQueue;
      return _sendRemoteHandoff(
        target,
        queue,
        remoteIndex < 0 ? 0 : remoteIndex,
        0,
        origin: 'setSourceAndPlay',
      );
    }
    _localSongSelections.add(mediaItem.id);
    return _audioHandler.customAction("setSourceNPlay", {
      "mediaItem": mediaItem,
    });
  }

  Future<void> updateQueue(List<MediaItem> queue) {
    if (_remoteTargetDeviceId != null) {
      _remoteQueue = List<MediaItem>.from(queue);
      return _sendRemoteQueue();
    }
    return _audioHandler.updateQueue(queue);
  }

  Future<void> _sendRemoteOrLocal(
    String type,
    Future<void> Function() local, [
    Map<String, Object?> payload = const {},
  ]) async {
    final target = _remoteTargetDeviceId;
    if (target == null || _cloudSync == null) {
      await local();
      return;
    }
    await _cloudSync.sendSessionCommand(
      targetDeviceId: target,
      type: type,
      payload: payload,
    );
  }

  Future<void> _sendRemoteHandoff(
    String targetDeviceId,
    List<MediaItem> queue,
    int index,
    int positionMs, {
    required String origin,
  }) async {
    final cloud = _cloudSync;
    if (cloud == null) return;
    final state = sessionState(queue: queue, index: index);
    // One tap must produce one handoff. A duplicate restarts the track on the
    // target, and the two call sites are indistinguishable from the target's
    // side - both arrive as a plain 'handoff' command - so name the origin
    // here, where it is still known.
    printINFO(
      'remote handoff origin=$origin song=${state['currentSongId']} '
      'index=$index positionMs=$positionMs queue=${queue.length}',
      tag: LogTags.cloudPlayback,
    );
    // Ids only: the target resolves the song itself, usually straight from its
    // own cache. Sending the whole queue keeps next/previous working there.
    await cloud.sendSessionCommand(
      targetDeviceId: targetDeviceId,
      type: 'handoff',
      payload: {
        ...state,
        'positionMs': positionMs,
        'playing': true,
        if (queue[index].duration != null)
          'initialDurationMs': queue[index].duration!.inMilliseconds,
      },
    );
    _remoteQueue = List<MediaItem>.from(queue);
    _remoteCurrentVideoId = state['currentSongId']?.toString();
  }

  Future<void> addQueueItem(MediaItem mediaItem) {
    if (_remoteTargetDeviceId != null) {
      _remoteQueue = [..._remoteQueue, mediaItem];
      return _sendRemoteQueue();
    }
    return _audioHandler.addQueueItem(mediaItem);
  }

  Future<void> addQueueItems(List<MediaItem> mediaItems) {
    if (_remoteTargetDeviceId != null) {
      _remoteQueue = [..._remoteQueue, ...mediaItems];
      return _sendRemoteQueue();
    }
    return _audioHandler.addQueueItems(mediaItems);
  }

  Future<void> removeQueueItem(MediaItem mediaItem) {
    if (_remoteTargetDeviceId != null) {
      _remoteQueue = _remoteQueue
          .where((song) => song.id != mediaItem.id)
          .toList();
      return _sendRemoteQueue();
    }
    return _audioHandler.removeQueueItem(mediaItem);
  }

  Future<void> clearQueue() {
    if (_remoteTargetDeviceId != null) {
      _remoteQueue = const [];
      return _sendRemoteQueue();
    }
    return _audioHandler.customAction("clearQueue");
  }

  Future<void> shuffleQueue() {
    if (_remoteTargetDeviceId != null)
      return _sendRemoteCommand('shuffleQueue');
    return _audioHandler.customAction("shuffleQueue");
  }

  Future<void> reorderQueue({
    required int oldIndex,
    required int newIndex,
    List<MediaItem>? remoteQueue,
    String? currentVideoId,
  }) {
    if (_remoteTargetDeviceId != null) {
      if (remoteQueue != null) {
        _remoteQueue = List<MediaItem>.from(remoteQueue);
      }
      if (currentVideoId != null) {
        _remoteCurrentVideoId = currentVideoId;
      }
      if (oldIndex < 0 ||
          oldIndex >= _remoteQueue.length ||
          newIndex < 0 ||
          newIndex > _remoteQueue.length) {
        return Future<void>.value();
      }
      final reordered = List<MediaItem>.from(_remoteQueue);
      final item = reordered.removeAt(oldIndex);
      final adjustedNewIndex = oldIndex < newIndex ? newIndex - 1 : newIndex;
      reordered.insert(adjustedNewIndex, item);
      _remoteQueue = reordered;
      return _sendRemoteQueue();
    }
    return _audioHandler.customAction("reorderQueue", {
      "oldIndex": oldIndex,
      "newIndex": newIndex,
    });
  }

  Future<void> addPlayNextItem(
    MediaItem mediaItem, {
    List<MediaItem>? remoteQueue,
    String? currentVideoId,
  }) {
    if (_remoteTargetDeviceId != null) {
      if (remoteQueue != null) {
        _remoteQueue = List<MediaItem>.from(remoteQueue);
      }
      if (currentVideoId != null) {
        _remoteCurrentVideoId = currentVideoId;
      }
      final currentIndex = _remoteQueue.indexWhere(
        (song) => song.id == _remoteCurrentVideoId,
      );
      final insertionIndex = currentIndex < 0 ? 1 : currentIndex + 1;
      _remoteQueue = [
        ..._remoteQueue.take(insertionIndex),
        mediaItem,
        ..._remoteQueue.skip(insertionIndex),
      ];
      return _sendRemoteQueue();
    }
    return _audioHandler.customAction("addPlayNextItem", {
      "mediaItem": mediaItem,
    });
  }

  Future<void> shuffleFromIndex(int index) {
    if (_remoteTargetDeviceId != null) {
      if (index < 0 || index >= _remoteQueue.length) {
        return Future<void>.value();
      }
      _remoteQueue = PlaybackQueueOrder.shuffledFromCurrent(
        _remoteQueue,
        index,
      );
      _remoteCurrentVideoId = _remoteQueue.first.id;
      return _sendRemoteQueue();
    }
    return _audioHandler.customAction("shuffleCmd", {"index": index});
  }

  Future<bool> toggleShuffle({required bool enabled}) async {
    final nextEnabled = !enabled;
    if (_remoteTargetDeviceId != null) {
      await _sendRemoteCommand('shuffleMode', {'enabled': nextEnabled});
      await _settingsRepository.setShuffleModeEnabled(nextEnabled);
      return nextEnabled;
    }
    await _audioHandler.setShuffleMode(
      nextEnabled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    );
    await _settingsRepository.setShuffleModeEnabled(nextEnabled);
    _localModeChanges.add(local.playbackModes);
    return nextEnabled;
  }

  Future<bool> toggleLoop({required bool enabled}) async {
    final nextEnabled = !enabled;
    if (_remoteTargetDeviceId != null) {
      await _sendRemoteCommand('repeatMode', {'enabled': nextEnabled});
      await _settingsRepository.setLoopModeEnabled(nextEnabled);
      return nextEnabled;
    }
    await _audioHandler.setRepeatMode(
      nextEnabled ? AudioServiceRepeatMode.one : AudioServiceRepeatMode.none,
    );
    await _settingsRepository.setLoopModeEnabled(nextEnabled);
    _localModeChanges.add(local.playbackModes);
    return nextEnabled;
  }

  Future<void> setQueueLoopMode(bool enabled) async {
    if (_remoteTargetDeviceId != null) {
      await _sendRemoteCommand('queueLoopMode', {'enabled': enabled});
      await _settingsRepository.setQueueLoopModeEnabled(enabled);
      return;
    }
    await _audioHandler.customAction("toggleQueueLoopMode", {
      "enable": enabled,
    });
    await _settingsRepository.setQueueLoopModeEnabled(enabled);
    _localModeChanges.add(local.playbackModes);
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
    if (_remoteTargetDeviceId != null) {
      return _sendRemoteCommand('volume', {'value': value});
    }
    return _audioHandler.customAction("setVolume", {"value": value});
  }

  Future<void> _sendRemoteQueue() async {
    final state = sessionState(
      queue: _remoteQueue,
      index: 0,
      currentVideoId: _remoteCurrentVideoId,
    );
    await _sendRemoteCommand('queueUpdate', state);
    _remoteCurrentVideoId = state['currentSongId']?.toString();
  }

  Future<void> _sendRemoteCommand(
    String type, [
    Map<String, Object?> payload = const {},
  ]) async {
    final cloud = _cloudSync;
    final target = _remoteTargetDeviceId;
    if (cloud == null || target == null) return;
    await cloud.sendSessionCommand(
      targetDeviceId: target,
      type: type,
      payload: payload,
    );
  }
}
