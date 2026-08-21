import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../../models/media_Item_builder.dart';
import '../../utils/helper.dart';
import '../constant.dart';
import '../crash_diagnostics_service.dart';
import '../local_playback_commands.dart';
import '../metadata/playback_metadata_resolver.dart';
import '../playback_command_service.dart';
import '../previous_track_policy.dart';
import '../../ui/player/player_controller.dart';
import 'cloud_playback_gateway.dart';
import 'playback_modes.dart';
import 'playback_socket_client.dart';

/// Applies account playback commands while Harmony is running.
///
/// Sessions carry ordered video ids only; each device resolves its own metadata
/// and its own playable media.
///
/// Commands arrive over a WebSocket, but the socket is not the only delivery
/// path: a push to a device that is not currently connected reaches nobody, and
/// Windows has no FCM to be woken by. So every connect also drains any commands
/// queued while this device was away.
class CloudPlaybackReceiver {
  CloudPlaybackReceiver(
    this._cloud,
    this._metadata,
    this._commands,
    this._socket, [
    this._player,
  ]);

  final CloudPlaybackGateway _cloud;
  final PlaybackMetadataResolver _metadata;
  final PlaybackCommandService _commands;
  final PlaybackSocketTransport _socket;
  final PlayerController? _player;

  /// Applying a command must never route back out to the network — see
  /// [LocalPlaybackCommands].
  LocalPlaybackCommands get _local => _commands.local;

  StreamSubscription<Map<String, dynamic>>? _frames;
  StreamSubscription<PlaybackSocketStatus>? _status;
  StreamSubscription<List<MediaItem>>? _localQueue;
  StreamSubscription<MediaItem?>? _localSong;
  StreamSubscription<String?>? _localSelection;
  StreamSubscription<PlaybackState>? _localPlaybackState;
  StreamSubscription<CloudPlaybackModes>? _localModeChanges;
  Timer? _progressTimer;
  Timer? _statePublishDebounce;

  /// Session this device has already begun playing as the audio target, so a
  /// repeated snapshot does not restart playback.
  String? _appliedTargetSessionId;
  int _appliedQueueRevision = -1;
  bool _isAudioTarget = false;
  int _targetPlaybackGeneration = 0;
  CloudPlaybackModes _sessionModes = const CloudPlaybackModes();
  CloudPlaybackModes? _lastObservedLocalModes;
  String? _lastRequestedNextSongId;

  /// Bumped every time this device decides its own role.
  ///
  /// Reading the session is a network round trip, and a `handoff` command can be
  /// applied while that read is in flight — [start] drains pending commands
  /// alongside it, and the socket's connect handler drains again. The response
  /// then describes the world as it was *before* this device became the audio
  /// target, and [_applySession] reads it as "someone else owns the audio" and
  /// switches this device to mirroring. Nothing stops the audio it already
  /// started, so the song plays while the mirror gate silently discards every
  /// local player event: the title and artist shimmer forever even though the
  /// resolved song is sitting in this device's own handler.
  int _roleGeneration = 0;

  /// Non-zero while this device is installing a session's queue locally, during
  /// which its own queue events must not be published back as durable state.
  int _applyingSessionQueue = 0;

  /// Commands already applied. The socket replays on connect and the REST drain
  /// covers a cold start, so the same command can legitimately arrive twice.
  final Set<String> _appliedCommandIds = {};

  String? _lastFrameReceived;
  DateTime? _lastFrameReceivedAt;
  String? _lastAppliedCommandId;

  /// How often the audio target publishes progress. Controllers extrapolate
  /// between these samples, so this is a correction rate, not a render rate.
  static const progressInterval = Duration(seconds: 2);

  /// Durable state is a Postgres write, so coalesce bursts (a skip fires both a
  /// queue and a media-item event) instead of writing per change.
  static const _statePublishDebounce_ = Duration(milliseconds: 750);

  Future<void> start() async {
    if (_frames != null) return;
    _player?.cloudReceiverDiagnostics = diagnostics;
    _frames = _socket.frames.listen(_onFrame);
    _status = _socket.status.listen((status) {
      _player?.setCloudSocketStatus(status);
      if (status == PlaybackSocketStatus.connected) {
        // Reconnect: anything queued while we were gone is still pending.
        unawaited(_drainPendingCommands());
      } else {
        _stopProgressPublishing();
      }
    });
    _watchLocalPlaybackForPublication();
    await _socket.connect(_cloud.deviceId);
    await _refreshSession();
    await _drainPendingCommands();
  }

  /// Whether this device has opted into the account session, either as the
  /// audio target (accepted a handoff) or as the controller (initiated one).
  /// Everyone else ignores session traffic and keeps playing independently —
  /// devices are only synced when the user explicitly syncs them.
  bool get _isEngaged => _isAudioTarget || _commands.isRemoteControlActive;

  /// Surfaced for the "Leave sync" affordance in the devices sheet.
  bool get isEngaged => _isEngaged;

