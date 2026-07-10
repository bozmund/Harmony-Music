import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../../models/media_Item_builder.dart';
import '../../ui/player/player_controller.dart';
import '../constant.dart';
import '../playback_command_service.dart';
import '../../utils/helper.dart';
import 'listen_together_gate.dart';
import 'session_message.dart';
import 'sync_clock.dart';
import 'sync_transport.dart';

/// Role of the local device in a Listen Together session.
enum LTRole { none, host, guest }

/// Factory that builds a concrete [SyncTransport] for a given [TransportKind].
/// Injected so this controller stays decoupled from the LAN/Bluetooth code and
/// remains unit-testable with a fake transport.
typedef TransportFactory = SyncTransport Function(TransportKind kind);

/// Orchestrates a "Listen Together" session on top of a [SyncTransport].
///
/// * As **host** it observes the local [PlayerController] and broadcasts queue +
///   playback state to guests, and applies control commands guests send in.
/// * As **guest** it applies host state to the local player (via
///   [PlaybackCommandService]) with clock-offset drift correction, and forwards
///   the local user's control intents to the host (see [ListenTogetherGate]).
class ListenTogetherController extends ChangeNotifier
    implements ListenTogetherGate {
  ListenTogetherController({
    required PlayerController playerController,
    required PlaybackCommandService playbackCommands,
    required TransportFactory transportFactory,
    String? deviceName,
  }) : _player = playerController,
       _playbackCommands = playbackCommands,
       _transportFactory = transportFactory,
       _selfName = deviceName ?? 'Harmony device',
       _selfId = _generateId() {
    // Expose ourselves to the player so guest control routing works.
    _player.listenTogetherGate = this;
  }

  final PlayerController _player;
  final PlaybackCommandService _playbackCommands;
  final TransportFactory _transportFactory;

  final String _selfId;
  String _selfName;

  SyncTransport? _transport;
  StreamSubscription<SessionMessage>? _messageSub;
  StreamSubscription<List<Peer>>? _peersSub;
  StreamSubscription<TransportConnectionState>? _connSub;
  StreamSubscription<List<DiscoveredSession>>? _discoverySub;
  final List<StreamSubscription<dynamic>> _playerSubs = [];
  Timer? _heartbeat;
  Timer? _clockSyncTimer;
  bool _leaving = false;

  // ---- Observable state (read by the UI) ------------------------------------

  LTRole _role = LTRole.none;
  LTRole get role => _role;
  bool get isHost => _role == LTRole.host;
  @override
  bool get isGuest => _role == LTRole.guest;
  bool get isActive => _role != LTRole.none;

  TransportConnectionState _connectionState = TransportConnectionState.idle;
  TransportConnectionState get connectionState => _connectionState;

  List<Peer> _peers = const [];
  List<Peer> get peers => _peers;

  List<DiscoveredSession> _discovered = const [];
  List<DiscoveredSession> get discoveredSessions => _discovered;

  String get selfName => _selfName;
  String get selfId => _selfId;
  set deviceName(String value) {
    _selfName = value;
    notifyListeners();
  }

  /// Estimated `hostClock - localClock` in ms (guest only). Zero on the host.
  int _clockOffsetMs = 0;
  int? _bestClockSyncRttMs;
  int _clockSyncSamplesSent = 0;
  int _lastDriftSeekMs = 0;

  // Guards to avoid redundant guest-side player mutations.
  String? _lastAppliedSongId;
  List<String> _lastAppliedQueueIds = const [];

  SessionInfo get _self => SessionInfo(id: _selfId, name: _selfName);

  // ---------------------------------------------------------------------------
  // Hosting
  // ---------------------------------------------------------------------------

  Future<void> startHosting(TransportKind kind) async {
    await leave();
    final transport = _transportFactory(kind);
    _transport = transport;
    _role = LTRole.host;
    _clockOffsetMs = 0;
    _wireTransport(transport);
    _observePlayer();
    _startHeartbeat();
    try {
      await transport.startAdvertising(_self);
      printINFO(
        'Hosting session over ${kind.name}',
        tag: LogTags.listenTogether,
      );
    } catch (e) {
      printERROR('startHosting failed: $e', tag: LogTags.listenTogether);
      await leave();
      rethrow;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Discovery / joining (guest)
  // ---------------------------------------------------------------------------

  /// Begin browsing for host sessions of [kind]. Discovered sessions are
  /// surfaced via [discoveredSessions] (and change notifications).
  Future<void> startBrowsing(TransportKind kind) async {
    await leave();
    final transport = _transportFactory(kind);
    _transport = transport;
    _role = LTRole.none; // not connected yet, just browsing
    _wireTransport(transport, wireMessages: false);
    _discovered = const [];
    _discoverySub = transport
        .startDiscovery(_self)
        .listen(
          (sessions) {
            _discovered = sessions;
            notifyListeners();
          },
          onError: (Object e) {
            printERROR('discovery error: $e', tag: LogTags.listenTogether);
          },
        );
    _setConnectionState(TransportConnectionState.discovering);
    notifyListeners();
  }

  Future<void> joinSession(DiscoveredSession session) async {
    final transport = _transport;
    if (transport == null) return;
    // Now that we are actually connecting, listen for host messages.
    _messageSub ??= transport.onMessage.listen(_onMessage);
    _role = LTRole.guest;
    try {
      await transport.join(session, _self);
      _startClockSyncSamples();
      printINFO(
        'Joined session "${session.name}"',
        tag: LogTags.listenTogether,
      );
    } catch (e) {
      printERROR('joinSession failed: $e', tag: LogTags.listenTogether);
      await leave();
      rethrow;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Leaving / teardown
  // ---------------------------------------------------------------------------

  Future<void> leave() async {
    if (_leaving) return;
    _leaving = true;
    final transport = _transport;
    final wasActive = _role != LTRole.none;
    if (transport != null && wasActive) {
      try {
        unawaited(
          transport.send(
            SessionMessage.bye(senderId: _selfId, senderName: _selfName),
          ),
        );
      } catch (_) {}
    }

    _transport = null;
    _role = LTRole.none;
    _peers = const [];
    _discovered = const [];
    _connectionState = TransportConnectionState.idle;
    _lastAppliedSongId = null;
    _lastAppliedQueueIds = const [];
    _bestClockSyncRttMs = null;
    _clockSyncSamplesSent = 0;
    _lastDriftSeekMs = 0;
    notifyListeners();

    try {
      _heartbeat?.cancel();
      _heartbeat = null;
      _clockSyncTimer?.cancel();
      _clockSyncTimer = null;
      await _messageSub?.cancel();
      _messageSub = null;
      await _peersSub?.cancel();
      _peersSub = null;
      await _connSub?.cancel();
      _connSub = null;
      await _discoverySub?.cancel();
      _discoverySub = null;
      for (final sub in _playerSubs) {
        await sub.cancel();
      }
      _playerSubs.clear();
      if (transport != null) {
        try {
          await transport.leave();
        } catch (e) {
          printERROR(
            'leave transport cleanup failed: $e',
            tag: LogTags.listenTogether,
          );
        }
      }
    } finally {
      _leaving = false;
    }
  }

  // ---------------------------------------------------------------------------
  // ListenTogetherGate — guest control routing
  // ---------------------------------------------------------------------------

  @override
  void sendCommand(SessionCommand command) {
    final transport = _transport;
    if (transport == null || !isGuest) return;
    unawaited(
      transport.send(
        SessionMessage.command(
          senderId: _selfId,
          senderName: _selfName,
          command: command,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Transport wiring
  // ---------------------------------------------------------------------------

  void _wireTransport(SyncTransport transport, {bool wireMessages = true}) {
    if (wireMessages) {
      _messageSub = transport.onMessage.listen(_onMessage);
    }
    _peersSub = transport.peers.listen((peers) {
      final joined = peers.length > _peers.length;
      _peers = peers;
      notifyListeners();
      // When a new guest joins, push the full current state to everyone.
      if (isHost && joined) {
        _broadcastQueue();
        _broadcastPlayback();
        _broadcastPeerList();
      }
    });
    _connSub = transport.connectionState.listen((state) {
      _setConnectionState(state);
    });
  }

  void _setConnectionState(TransportConnectionState state) {
    if (_connectionState == state) return;
    _connectionState = state;
    notifyListeners();
  }

  void _startClockSyncSamples() {
    _clockSyncTimer?.cancel();
    _bestClockSyncRttMs = null;
    _clockSyncSamplesSent = 0;
    _sendClockSyncHello();
    _clockSyncTimer = Timer.periodic(_clockSyncSampleInterval, (timer) {
      if (!isGuest || _clockSyncSamplesSent >= _clockSyncSampleCount) {
        timer.cancel();
        return;
      }
      _sendClockSyncHello();
    });
  }

  void _sendClockSyncHello() {
    final transport = _transport;
    if (transport == null || !isGuest) return;
    _clockSyncSamplesSent++;
    unawaited(
      transport.send(
        SessionMessage.hello(
          senderId: _selfId,
          senderName: _selfName,
          clientTimeMs: _nowMs(),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Inbound messages
  // ---------------------------------------------------------------------------

  void _onMessage(SessionMessage message) {
    switch (message.type) {
      case SessionMessageType.hello:
        // Host: reply so the guest can estimate the clock offset.
        if (isHost) {
          unawaited(
            _transport?.sendTo(
              message.senderId,
              SessionMessage.helloAck(
                senderId: _selfId,
                senderName: _selfName,
                clientTimeMs: message.clientTimeMs,
                hostTimeMs: _nowMs(),
              ),
            ),
          );
          // Make sure the newcomer has full state.
          _broadcastQueue();
          _broadcastPlayback();
        }
        break;
      case SessionMessageType.helloAck:
        _updateClockOffset(message);
        break;
      case SessionMessageType.queueSync:
        if (isGuest) unawaited(_applyQueueSync(message));
        break;
      case SessionMessageType.playbackSync:
        if (isGuest) unawaited(_applyPlaybackSync(message.snapshot));
        break;
      case SessionMessageType.command:
        if (isHost) unawaited(_applyCommand(message.command));
        break;
      case SessionMessageType.peerList:
        if (isGuest) {
          _peers = message.peers.map(Peer.fromJson).toList();
          notifyListeners();
        }
        break;
      case SessionMessageType.bye:
        // A peer left; the transport's peers stream reflects the removal.
        break;
    }
  }

  /// rtt = now - echoedClientTime; estimated host clock at our "now" is
  /// hostTimeMs + rtt/2, so offset = (hostTimeMs + rtt/2) - now.
  void _updateClockOffset(SessionMessage ack) {
    final sample = SyncClock.estimateOffsetSample(
      helloClientTimeMs: ack.clientTimeMs,
      hostTimeMs: ack.hostTimeMs,
      ackReceivedMs: _nowMs(),
    );
    final bestRtt = _bestClockSyncRttMs;
    if (bestRtt != null && sample.rttMs > bestRtt) return;
    _bestClockSyncRttMs = sample.rttMs;
    _clockOffsetMs = sample.offsetMs;
    printINFO(
      'clock offset ~${_clockOffsetMs}ms (rtt ${sample.rttMs}ms)',
      tag: LogTags.listenTogether,
    );
  }

  // ---------------------------------------------------------------------------
  // Host: execute a guest command locally (which triggers a re-broadcast)
  // ---------------------------------------------------------------------------

  Future<void> _applyCommand(SessionCommand command) async {
    switch (command.action) {
      case SessionCommand.actionPlay:
        await _playbackCommands.play();
        break;
      case SessionCommand.actionPause:
        await _playbackCommands.pause();
        break;
      case SessionCommand.actionPlayPause:
        if (_isPlaying) {
          await _playbackCommands.pause();
        } else {
          await _playbackCommands.play();
        }
        break;
      case SessionCommand.actionNext:
        await _playbackCommands.next();
        break;
      case SessionCommand.actionPrev:
        await _playbackCommands.previous();
        break;
      case SessionCommand.actionSeek:
        await _playbackCommands.seek(command.seekPosition);
        break;
      case SessionCommand.actionPlayByIndex:
        await _playbackCommands.playByIndex(command.index);
        break;
      case SessionCommand.actionToggleShuffle:
        await _player.toggleShuffleMode();
        break;
      case SessionCommand.actionToggleLoop:
        await _player.toggleLoopMode();
        break;
    }
    // Reflect the resulting state immediately (seek in particular is not
    // covered by an observed field).
    _broadcastPlayback();
  }

  // ---------------------------------------------------------------------------
  // Guest: apply host state to the local player
  // ---------------------------------------------------------------------------

  Future<void> _applyQueueSync(SessionMessage message) async {
    final ids =
        message.queue.map((e) => e['videoId']?.toString() ?? '').toList();
    if (listEquals(ids, _lastAppliedQueueIds)) return;
    _lastAppliedQueueIds = ids;
    final items =
        message.queue.map((json) => MediaItemBuilder.fromJson(json)).toList();
    await _playbackCommands.updateQueue(items);
  }

  Future<void> _applyPlaybackSync(PlaybackSnapshot snap) async {
    final currentId = _player.currentSong.value?.id;

    // Different song (or nothing playing yet) -> jump to it at the projected
    // position.
    if (snap.songId != null && snap.songId != currentId) {
      if (_lastAppliedSongId == snap.songId) return; // switch already in flight
      _lastAppliedSongId = snap.songId;
      final expected = _expectedPositionMs(snap);
      await _playbackCommands.playByIndex(snap.index, position: expected);
      return;
    }
    _lastAppliedSongId = snap.songId;

    // Same song: reconcile play/pause first.
    if (snap.playing && !_isPlaying) {
      await _playbackCommands.play();
    } else if (!snap.playing && _isPlaying) {
      await _playbackCommands.pause();
    }

    // Drift correction (only while playing and not mid-load).
    if (snap.playing) {
      final expected = _expectedPositionMs(snap);
      final actual = _player.progressBarStatus.value.current.inMilliseconds;
      final now = _nowMs();
      if ((expected - actual).abs() > _driftThresholdMs &&
          now - _lastDriftSeekMs > _driftSeekThrottleMs) {
        _lastDriftSeekMs = now;
        await _playbackCommands.seek(Duration(milliseconds: max(0, expected)));
      }
    }
  }

  int _expectedPositionMs(PlaybackSnapshot snap) =>
      SyncClock.expectedPositionMs(
        snap,
        clockOffsetMs: _clockOffsetMs,
        nowMs: _nowMs(),
      );

  // ---------------------------------------------------------------------------
  // Host: observe player + broadcast
  // ---------------------------------------------------------------------------

  void _observePlayer() {
    _playerSubs.add(_player.currentSong.listen((_) => _broadcastPlayback()));
    _playerSubs.add(
      _player.currentSongIndex.listen((_) => _broadcastPlayback()),
    );
    _playerSubs.add(_player.buttonState.listen((_) => _broadcastPlayback()));
    _playerSubs.add(
      _player.isShuffleModeEnabled.listen((_) => _broadcastPlayback()),
    );
    _playerSubs.add(
      _player.isLoopModeEnabled.listen((_) => _broadcastPlayback()),
    );
    _playerSubs.add(_player.currentQueue.listen((_) => _broadcastQueue()));
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) {
      if (isHost) _broadcastPlayback();
    });
  }

  void _broadcastQueue() {
    final transport = _transport;
    if (transport == null || !isHost) return;
    final queue = _player.currentQueue.value.map(sessionSafeQueueJson).toList();
    unawaited(
      transport.send(
        SessionMessage.queueSync(
          senderId: _selfId,
          senderName: _selfName,
          queue: queue,
          index: _player.currentSongIndex.value,
        ),
      ),
    );
  }

  void _broadcastPlayback() {
    final transport = _transport;
    if (transport == null || !isHost) return;
    unawaited(
      transport.send(
        SessionMessage.playbackSync(
          senderId: _selfId,
          senderName: _selfName,
          snapshot: PlaybackSnapshot(
            songId: _player.currentSong.value?.id,
            index: _player.currentSongIndex.value,
            positionMs: _player.progressBarStatus.value.current.inMilliseconds,
            playing: _isPlaying,
            hostTimestampMs: _nowMs(),
            shuffle: _player.isShuffleModeEnabled.value,
            loop: _player.isLoopModeEnabled.value,
          ),
        ),
      ),
    );
  }

  void _broadcastPeerList() {
    final transport = _transport;
    if (transport == null || !isHost) return;
    unawaited(
      transport.send(
        SessionMessage.peerList(
          senderId: _selfId,
          senderName: _selfName,
          peers: _peers.map((p) => p.toJson()).toList(),
        ),
      ),
    );
  }

  bool get _isPlaying => _player.buttonState.value == PlayButtonState.playing;

  @visibleForTesting
  static Map<String, dynamic> sessionSafeQueueJson(MediaItem item) {
    final json = MediaItemBuilder.toJson(item);
    final url = json['url'];
    if (url is String && _isLocalSourceUrl(url)) {
      json.remove('url');
    }
    return json;
  }

  static bool _isLocalSourceUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (uri.scheme == 'file') return true;
    if (uri.scheme == 'http' || uri.scheme == 'https') return false;
    return url.startsWith('/') || url.contains('/cache');
  }

  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  static const Duration _heartbeatInterval = Duration(milliseconds: 750);
  static const Duration _clockSyncSampleInterval = Duration(milliseconds: 180);
  static const int _clockSyncSampleCount = 5;
  static const int _driftThresholdMs = 250;
  static const int _driftSeekThrottleMs = 1000;

  static String _generateId() {
    final rnd = Random();
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '-${rnd.nextInt(1 << 32).toRadixString(36)}';
  }

  @override
  void dispose() {
    if (identical(_player.listenTogetherGate, this)) {
      _player.listenTogetherGate = null;
    }
    unawaited(leave());
    super.dispose();
  }
}
