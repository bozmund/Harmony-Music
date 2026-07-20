import 'dart:async';

import 'lan_transport.dart';
import 'nearby_transport.dart';
import 'session_message.dart';
import 'sync_transport.dart';

/// Hosts over LAN and Nearby simultaneously and discovers Nearby first, then LAN.
class HybridTransport
    implements
        SyncTransport,
        ConnectionAuthenticatingTransport,
        TransportErrorReporting {
  HybridTransport({LanTransport? lan, NearbyTransport? nearby})
    : _lan = lan ?? LanTransport(),
      _nearby = nearby ?? NearbyTransport() {
    for (final transport in [_nearby, _lan]) {
      _subs.add(transport.onMessage.listen(_messages.add));
      _subs.add(
        transport.connectionState.listen((state) => _onState(transport, state)),
      );
    }
    _subs.add(
      _nearby.peers.listen((value) {
        _updatePeerRoutes(_nearby, _nearbyPeers, value);
        _nearbyPeers = value;
        _emitPeers();
      }),
    );
    _subs.add(
      _lan.peers.listen((value) {
        _updatePeerRoutes(_lan, _lanPeers, value);
        _lanPeers = value;
        _emitPeers();
      }),
    );
    _subs.add(_nearby.confirmations.listen(_confirmations.add));
    _subs.add(_nearby.errors.listen(_errors.add));
  }

  final LanTransport _lan;
  final NearbyTransport _nearby;
  final _messages = StreamController<SessionMessage>.broadcast();
  final _peers = StreamController<List<Peer>>.broadcast();
  final _states = StreamController<TransportConnectionState>.broadcast();
  final _sessions = StreamController<List<DiscoveredSession>>.broadcast();
  final _confirmations = StreamController<ConnectionConfirmation>.broadcast();
  final _errors = StreamController<Object>.broadcast();
  final List<StreamSubscription<dynamic>> _subs = [];
  final List<StreamSubscription<dynamic>> _discoverySubs = [];
  final Map<String, List<DiscoveredSession>> _routes = {};
  final Map<String, SyncTransport> _peerRoutes = {};
  List<Peer> _lanPeers = const [];
  List<Peer> _nearbyPeers = const [];
  SyncTransport? _activeGuestTransport;
  final Map<SyncTransport, TransportConnectionState> _transportStates = {};

  @override
  TransportKind get kind => TransportKind.both;
  @override
  Stream<SessionMessage> get onMessage => _messages.stream;
  @override
  Stream<List<Peer>> get peers => _peers.stream;
  @override
  Stream<TransportConnectionState> get connectionState => _states.stream;
  @override
  Stream<ConnectionConfirmation> get confirmations => _confirmations.stream;
  @override
  Stream<Object> get errors => _errors.stream;
  @override
  Stream<List<DiscoveredSession>> get discoveredSessions => _sessions.stream;

  @override
  Future<void> startAdvertising(SessionInfo info) async {
    Future<({bool started, Object? error})> start(
      SyncTransport transport,
    ) async {
      try {
        await transport.startAdvertising(info);
        return (started: true, error: null);
      } catch (error) {
        return (started: false, error: _startupFailure(error));
      }
    }

    final results = await Future.wait([start(_nearby), start(_lan)]);
    final nearbyResult = results[0];
    final lanResult = results[1];
    if (!nearbyResult.started || !lanResult.started) {
      await Future.wait([_nearby.leave(), _lan.leave()]);
      final error = nearbyResult.error ?? lanResult.error;
      if (error != null) _errors.add(error);
      throw error ??
          const TransportFailure(TransportFailureCode.startupFailure);
    }
  }

  @override
  Future<void> startDiscovery(SessionInfo self) async {
    _watchDiscovery(TransportKind.bluetooth, _nearby.discoveredSessions);
    _watchDiscovery(TransportKind.wifi, _lan.discoveredSessions);

    Future<({bool started, Object? error})> start(
      SyncTransport transport,
    ) async {
      try {
        await transport.startDiscovery(self);
        return (started: true, error: null);
      } catch (error) {
        return (started: false, error: _startupFailure(error));
      }
    }

    final results = await Future.wait([start(_nearby), start(_lan)]);
    if (!results[0].started || !results[1].started) {
      final error = results[0].error ?? results[1].error;
      await leave();
      throw error ??
          const TransportFailure(TransportFailureCode.startupFailure);
    }
  }

  void _watchDiscovery(
    TransportKind kind,
    Stream<List<DiscoveredSession>> stream,
  ) {
    _discoverySubs.add(
      stream.listen((items) {
        for (final entry in _routes.entries) {
          entry.value.removeWhere((item) => item.kind == kind);
        }
        for (final item in items) {
          (_routes[item.id] ??= []).add(item);
        }
        _routes.removeWhere((_, routes) => routes.isEmpty);
        _sessions.add(
          _routes.entries.map((entry) {
            final sorted = [...entry.value]
              ..sort((a, b) {
                if (a.kind == b.kind) return 0;
                return a.kind == TransportKind.bluetooth ? -1 : 1;
              });
            final preferred = sorted.first;
            return DiscoveredSession(
              id: entry.key,
              name: preferred.name,
              kind: preferred.kind,
              host: preferred.host,
              port: preferred.port,
              endpointId: preferred.endpointId,
              raw: preferred.raw,
              routes: sorted,
            );
          }).toList(),
        );
      }, onError: _sessions.addError),
    );
  }

  @override
  Future<void> join(DiscoveredSession session, SessionInfo self) async {
    final routes = session.routes.isEmpty ? [session] : session.routes;
    Object? lastError;
    for (final route in routes) {
      try {
        await (route.kind == TransportKind.bluetooth ? _nearby : _lan).join(
          route,
          self,
        );
        _activeGuestTransport = route.kind == TransportKind.bluetooth
            ? _nearby
            : _lan;
        _states.add(TransportConnectionState.connected);
        return;
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('Could not join session: $lastError');
  }

  @override
  Future<void> send(SessionMessage message) async {
    final active = _activeGuestTransport;
    if (active != null) {
      await active.send(message);
      return;
    }
    await Future.wait([_nearby.send(message), _lan.send(message)]);
  }

  @override
  Future<void> sendTo(String peerId, SessionMessage message) async {
    final active = _activeGuestTransport;
    if (active != null) {
      await active.sendTo(peerId, message);
      return;
    }
    final route = _peerRoutes[peerId];
    if (route != null) await route.sendTo(peerId, message);
  }

  @override
  Future<void> confirmConnection(String endpointId, bool accept) =>
      _nearby.confirmConnection(endpointId, accept);

  void _emitPeers() {
    // Read latest snapshots from transport streams via dedicated subscriptions.
    final merged = <String, Peer>{
      for (final peer in [..._nearbyPeers, ..._lanPeers]) peer.id: peer,
    };
    _peers.add(merged.values.toList());
  }

  void _updatePeerRoutes(
    SyncTransport transport,
    List<Peer> previous,
    List<Peer> current,
  ) {
    final currentIds = current.map((peer) => peer.id).toSet();
    for (final peer in previous) {
      if (!currentIds.contains(peer.id) &&
          identical(_peerRoutes[peer.id], transport)) {
        _peerRoutes.remove(peer.id);
      }
    }
    for (final peer in current) {
      // Nearby wins only when both routes become visible before a disconnect.
      // Removing that route later does not silently switch the peer to LAN.
      if (identical(transport, _nearby) || !_peerRoutes.containsKey(peer.id)) {
        _peerRoutes[peer.id] = transport;
      }
    }
  }

  void _onState(SyncTransport transport, TransportConnectionState state) {
    _transportStates[transport] = state;
    final active = _activeGuestTransport;
    if (active != null) {
      if (identical(active, transport)) _states.add(state);
      return;
    }
    final values = _transportStates.values;
    if (values.contains(TransportConnectionState.connected)) {
      _states.add(TransportConnectionState.connected);
    } else if (values.contains(TransportConnectionState.advertising)) {
      _states.add(TransportConnectionState.advertising);
    } else if (values.contains(TransportConnectionState.discovering)) {
      _states.add(TransportConnectionState.discovering);
    } else if (values.isNotEmpty &&
        values.every((value) => value == TransportConnectionState.error)) {
      _states.add(TransportConnectionState.error);
    }
  }

  @override
  Future<void> leave() async {
    for (final sub in _discoverySubs) {
      await sub.cancel();
    }
    _discoverySubs.clear();
    _routes.clear();
    _sessions.add(const []);
    _activeGuestTransport = null;
    _peerRoutes.clear();
    _nearbyPeers = const [];
    _lanPeers = const [];
    _transportStates.clear();
    await Future.wait([_nearby.leave(), _lan.leave()]);
  }

  @override
  Future<void> dispose() async {
    await leave();
    for (final sub in _subs) {
      await sub.cancel();
    }
    await _nearby.dispose();
    await _lan.dispose();
    await _messages.close();
    await _peers.close();
    await _states.close();
    await _sessions.close();
    await _confirmations.close();
    await _errors.close();
  }

  TransportFailure _startupFailure(Object error) => error is TransportFailure
      ? error
      : const TransportFailure(TransportFailureCode.startupFailure);
}