  /// The explicit "Leave sync" action.
  ///
  /// Ends the shared session for every participant, while whichever device was
  /// producing audio is paused as part of the disconnect. Leaving only on a
  /// controller used to leave the server's target marker behind, so the devices
  /// sheet kept reporting the old target as "Playing here" after sync ended.
  Future<void> leaveSync() async {
    final wasRemoteController = _commands.isRemoteControlActive;
    if (wasRemoteController) {
      try {
        // Send this while routing still points at the target. The subsequent
        // session-ended frame also pauses it, covering either delivery order.
        await _commands.pause();
      } catch (error, stackTrace) {
        CrashDiagnosticsService.instance.record(
          'cloud-playback',
          'Unable to pause the remote target while leaving sync',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    await _pauseLocalForSyncEnd(preserveMirroredPosition: wasRemoteController);
    _roleGeneration++;
    _targetPlaybackGeneration++;
    _isAudioTarget = false;
    _stopProgressPublishing();
    _statePublishDebounce?.cancel();
    _commands.stopRemoteControl();
    await _player?.clearRemoteSessionState();
    _appliedTargetSessionId = null;
    _appliedQueueIds = null;
    _targetSongIdOverride = null;
    _targetLoadingPositionMs = null;
    _targetLoadingDurationMs = null;
    _sessionModes = const CloudPlaybackModes();
    try {
      await _cloud.endPlaybackSession();
    } catch (error, stackTrace) {
      CrashDiagnosticsService.instance.record(
        'cloud-playback',
        'Unable to end the playback session while leaving sync',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _pauseLocalForSyncEnd({
    bool preserveMirroredPosition = false,
  }) async {
    try {
      // Restore the phone's parked local media session before issuing local
      // seek/pause calls. While the notification mirror is active those
      // transport calls intentionally route to the remote target.
      await _player?.clearRemoteMediaNotification();
      if (preserveMirroredPosition) {
        await _adoptMirroredSongLocally();
        await _applyModesToLocalPlayer(_sessionModes, preserveQueueOrder: true);
      }
      await _local.pause();
    } catch (error, stackTrace) {
      CrashDiagnosticsService.instance.record(
        'cloud-playback',
        'Unable to pause local playback while leaving sync',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Carries the session's song onto this device as sync ends.
  ///
  /// A controller never touches its own audio engine while mirroring, so its
  /// handler stays parked on whatever was playing when the handoff began — and
  /// [PlayerController.clearRemoteSessionState] rebuilds the UI from exactly
  /// that. Leaving sync therefore used to teleport the user back to the
  /// pre-sync song. Where the music was is what should survive; whether it was
  /// playing here or there is an implementation detail the user never asked
  /// about.
  Future<void> _adoptMirroredSongLocally() async {
    final player = _player;
    if (player == null) return;
    final mirroredSong = player.currentSong.value;
    // Nothing worth adopting if the session never resolved a real song.
    if (mirroredSong == null || MediaItemBuilder.isResolving(mirroredSong)) {
      return;
    }
    final position = player.progressBarStatus.value.current;
    if (_local.currentSong?.id == mirroredSong.id) {
      // Right song already loaded — just move it to where the session got to,
      // otherwise 1:46 visibly snaps back to 0:23.
      await _local.seek(position);
      return;
    }
    final mirroredQueue = List<MediaItem>.from(player.currentQueue);
    final index = mirroredQueue.indexWhere(
      (item) => item.id == mirroredSong.id,
    );
    final queue = index < 0 ? [mirroredSong] : mirroredQueue;
    await _local.updateQueue(queue);
    // restoreSession: prepare and seek without resuming. Leaving sync pauses,
    // so starting playback here only to stop it again would leak a blip of
    // audio out of a device the user just disconnected.
    await _local.playByIndex(
      index < 0 ? 0 : index,
      position: position.inMilliseconds,
      restoreSession: true,
    );
  }

  /// Seeds the controller mirror right after THIS device handed audio away.
  ///
  /// A brand-new session's persisted progress columns are still zero, so
  /// waiting for the server round trip briefly showed a bar reset to 0:00 and
  /// a paused button. Everything needed for a correct mirror — the queue that
  /// was just on screen, the song, the position — is already local; use it.
  void adoptInitiatedHandoff({
    required List<MediaItem> queue,
    required List<String> queueIds,
    required String currentSongId,
    required int positionMs,
  }) {
    _roleGeneration++;
    _isAudioTarget = false;
    _stopProgressPublishing();
    _statePublishDebounce?.cancel();
    _appliedTargetSessionId = null;
    _appliedQueueIds = List<String>.unmodifiable(queueIds);
    _sessionModes = _local.playbackModes;
    final player = _player;
    if (player == null) return;
    player.applyRemotePlaybackModes(_sessionModes);
    final byId = {for (final item in queue) item.id: item};
    final items = [
      for (final id in queueIds) byId[id] ?? MediaItemBuilder.placeholder(id),
    ];
    final index = queueIds.indexOf(currentSongId);
    player.applyRemoteQueue(
      items,
      index: index < 0 ? 0 : index,
      positionMs: positionMs,
      durationMs: byId[currentSongId]?.duration?.inMilliseconds,
      // The whole point of the handoff is that music continues over there;
      // show a pause button, not a spinner or a stale paused state.
      playing: true,
    );
    if (items.any(MediaItemBuilder.isResolving)) {
      unawaited(_backfill(queueIds));
    }
  }

  /// Fetches commands queued while this device had no live socket. Without this
  /// a handoff created while the target was offline is lost permanently.
  Future<void> _drainPendingCommands() async {
    try {
      for (final command in await _cloud.pendingPlaybackCommands()) {
        await _applyDeliveredCommand(
          commandId: command.commandId,
          type: command.type,
          payload: command.payload,
          ackOverSocket: false,
        );
      }
    } catch (error, stackTrace) {
      CrashDiagnosticsService.instance.record(
        'cloud-playback',
        'Unable to drain pending playback commands',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Re-reads the active session from the cloud.
  ///
  /// Called by the devices sheet right after this device initiates a handoff:
  /// the server's snapshot broadcast can race the HTTP response that flips this
  /// device into controller mode, and a disengaged device ignores snapshots.
  Future<void> refreshSession() => _refreshSession();

  Future<void> _refreshSession() async {
    final generation = _roleGeneration;
    try {
      final session = await _cloud.playbackSession();
      // This device changed role while the read was in flight, so the answer
      // describes a world that no longer exists — see [_roleGeneration].
      if (generation != _roleGeneration) return;
      if (session == null) {
        await _onSessionEnded();
      } else {
        await _applySession(
          sessionId: session.sessionId,
          targetDeviceId: session.targetDeviceId,
          state: session.state,
          positionMs: session.positionMs,
          durationMs: session.durationMs,
          playing: session.playing,
        );
      }
    } catch (error, stackTrace) {
      CrashDiagnosticsService.instance.record(
        'cloud-playback',
        'Unable to read the active playback session',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _onFrame(Map<String, dynamic> frame) {
    _lastFrameReceived = frame['type']?.toString();
    _lastFrameReceivedAt = DateTime.now();
    // Progress ticks twice a second and would drown the log; everything else is
    // rare and is exactly what you need to see to explain a session that did
    // not do what the user expected.
    if (frame['type'] != 'progress') {
      printINFO(
        'frame ${frame['type']} target=${frame['targetDeviceId']} '
        'command=${frame['commandType']} engaged=$_isEngaged '
        'isTarget=$_isAudioTarget',
        tag: LogTags.cloudPlayback,
      );
    }
    switch (frame['type']) {
      case 'sessionSnapshot':
        unawaited(
          _applySession(
            sessionId: frame['sessionId'].toString(),
            targetDeviceId: frame['targetDeviceId'].toString(),
            state: Map<String, dynamic>.from(
              frame['state'] as Map? ?? const {},
            ),
            // The snapshot carries the last persisted progress; without it a
            // device joining mid-session cannot tell whether to be playing.
            positionMs: (frame['positionMs'] as num?)?.toInt() ?? 0,
            durationMs: (frame['durationMs'] as num?)?.toInt(),
            playing: frame['playing'] == true,
          ),
        );
      case 'progress':
        // Only a device that is mirroring follows the target's position.
        // Applying these while independent would hijack the local UI: the
        // player controller treats any remote progress as "enter mirror mode".
        if (_commands.isRemoteControlActive) {
          _player?.applyRemoteProgress(frame);
        }
      case 'command':
        unawaited(
          _applyDeliveredCommand(
            commandId: frame['commandId']?.toString(),
            type: frame['commandType']?.toString() ?? '',
            payload: Map<String, dynamic>.from(
              frame['payload'] as Map? ?? const {},
            ),
            ackOverSocket: true,
          ),
        );
      case 'sessionEnded':
        unawaited(_onSessionEnded());
    }
  }

  Future<void> _onSessionEnded() async {
    final wasEngaged = _isEngaged;
    final wasRemoteController = _commands.isRemoteControlActive;
    if (wasEngaged) {
      await _pauseLocalForSyncEnd(
        preserveMirroredPosition: wasRemoteController,
      );
    }
    _roleGeneration++;
    _targetPlaybackGeneration++;
    _isAudioTarget = false;
    _stopProgressPublishing();
    _statePublishDebounce?.cancel();
    _commands.stopRemoteControl();
    await _player?.clearRemoteSessionState();
    _appliedTargetSessionId = null;
    _targetSongIdOverride = null;
    _targetLoadingPositionMs = null;
    _targetLoadingDurationMs = null;
    _appliedQueueRevision = -1;
    _appliedQueueIds = null;
    _sessionModes = const CloudPlaybackModes();
  }

  Future<void> _applySession({
    required String sessionId,
    required String targetDeviceId,
    required Map<String, dynamic> state,
    int positionMs = 0,
    int? durationMs,
    bool playing = false,
  }) async {
    // Always observed, even while independent: if this device later initiates
    // a handoff, its first durable write must sort after the cloud's revision.
    _commands.observeQueueRevision(_revisionOf(state));
    final incomingModes = CloudPlaybackModes.fromMap(state);
    if (incomingModes.hasAny) {
      _sessionModes = _sessionModes.merge(incomingModes);
    }

    // Session traffic only concerns devices that opted in. A device that never
    // accepted or initiated a handoff keeps playing its own music untouched —
    // sync happens when the user syncs, not whenever a session exists.
    if (!_isEngaged) return;

    if (targetDeviceId != _cloud.deviceId) {
      // Another device owns the audio: act as a controller mirroring its state.
      _isAudioTarget = false;
      _stopProgressPublishing();
      _commands.startRemoteControl(targetDeviceId);
      _player?.applyRemotePlaybackModes(incomingModes);
      await _mirrorQueue(state, positionMs, durationMs, playing);
      // Becoming the target again must re-apply the session from scratch.
      _appliedTargetSessionId = null;
      return;
    }

    // Only a handoff command makes this device the target. A snapshot naming us
    // (say, from a session predating an app restart) must not start audio.
    if (!_isAudioTarget) return;

    await _becomeAudioTarget();
    await _applyModesToLocalPlayer(incomingModes, preserveQueueOrder: true);
    // Publishing must not wait on the audio load: a controller with no progress
    // frames shows a dead UI.
    _startProgressPublishing();
    // A start-session handoff arrives as a command before its durable snapshot.
    // The command has no session id, so it claims the temporary handoff latch.
    // When the matching snapshot follows, adopt its real id instead of treating
    // the same queue/song as a second playback request.
    if (_appliedTargetSessionId == _handoffSessionId &&
        _matchesAppliedHandoff(state)) {
      _appliedTargetSessionId = sessionId;
    }
    if (_appliedTargetSessionId != sessionId) {
      await _startSessionPlayback(
        sessionId,
        state,
        positionMs: positionMs,
        playing: playing,
      );
    }
  }

  /// Starts playback for a session exactly once.
  ///
  /// The latch is claimed *before* awaiting, and concurrent callers join the
  /// running attempt. Setting it afterwards meant every snapshot that arrived
  /// while the first load was still in flight re-entered playback and cancelled
  /// that load — five playback generations deep, the track never finished
  /// loading and the spinner never cleared.
  Future<void> _startSessionPlayback(
    String sessionId,
    Map<String, dynamic> state, {
    required int positionMs,
    required bool playing,
    bool isExplicitHandoff = false,
  }) {
    final requestKey = _playbackStartKey(sessionId, state);
    final inFlight = _startingPlayback;
    if (inFlight != null && _startingPlaybackKey == requestKey) {
      return inFlight;
    }
    if (inFlight != null) {
      // A new explicit handoff must not be queued behind a source that is
      // stalled resolving or loading. The in-flight operation notices the
      // generation change at each async boundary and cannot overwrite this
      // newer selection when it eventually settles.
      _targetPlaybackGeneration++;
    }

    _appliedTargetSessionId = sessionId;
    final operation =
        _startPlayback(
          state,
          positionMs: positionMs,
          playing: playing,
          isExplicitHandoff: isExplicitHandoff,
        ).catchError((Object error, StackTrace stackTrace) {
          // Release the latch so a later snapshot retries resolution.
          if (_startingPlaybackKey == requestKey) {
            _appliedTargetSessionId = null;
          }
          CrashDiagnosticsService.instance.record(
            'cloud-playback',
            'Failed to start playback for incoming session',
            error: error,
            stackTrace: stackTrace,
            flush: true,
          );
        });
    _startingPlayback = operation;
    _startingPlaybackKey = requestKey;
    _publishProgressFrame();
    return operation.whenComplete(() {
      if (identical(_startingPlayback, operation)) {
        _startingPlayback = null;
        _startingPlaybackKey = null;
      }
    });
  }

  Future<void>? _startingPlayback;
  String? _startingPlaybackKey;

  String _playbackStartKey(String sessionId, Map<String, dynamic> state) {
    final queueIds = _queueIdsOf(state);
    final index = _indexOf(state, queueIds.length);
    return '$sessionId|${queueIds.join('|')}|$index';
  }

  String? _targetSongIdOverride;
  int? _targetLoadingPositionMs;
  int? _targetLoadingDurationMs;
  bool _targetLoadingPlaying = true;

  /// A handoff command carries no session id, but claiming the latch still stops
  /// a concurrent snapshot from starting playback a second time.
  static const _handoffSessionId = 'handoff';

  /// How long to wait for the audio source to settle before carrying on.
  static const _playbackStartTimeout = Duration(seconds: 12);

  /// Backstop on resolving the handed-off song's metadata. The metadata service
  /// bounds itself; this bounds the receiver against whatever it does not.
  static const _metadataResolveTimeout = Duration(seconds: 20);

  /// Leaves controller mode before doing anything else. Producing audio and
  /// controlling a peer are mutually exclusive; staying in controller mode while
  /// acting as the target is what lets local playback leak back onto the wire.
  Future<void> _becomeAudioTarget() async {
    _roleGeneration++;
    _isAudioTarget = true;
    _commands.stopRemoteControl();
    await _player?.clearRemoteSessionState();
  }

  /// Controller side: show the whole queue immediately using placeholders, then
  /// fill in real metadata as it resolves.
  Future<void> _mirrorQueue(
    Map<String, dynamic> state,
    int positionMs,
    int? durationMs,
    bool playing,
  ) async {
    final player = _player;
    if (player == null) return;
    final queueIds = _queueIdsOf(state);
    if (queueIds.isEmpty) return;
    final revision = _revisionOf(state);
    final index = _indexOf(state, queueIds.length);
    final modes = CloudPlaybackModes.fromMap(state);
    if (modes.hasAny) {
      _sessionModes = _sessionModes.merge(modes);
      player.applyRemotePlaybackModes(modes);
    }

    _appliedQueueRevision = revision;
    // Compare ids, not the revision. The target bumps the revision every time it
    // skips a track, and rebuilding on that would throw away the metadata we
    // already resolved and flash the whole queue back to placeholders.
    final sameQueue =
        _appliedQueueIds != null &&
        _appliedQueueIds!.length == queueIds.length &&
        Iterable<int>.generate(
          queueIds.length,
        ).every((i) => _appliedQueueIds![i] == queueIds[i]);

    if (!sameQueue) {
      final queueApplied = player.applyRemoteQueue(
        queueIds.map(MediaItemBuilder.placeholder).toList(),
        index: index,
        positionMs: positionMs,
        durationMs: durationMs,
        playing: playing,
      );
      if (!queueApplied) return;
      _appliedQueueIds = List<String>.unmodifiable(queueIds);
      unawaited(_backfill(queueIds));
      return;
    }

    // Same songs, new position in it — follow the target's skip without a
    // rebuild, and WITHOUT touching progress. A snapshot's progress fields are
    // only persisted every ~10s, so applying them here yanked the bar back to a
    // stale value between live frames — the position visibly flicking 0, 1, 0, 1.
    // Live `progress` frames own the position; the snapshot owns the queue.
    player.applyRemoteIndex(index);
  }

  List<String>? _appliedQueueIds;

  /// The session's queue, as the cloud holds it.
  ///
  /// Authoritative for both devices. The local audio handler is only ever "what
  /// is loaded to play" — on the target it starts as a single song and widens in
  /// the background, so reading the queue off it can momentarily see one track
  /// and collapse the shared queue for everyone.
  List<String>? get sessionQueueIds => _appliedQueueIds;

  /// Resolves placeholders in the background and hands them back as they land,
  /// so a long queue fills progressively instead of appearing all at once.
  Future<void> _backfill(List<String> queueIds) async {
    final player = _player;
    if (player == null) return;
    printINFO(
      'backfill start ids=${queueIds.length}',
      tag: LogTags.cloudPlayback,
    );
    player.setQueueResolutionProgress(resolved: 0, total: queueIds.length);
    var resolved = 0;
    try {
      for (final chunk in _chunks(queueIds, 100)) {
        final items = await _metadata.resolveBatch(chunk);
        resolved += items.length;
        printINFO(
          'backfill chunk=${chunk.length} resolved=${items.length} '
          'total=$resolved/${queueIds.length}',
          tag: LogTags.cloudPlayback,
        );
        player.mergeResolvedQueueItems(items);
        player.setQueueResolutionProgress(
          resolved: resolved,
          total: queueIds.length,
        );
      }
    } catch (error, stackTrace) {
      // This runs unawaited, so an exception here used to vanish — leaving
      // every row on the mirroring device as a placeholder with no trace.
      CrashDiagnosticsService.instance.record(
        'cloud-playback',
        'Queue backfill failed after $resolved/${queueIds.length}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      player.setQueueResolutionProgress(
        resolved: queueIds.length,
        total: queueIds.length,
      );
    }
  }

  /// Target side: resolve the current song and start it, then widen the queue in
  /// the background so next/previous and preloading work.
  Future<void> _startPlayback(
    Map<String, dynamic> state, {
    required int positionMs,
    required bool playing,
    bool isExplicitHandoff = false,
  }) async {
    final incomingModes = CloudPlaybackModes.fromMap(state);
    if (incomingModes.hasAny) {
      _sessionModes = _sessionModes.merge(incomingModes);
      await _applyModesToLocalPlayer(incomingModes, preserveQueueOrder: true);
    }
    final queueIds = _queueIdsOf(state);
    if (queueIds.isEmpty) throw const FormatException('Empty session queue.');
    final index = _indexOf(state, queueIds.length);
    final generation = ++_targetPlaybackGeneration;
    // Remember the cloud's queue even as the target, so a handoff started before
    // the local queue finishes widening still carries every song.
    _appliedQueueIds = List<String>.unmodifiable(queueIds);
    final startPosition = (state['positionMs'] as num?)?.toInt() ?? positionMs;
    // A handoff is an explicit user action, so it resumes unless the session
    // says otherwise. Relying only on the source's button state meant a handoff
    // started while the source was still buffering arrived as "not playing" and
    // the target loaded the song but never pressed play.
    final shouldPlay = state.containsKey('playing')
        ? state['playing'] == true
        : (playing || isExplicitHandoff);

    printINFO(
      'startPlayback song=${queueIds[index]} index=$index '
      'queue=${queueIds.length} position=$startPosition play=$shouldPlay',
      tag: LogTags.cloudPlayback,
    );
    _targetSongIdOverride = queueIds[index];
    _targetLoadingPositionMs = startPosition < 0 ? 0 : startPosition;
    _targetLoadingDurationMs = (state['initialDurationMs'] as num?)?.toInt();
    _targetLoadingPlaying = shouldPlay;
    final pendingSong = MediaItemBuilder.placeholder(queueIds[index]).copyWith(
      duration:
          _targetLoadingDurationMs != null && _targetLoadingDurationMs! > 0
          ? Duration(milliseconds: _targetLoadingDurationMs!)
          : null,
    );
    await _player?.prepareIncomingCloudSong(
      pendingSong,
      position: Duration(milliseconds: _targetLoadingPositionMs!),
    );
    _applyingSessionQueue++;
    try {
      // Bounded for the same reason playByIndex below is: everything the user
      // can see on the target — the spinner, the shimmering title, the held
      // position — clears in this method's `finally`, so an await here that
      // never returns is indistinguishable from the app having died.
      final current = await _metadata
          .resolve(queueIds[index])
          .timeout(_metadataResolveTimeout, onTimeout: () => null);
      if (generation != _targetPlaybackGeneration) return;
      printINFO(
        'startPlayback resolved ${queueIds[index]} -> '
        '${current == null ? 'NOTHING' : current.title}',
        tag: LogTags.cloudPlayback,
      );
      if (current == null) {
        throw const FormatException('Unable to resolve the session song.');
      }
      await _local.updateQueue([current]);
      if (generation != _targetPlaybackGeneration) return;
      // Bounded: playByIndex completes only once the source is loaded, and a
      // stalled load must not wedge the command ack, the spinner, and progress
      // publishing along with it. The handler keeps working in the background
      // and reports through its own state either way.
      await _local
          .playByIndex(
            0,
            position: startPosition < 0 ? 0 : startPosition,
            generateNewUrl: true,
          )
          .timeout(
            _playbackStartTimeout,
            onTimeout: () => CrashDiagnosticsService.instance.record(
              'cloud-playback',
              'Audio load for the session song did not settle within '
                  '${_playbackStartTimeout.inSeconds}s; continuing anyway',
            ),
          );
      if (generation != _targetPlaybackGeneration) return;
      if (shouldPlay) unawaited(_local.play());
    } finally {
      _applyingSessionQueue--;
      if (generation == _targetPlaybackGeneration) {
        // The device producing the audio never mirrors anyone. Say so out loud
        // instead of trusting that no stale snapshot ever set the mirror gate:
        // while that gate is up the player ignores this device's own handler,
        // so the resolved song plays under a placeholder that shimmers
        // forever. A no-op unless something really did leave the gate up.
        await _player?.clearRemoteSessionState();
        _player?.setCurrentSongResolving(false);
        printINFO(
          'startPlayback finished song=${queueIds[index]}',
          tag: LogTags.cloudPlayback,
        );
      } else if (_applyingSessionQueue == 0) {
        // A target-side tap cancelled this install. Its queue/media events may
        // have been suppressed while the counter was non-zero, so publish the
        // now-authoritative local queue once the stale operation unwinds.
        _scheduleStatePublish();
      }
    }

    if (generation == _targetPlaybackGeneration) {
      unawaited(_widenLocalQueue(queueIds, generation));
    }
  }

  /// Replaces the single-song starter queue with the full resolved queue without
  /// interrupting playback. The current song keeps playing because
  /// `updateQueue` only swaps the list; the handler re-derives the index by id.
  Future<void> _widenLocalQueue(List<String> queueIds, int generation) async {
    if (queueIds.length < 2 || generation != _targetPlaybackGeneration) return;
    final player = _player;
    player?.setQueueResolutionProgress(resolved: 1, total: queueIds.length);
    _applyingSessionQueue++;
    try {
      final resolved = <MediaItem>[];
      var done = 0;
      for (final chunk in _chunks(queueIds, 100)) {
        final items = await _metadata.resolveBatch(chunk);
        if (generation != _targetPlaybackGeneration) return;
        for (final id in chunk) {
          final item = items[id];
          if (item != null) resolved.add(item);
        }
        done += chunk.length;
        player?.setQueueResolutionProgress(
          resolved: done.clamp(0, queueIds.length),
          total: queueIds.length,
        );
      }
      // Only swap if we are still the target and the queue actually grew.
      if (resolved.length > 1 &&
          _isAudioTarget &&
          generation == _targetPlaybackGeneration) {
        await _local.updateQueue(resolved);
      }
    } catch (error, stackTrace) {
      CrashDiagnosticsService.instance.record(
        'cloud-playback',
        'Failed to widen the session queue',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _applyingSessionQueue--;
      if (generation == _targetPlaybackGeneration) {
        player?.setQueueResolutionProgress(
          resolved: queueIds.length,
          total: queueIds.length,
        );
      } else if (_applyingSessionQueue == 0) {
        _scheduleStatePublish();
      }
    }
  }

  // ---------------------------------------------------------------- publishing

  void _startProgressPublishing() {
    _progressTimer ??= Timer.periodic(
      progressInterval,
      (_) => _publishProgressFrame(),
    );
    _publishProgressFrame();
  }

  void _publishProgressFrame() {
    final frame = _local.progressFrame();
    final localSongId = frame['currentSongId']?.toString();
    if (_targetSongIdOverride == localSongId) {
      _targetSongIdOverride = null;
    } else if (_targetSongIdOverride case final pendingSongId?) {
      frame['currentSongId'] = pendingSongId;
      frame['songMetadata'] = {
        'id': pendingSongId,
        'title': '',
        'artist': '',
        'album': null,
        'durationMs': _targetLoadingDurationMs,
        'artworkUri': null,
      };
      if (_targetLoadingDurationMs != null) {
        frame['durationMs'] = _targetLoadingDurationMs;
      }
    }
    // While the handed-off song is still loading, the local player can still
    // report the previous playing state. Publish the transition explicitly so
    // controllers keep their loading UI until the new source settles.
    final targetLoadingPositionMs = _targetLoadingPositionMs;
    final transitionLoading =
        _startingPlayback != null || _targetSongIdOverride != null;
    final sourceLoading = frame['loading'] == true;
    if (targetLoadingPositionMs != null &&
        (transitionLoading || sourceLoading)) {
      frame['positionMs'] = targetLoadingPositionMs;
      frame['playing'] = _targetLoadingPlaying;
      frame['loading'] = true;
    } else if (!transitionLoading && !sourceLoading) {
      _targetLoadingPositionMs = null;
      _targetLoadingDurationMs = null;
    }
    final metadata = frame['songMetadata'];
    final title = metadata is Map ? metadata['title']?.toString() ?? '' : null;
    final line =
        'publish song=${frame['currentSongId']} '
        'title="${title ?? '<none>'}" '
        'override=$_targetSongIdOverride loading=${frame['loading']} '
        'playing=${frame['playing']} pos=${frame['positionMs']}';
    if (line != _lastPublishLine) {
      _lastPublishLine = line;
      printINFO(line, tag: LogTags.cloudPlayback);
    }
    _socket.send(frame);
  }

  String? _lastPublishLine;

  void _stopProgressPublishing() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  /// Publishes the durable queue whenever the target changes it locally, so the
  /// other device can follow a skip. Progress frames alone are not enough: they
  /// carry position, not queue order or index.
  void _watchLocalPlaybackForPublication() {
    _localQueue = _local.queueStream.listen((_) => _scheduleStatePublish());
    _localSong = _local.mediaItemStream.listen(_onLocalSongChanged);
    _localSelection = _commands.localSongSelections.listen(
      _onLocalSongSelected,
    );
    _localPlaybackState = _local.playbackStateStream.listen(
      _onLocalPlaybackStateChanged,
    );
    _localModeChanges = _commands.localModeChanges.listen(
      _onLocalPlaybackModesChanged,
    );
  }

  void _onLocalPlaybackStateChanged(PlaybackState _) {
    final modes = _local.playbackModes;
    if (modes == _lastObservedLocalModes) return;
    _lastObservedLocalModes = modes;
    if (!_isAudioTarget) return;
    _sessionModes = _sessionModes.merge(modes);
    unawaited(_local.persistPlaybackModes(modes));
    _publishProgressFrame();
    _scheduleStatePublish();
  }

  void _onLocalPlaybackModesChanged(CloudPlaybackModes modes) {
    if (!_isAudioTarget) return;
    _sessionModes = _sessionModes.merge(modes);
    _lastObservedLocalModes = modes;
    _publishProgressFrame();
    _scheduleStatePublish();
  }

  void _onLocalSongSelected(String? _) {
    if (!_isAudioTarget) return;
    // This is emitted only by the forwarding facade's *local* UI path. Network
    // commands use LocalPlaybackCommands and never reach here, so a real target
    // tap can safely supersede an older metadata lookup/queue backfill even
    // while [_applyingSessionQueue] is non-zero.
    _targetPlaybackGeneration++;
    _targetSongIdOverride = null;
    _targetLoadingPositionMs = null;
    _targetLoadingDurationMs = null;
    // Keep the current session latch claimed. Releasing it here lets a snapshot
    // containing the previous cloud state restart that song before this local
    // selection's debounced session update reaches the server.
  }

  /// Guards against a burst of song changes firing overlapping claims.
  bool _claimInFlight = false;

  /// Advertises this device as the audio target for what it is already
  /// playing, so another device can subscribe to it as a remote.
  ///
  /// Without this a device playing on its own publishes nothing: every publish
  /// path is gated on being the target, and the only way to become the target
  /// used to be accepting a handoff. So there was never a session to join.
  Future<void> _claimSessionForLocalPlayback() async {
    if (_isEngaged || _claimInFlight) return;
    if (!_cloud.shareNowPlaying) return;
    final queue = _local.queue;
    if (queue.isEmpty) return;
    _claimInFlight = true;
    try {
      // The index the queue is actually sitting on. Deriving it from the
      // current song rather than tracking a separate counter keeps this
      // correct across shuffle, which reorders the queue underneath.
      final current = _local.currentSong;
      final index = current == null
          ? 0
          : queue.indexWhere((item) => item.id == current.id).clamp(0, queue.length - 1);
      final sessionId = await _cloud.claimPlaybackSession(
        state: _commands.sessionState(queue: queue, index: index),
      );
      // Null is a refusal, not an error: another device legitimately owns the
      // session, or the server predates the endpoint. Either way this device
      // keeps playing, just without advertising.
      if (sessionId == null) return;
      _isAudioTarget = true;
      _startProgressPublishing();
      _scheduleStatePublish();
    } catch (error, stackTrace) {
      CrashDiagnosticsService.instance.record(
        'cloud-playback',
        'claiming a session for local playback failed: $error',
        stackTrace: stackTrace,
      );
    } finally {
      _claimInFlight = false;
    }
  }

  void _onLocalSongChanged(MediaItem? item) {
    // A song starting here is the moment there is something worth advertising.
    if (!_isAudioTarget && item != null) {
      unawaited(_claimSessionForLocalPlayback());
    }
    if (_isAudioTarget && item != null) {
      final pendingSongId = _targetSongIdOverride;
      // A song tapped directly on the target supersedes any handoff placeholder
      // that is still latched. Otherwise progress keeps publishing that old
      // placeholder forever even though the local source is already ready.
      if (_applyingSessionQueue == 0 &&
          pendingSongId != null &&
          pendingSongId != item.id) {
        _targetPlaybackGeneration++;
        _targetSongIdOverride = null;
        _targetLoadingPositionMs = null;
        _targetLoadingDurationMs = null;
      }
      // Do not wait for the periodic tick. The controller should see the new
      // song (or its loading state) as soon as the target's media item changes.
      _publishProgressFrame();
    }
    _scheduleStatePublish();
  }

  void _scheduleStatePublish() {
    if (!_isAudioTarget) return;
    // Starting a session deliberately installs a one-song queue and then widens
    // it. Publishing in between would overwrite the session's full queue with
    // that placeholder and strip everyone else's list down to a single track.
    if (_applyingSessionQueue > 0) return;
    _statePublishDebounce?.cancel();
    _statePublishDebounce = Timer(
      _statePublishDebounce_,
      () => unawaited(_publishSessionState()),
    );
  }

  Future<void> _publishSessionState() async {
    if (!_isAudioTarget) return;
    final queue = _local.queue;
    if (queue.isEmpty) return;
    final currentId = _local.currentSong?.id;
    // A local queue event is authoritative. Receiver-driven starter/widening
    // queues are already suppressed by [_applyingSessionQueue] in
    // [_scheduleStatePublish]. Reusing an older cloud queue merely because it
    // was longer made a real replacement (for example 50 random songs -> 5
    // favorites) impossible to publish.
    final orderedIds = queue.map((item) => item.id).toList();
    final index = currentId == null ? 0 : orderedIds.indexOf(currentId);
    try {
      await _cloud.updatePlaybackSessionState(
        _commands.sessionState(
          queue: queue,
          index: index < 0 ? 0 : index,
          currentVideoId: currentId,
        ),
      );
      _appliedQueueIds = List<String>.unmodifiable(orderedIds);
    } catch (error, stackTrace) {
      CrashDiagnosticsService.instance.record(
        'cloud-playback',
        'Unable to publish the session queue',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  // ------------------------------------------------------------------ commands

  Future<void> _applyDeliveredCommand({
    required String? commandId,
    required String type,
    required Map<String, dynamic> payload,
    required bool ackOverSocket,
  }) async {
    // Socket replay and the REST drain overlap by design, so the same command
    // can arrive twice. Re-applying a handoff would restart playback.
    if (commandId != null && !_appliedCommandIds.add(commandId)) return;

    var applied = false;
    try {
      await _applyCommand(type, payload);
      applied = true;
      _lastAppliedCommandId = commandId;
    } catch (error, stackTrace) {
      if (commandId != null) _appliedCommandIds.remove(commandId);
      CrashDiagnosticsService.instance.record(
        'cloud-playback',
        'Failed to apply $type command',
        error: error,
        stackTrace: stackTrace,
        flush: true,
      );
    }
    if (commandId != null) {
      if (ackOverSocket) {
        _socket.send({
          'type': 'ack',
          'commandId': commandId,
          'applied': applied,
        });
      } else {
        // Drained over REST: ack the same way so the server stops replaying it.
        try {
          await _cloud.acknowledgePlaybackCommand(
            commandId: commandId,
            applied: applied,
          );
        } catch (_) {
          // The command expires server-side; a lost ack is not worth failing on.
        }
      }
    }
    if (applied && _isAudioTarget) _publishProgressFrame();
  }

  Future<void> _applyCommand(String type, Map<String, dynamic> payload) async {
    // A handoff is the user explicitly sending audio here and always engages.
    // Every other command is remote control of an existing target — a device
    // that never accepted the session must not have its local playback driven
    // by stale queued commands (they get acked applied=false instead).
    if (type != 'handoff' && !_isAudioTarget) {
      throw StateError('Not the audio target; refusing $type command.');
    }
    switch (type) {
      case 'handoff':
        // Receiving a handoff *is* the become-target transition.
        await _becomeAudioTarget();
        _startProgressPublishing();
        // A handoff always restarts playback, so it clears the latch first —
        // but still goes through the guard so it cannot race a snapshot.
        _appliedTargetSessionId = null;
        await _startSessionPlayback(
          _handoffSessionId,
          payload,
          positionMs: 0,
          playing: true,
          isExplicitHandoff: true,
        );
        return;
      case 'play':
        await _local.play();
        return;
      case 'pause':
        await _local.pause();
        return;
      case 'playPause':
        await _local.playPause(isPlaying: _local.isPlaying);
        return;
      case 'seek':
        await _local.seek(
          Duration(milliseconds: (payload['positionMs'] as num?)?.toInt() ?? 0),
        );
        return;
      case 'next':
        final desiredVideoId = payload['desiredVideoId']?.toString();
        _lastRequestedNextSongId = desiredVideoId;
        if (desiredVideoId != null &&
            await _playCloudQueueItem(desiredVideoId)) {
          return;
        }
        if (await _playNextCloudQueueItem()) return;
        await _local.next();
        return;
      case 'previous':
        final intent = previousTrackIntentFromWire(payload['intent']);
        if (intent == null) {
          throw const FormatException(
            'Previous command is missing a valid intent',
          );
        }
        if (intent == PreviousTrackIntent.restartCurrent) {
          await _local.seek(Duration.zero);
          return;
        }
        final desiredVideoId = payload['desiredVideoId']?.toString();
        final queueIds = _appliedQueueIds;
        if (desiredVideoId != null &&
            queueIds != null &&
            queueIds.contains(desiredVideoId)) {
          await _startPlayback(
            {
              'queueIds': queueIds,
              'index': queueIds.indexOf(desiredVideoId),
              'currentSongId': desiredVideoId,
              'positionMs': 0,
              'playing': true,
            },
            positionMs: 0,
            playing: true,
          );
          return;
        }
        // The controller has already decided that this press means "change
        // track", based on the position visible to the user. Do not pass that
        // intent through skipToPrevious(): it checks this device's position a
        // second time and can reinterpret the press as "restart", particularly
        // when the mirrored progress is still catching up. Resolve and start
        // the preceding cloud queue item directly instead.
        if (await _playPreviousCloudQueueItem()) return;
        await _local.previous();
        return;
      case 'queueUpdate':
        await _applyQueueUpdate(payload);
        return;
      case 'shuffleMode':
        await _local.setShuffle(payload['enabled'] == true);
        _sessionModes = _sessionModes.merge(
          CloudPlaybackModes(shuffle: payload['enabled'] == true),
        );
        _scheduleStatePublish();
        return;
      case 'repeatMode':
        await _local.setLoop(payload['enabled'] == true);
        _sessionModes = _sessionModes.merge(
          CloudPlaybackModes(repeat: payload['enabled'] == true),
        );
        _scheduleStatePublish();
        return;
      case 'queueLoopMode':
        await _local.setQueueLoopMode(payload['enabled'] == true);
        _sessionModes = _sessionModes.merge(
          CloudPlaybackModes(queueLoop: payload['enabled'] == true),
        );
        _scheduleStatePublish();
        return;
      case 'volume':
        await _local.setVolume((payload['value'] as num?)?.toInt() ?? 100);
        return;
      default:
        throw FormatException('Unsupported playback command: $type');
    }
  }

  Future<bool> _playPreviousCloudQueueItem() async {
    final queueIds = _appliedQueueIds;
    final currentSongId = _targetSongIdOverride ?? _local.currentSong?.id;
    if (queueIds == null || currentSongId == null) return false;
    final currentIndex = queueIds.indexOf(currentSongId);
    if (currentIndex <= 0) return false;
    final previousIndex = currentIndex - 1;
    final previousSongId = queueIds[previousIndex];
    await _startPlayback(
      {
        'queueIds': queueIds,
        'index': previousIndex,
        'currentSongId': previousSongId,
        'positionMs': 0,
        'playing': true,
      },
      positionMs: 0,
      playing: true,
    );
    return true;
  }

  Future<bool> _playNextCloudQueueItem() async {
    final queueIds = _appliedQueueIds;
    final currentSongId = _targetSongIdOverride ?? _local.currentSong?.id;
    if (queueIds == null || currentSongId == null) return false;
    final currentIndex = queueIds.indexOf(currentSongId);
    if (currentIndex < 0) return false;
    final nextIndex = currentIndex + 1 < queueIds.length
        ? currentIndex + 1
        : _local.playbackModes.queueLoop == true
        ? 0
        : currentIndex;
    if (nextIndex == currentIndex) return false;
    return _playCloudQueueItem(queueIds[nextIndex]);
  }

  Future<bool> _playCloudQueueItem(String videoId) async {
    final queueIds = _appliedQueueIds;
    if (queueIds == null) return false;
    final index = queueIds.indexOf(videoId);
    if (index < 0) return false;
    await _startPlayback(
      {
        'queueIds': queueIds,
        'index': index,
        'currentSongId': videoId,
        'positionMs': 0,
        'playing': true,
      },
      positionMs: 0,
      playing: true,
    );
    return true;
  }

  int _queueUpdateGeneration = 0;

  Future<void> _applyQueueUpdate(Map<String, dynamic> payload) async {
    final generation = _targetPlaybackGeneration;
    final queueUpdateGeneration = ++_queueUpdateGeneration;
    final queueIds = _queueIdsOf(payload);
    if (queueIds.isEmpty) {
      if (generation != _targetPlaybackGeneration ||
          queueUpdateGeneration != _queueUpdateGeneration) {
        return;
      }
      await _local.clearQueue();
      _appliedQueueIds = const [];
      return;
    }
    final resolved = await _metadata.resolveBatch(queueIds);
    if (generation != _targetPlaybackGeneration ||
        queueUpdateGeneration != _queueUpdateGeneration) {
      return;
    }
    final items = queueIds
        .map((id) => resolved[id])
        .whereType<MediaItem>()
        .toList();
    if (items.isEmpty)
      throw const FormatException('Unresolvable queue update.');
    await _local.updateQueue(items);
    _appliedQueueIds = List<String>.unmodifiable(items.map((item) => item.id));
  }

  // --------------------------------------------------------------- diagnostics

  /// Surfaced in the diagnostics dump: the previous handoff failure could not be
  /// diagnosed because nothing recorded which role each device believed it had.
  Map<String, Object?> diagnostics() => {
    'deviceId': _cloud.deviceId,
    'isAudioTarget': _isAudioTarget,
    'isMirroringRemotePlayback': _player?.isMirroringRemotePlayback ?? false,
    'socketStatus': _socket.currentStatus.name,
    'appliedTargetSessionId': _appliedTargetSessionId,
    'appliedQueueRevision': _appliedQueueRevision,
    'appliedCommandCount': _appliedCommandIds.length,
    'lastAppliedCommandId': _lastAppliedCommandId,
    'lastFrameReceived': _lastFrameReceived,
    'lastFrameReceivedAt': _lastFrameReceivedAt?.toIso8601String(),
    'publishingProgress': _progressTimer != null,
    'sessionModes': _sessionModes.toMap(),
    'lastRequestedNextSongId': _lastRequestedNextSongId,
  };

  // ------------------------------------------------------------------- helpers

  static List<String> _queueIdsOf(Map<String, dynamic> state) {
    final raw = state['queueIds'];
    if (raw is! List) return const [];
    return raw
        .map((id) => id.toString())
        .where((id) => id.trim().isNotEmpty)
        .toList();
  }

  static int _indexOf(Map<String, dynamic> state, int length) {
    final index = (state['index'] as num?)?.toInt() ?? 0;
    return index < 0 || index >= length ? 0 : index;
  }

  static int _revisionOf(Map<String, dynamic> state) =>
      (state['queueRevision'] as num?)?.toInt() ?? 0;

  bool _matchesAppliedHandoff(Map<String, dynamic> state) {
    final incomingIds = _queueIdsOf(state);
    final appliedIds = _appliedQueueIds;
    if (appliedIds == null || incomingIds.length != appliedIds.length) {
      return false;
    }
    for (var index = 0; index < incomingIds.length; index++) {
      if (incomingIds[index] != appliedIds[index]) return false;
    }
    final incomingIndex = _indexOf(state, incomingIds.length);
    final incomingSongId = incomingIds.isEmpty
        ? null
        : incomingIds[incomingIndex];
    final activeSongId = _targetSongIdOverride ?? _local.currentSong?.id;
    return incomingSongId != null && incomingSongId == activeSongId;
  }

  Future<void> _applyModesToLocalPlayer(
    CloudPlaybackModes modes, {
    required bool preserveQueueOrder,
  }) async {
    if (!modes.hasAny) return;
    final current = _local.playbackModes;
    if (modes.repeat case final enabled?) {
      if (current.repeat != enabled) await _local.setLoop(enabled);
    }
    if (modes.queueLoop case final enabled?) {
      if (current.queueLoop != enabled) {
        await _local.setQueueLoopMode(enabled);
      }
    }
    if (modes.shuffle case final enabled?) {
      if (current.shuffle != enabled) {
        await _local.setShuffle(
          enabled,
          preserveQueueOrder: preserveQueueOrder,
        );
      }
    }
    await _local.persistPlaybackModes(modes);
    _lastObservedLocalModes = _local.playbackModes;
  }

  static Iterable<List<T>> _chunks<T>(List<T> items, int size) sync* {
    for (var start = 0; start < items.length; start += size) {
      yield items.sublist(start, (start + size).clamp(0, items.length));
    }
  }

  void dispose() {
    _stopProgressPublishing();
    _statePublishDebounce?.cancel();
    unawaited(_localQueue?.cancel());
    unawaited(_localSong?.cancel());
    unawaited(_localSelection?.cancel());
    unawaited(_localPlaybackState?.cancel());
    unawaited(_localModeChanges?.cancel());
    unawaited(_frames?.cancel());
    unawaited(_status?.cancel());
    unawaited(_socket.dispose());
  }
}
