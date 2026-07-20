import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'nearby_bridge.dart';
import 'nearby_permissions.dart';
import 'nearby_frames.dart';
import 'session_message.dart';
import 'sync_transport.dart';

/// Bluetooth / Wi-Fi-Direct P2P transport (Nearby Connections / Multipeer).
///
class NearbyTransport
    implements
        SyncTransport,
        ConnectionAuthenticatingTransport,
        TransportErrorReporting {
  @override
  TransportKind get kind => TransportKind.bluetooth;

  final _messageController = StreamController<SessionMessage>.broadcast();
  final _peersController = StreamController<List<Peer>>.broadcast();
  final _connController =
      StreamController<TransportConnectionState>.broadcast();
  final _errorController = StreamController<Object>.broadcast();

  @override
  Stream<SessionMessage> get onMessage => _messageController.stream;
  @override
  Stream<List<Peer>> get peers => _peersController.stream;
  @override
  Stream<TransportConnectionState> get connectionState =>
      _connController.stream;
  @override
  Stream<Object> get errors => _errorController.stream;
  @override
  Stream<List<DiscoveredSession>> get discoveredSessions =>
      _sessionsController.stream;

  final NearbyBridge _bridge;
  StreamSubscription<Map<String, dynamic>>? _events;
  final Map<String, Peer> _peers = {};
  final Map<String, String> _endpointByPeerId = {};
  final Map<String, Completer<void>> _joinCompleters = {};
  final Map<String, DiscoveredSession> _sessions = {};
  SessionInfo? _self;
  final NearbyFrameCodec _frames = NearbyFrameCodec();
  final _confirmationController =
      StreamController<ConnectionConfirmation>.broadcast();
  @override
  Stream<ConnectionConfirmation> get confirmations =>
      _confirmationController.stream;
  NearbyTransport({NearbyBridge? bridge}) : _bridge = bridge ?? NearbyBridge();

  @override
  Future<void> startAdvertising(SessionInfo info) async {
    await NearbyPermissions.ensureGranted();
    _self = info;
    _listen();
    await _bridge.advertise(name: info.name, sessionId: info.id);
    _connController.add(TransportConnectionState.advertising);
  }

  @override
  Future<void> startDiscovery(SessionInfo self) async {
    _self = self;
    _listen();
    await NearbyPermissions.ensureGranted();
    await _bridge.discover();
    _connController.add(TransportConnectionState.discovering);
  }

  final _sessionsController =
      StreamController<List<DiscoveredSession>>.broadcast();

  @override
  Future<void> join(DiscoveredSession session, SessionInfo self) async {
    final endpointId = session.endpointId;
    if (endpointId == null) throw StateError('Nearby session has no endpoint');
    _self = self;
    final completer = Completer<void>();
    _joinCompleters[endpointId] = completer;
    await _bridge.connect(endpointId: endpointId, name: self.name);
    _connController.add(TransportConnectionState.connecting);
    try {
      await completer.future.timeout(const Duration(seconds: 60));
    } finally {
      _joinCompleters.remove(endpointId);
    }
  }

  @override
  Future<void> send(SessionMessage message) async {
    final bytes = Uint8List.fromList(utf8.encode(message.encode()));
    for (final id in _endpointByPeerId.values.toSet()) {
      for (final frame in _frames.encode(bytes)) {
        await _bridge.send(id, frame);
      }
    }
  }

  @override
  Future<void> sendTo(String peerId, SessionMessage message) async {
    final endpointId = _endpointByPeerId[peerId] ?? peerId;
    final bytes = Uint8List.fromList(utf8.encode(message.encode()));
    for (final frame in _frames.encode(bytes)) {
      await _bridge.send(endpointId, frame);
    }
  }

  @override
  Future<void> confirmConnection(String endpointId, bool accept) =>
      _bridge.confirm(endpointId, accept);

  @override
  Future<void> leave() async {
    _peers.clear();
    _endpointByPeerId.clear();
    for (final completer in _joinCompleters.values) {
      if (!completer.isCompleted)
        completer.completeError(StateError('Nearby session ended'));
    }
    _joinCompleters.clear();
    _sessions.clear();
    _frames.reset();
    await _bridge.stop();
    _peersController.add(const []);
    _sessionsController.add(const []);
    _connController.add(TransportConnectionState.disconnected);
  }

  @override
  Future<void> dispose() async {
    await leave();
    await _events?.cancel();
    await _messageController.close();
    await _peersController.close();
    await _connController.close();
    await _errorController.close();
    await _sessionsController.close();
    await _confirmationController.close();
  }

  void _listen() {
    _events ??= _bridge.events.listen((event) {
      switch (event['type']) {
        case 'endpointFound':
          final id = event['endpointId'] as String?;
          if (id == null) return;
          final sessionId = event['sessionId'] as String? ?? id;
          if (sessionId == _self?.id) return;
          _sessions[sessionId] = DiscoveredSession(
            id: sessionId,
            name: event['name'] as String? ?? 'Session',
            kind: kind,
            endpointId: id,
          );
          _sessionsController.add(_sessions.values.toList());
        case 'endpointLost':
          _sessions.remove(event['sessionId']);
          _sessionsController.add(_sessions.values.toList());
        case 'connectionCode':
          final endpointId = event['endpointId'] as String?;
          final code = event['code'] as String?;
          if (endpointId != null && code != null) {
            _confirmationController.add(
              ConnectionConfirmation(
                endpointId: endpointId,
                name: event['name'] as String? ?? 'Device',
                code: code,
              ),
            );
          }
          _connController.add(TransportConnectionState.connecting);
        case 'connected':
          final id = event['endpointId'] as String?;
          if (id == null) return;
          _endpointByPeerId[id] = id;
          _peers[id] = Peer(id: id, name: event['name'] as String? ?? 'Guest');
          _peersController.add(_peers.values.toList());
          _connController.add(TransportConnectionState.connected);
          final completer = _joinCompleters[id];
          if (completer != null && !completer.isCompleted) completer.complete();
        case 'payload':
          final raw = event['payload'] as String?;
          if (raw == null) return;
          try {
            final messageBytes = _frames.add(base64Decode(raw));
            if (messageBytes != null) {
              final message = SessionMessage.decode(utf8.decode(messageBytes));
              final endpointId = event['endpointId'] as String?;
              if (endpointId != null) {
                _endpointByPeerId[message.senderId] = endpointId;
                _peers.remove(endpointId);
                _peers[message.senderId] = Peer(
                  id: message.senderId,
                  name: message.senderName,
                );
                _peersController.add(_peers.values.toList());
              }
              _messageController.add(message);
            }
          } catch (_) {}
        case 'disconnected':
          final id = event['endpointId'] as String?;
          final platformCode = event['code'] as String?;
          final failure = platformCode == null
              ? null
              : NearbyBridge.failureForCode(platformCode);
          if (failure != null) _errorController.add(failure);
          if (id != null) {
            _peers.remove(id);
            final appIds = _endpointByPeerId.entries
                .where((entry) => entry.value == id)
                .map((entry) => entry.key)
                .toList();
            for (final appId in appIds) {
              _endpointByPeerId.remove(appId);
              _peers.remove(appId);
            }
            final completer = _joinCompleters[id];
            if (completer != null && !completer.isCompleted) {
              completer.completeError(
                failure ??
                    const TransportFailure(TransportFailureCode.startupFailure),
              );
            }
          }
          _peersController.add(_peers.values.toList());
          _connController.add(TransportConnectionState.disconnected);
        case 'error':
          final code = event['code'] as String? ?? 'NEARBY_ERROR';
          _errorController.add(NearbyBridge.failureForCode(code));
          _connController.add(TransportConnectionState.error);
      }
    });
  }
}
