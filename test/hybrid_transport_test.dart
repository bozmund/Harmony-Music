import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/listen_together/hybrid_transport.dart';
import 'package:harmonymusic/services/listen_together/lan_transport.dart';
import 'package:harmonymusic/services/listen_together/nearby_transport.dart';
import 'package:harmonymusic/services/listen_together/session_message.dart';
import 'package:harmonymusic/services/listen_together/sync_transport.dart';

void main() {
  const self = SessionInfo(id: 'self', name: 'Me');
  test('merges duplicate routes and prefers Nearby', () async {
    final lan = _FakeLan();
    final nearby = _FakeNearby();
    final hybrid = HybridTransport(lan: lan, nearby: nearby);
    final values = <List<DiscoveredSession>>[];
    final sub = hybrid.discoveredSessions.listen(values.add);
    await hybrid.startDiscovery(self);
    await Future<void>.delayed(Duration.zero);
    nearby.sessions.add(const [
      DiscoveredSession(
        id: 'host',
        name: 'Host',
        kind: TransportKind.bluetooth,
        endpointId: 'near',
      ),
    ]);
    lan.sessions.add(const [
      DiscoveredSession(
        id: 'host',
        name: 'Host',
        kind: TransportKind.wifi,
        host: '1.2.3.4',
        port: 9,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(values.last, hasLength(1));
    expect(values.last.single.kind, TransportKind.bluetooth);
    expect(values.last.single.routes, hasLength(2));
    await sub.cancel();
    await hybrid.dispose();
  });

  test('falls back to LAN join when Nearby fails', () async {
    final lan = _FakeLan();
    final nearby = _FakeNearby()..failJoin = true;
    final hybrid = HybridTransport(lan: lan, nearby: nearby);
    await hybrid.join(
      const DiscoveredSession(
        id: 'host',
        name: 'Host',
        kind: TransportKind.bluetooth,
        routes: [
          DiscoveredSession(
            id: 'host',
            name: 'Host',
            kind: TransportKind.bluetooth,
            endpointId: 'near',
          ),
          DiscoveredSession(
            id: 'host',
            name: 'Host',
            kind: TransportKind.wifi,
            host: 'x',
            port: 1,
          ),
        ],
      ),
      self,
    );
    expect(nearby.joinCount, 1);
    expect(lan.joinCount, 1);
    await hybrid.send(
      SessionMessage.bye(senderId: self.id, senderName: self.name),
    );
    expect(nearby.sendCount, 0);
    expect(lan.sendCount, 1);
    await hybrid.dispose();
  });

  test('direct host replies use only the peer owning transport', () async {
    final lan = _FakeLan();
    final nearby = _FakeNearby();
    final hybrid = HybridTransport(lan: lan, nearby: nearby);
    lan.peerValues.add(const [Peer(id: 'lan-guest', name: 'Guest')]);
    await Future<void>.delayed(Duration.zero);

    await hybrid.sendTo(
      'lan-guest',
      SessionMessage.bye(senderId: 'host', senderName: 'Host'),
    );

    expect(lan.sendToCount, 1);
    expect(nearby.sendToCount, 0);
    await hybrid.dispose();
  });

  test('fails atomically when Bluetooth advertising cannot start', () async {
    final lan = _FakeLan();
    final nearby = _FakeNearby()..failAdvertising = true;
    final hybrid = HybridTransport(lan: lan, nearby: nearby);
    final error = expectLater(hybrid.errors, emits(isA<TransportFailure>()));

    await expectLater(
      hybrid.startAdvertising(self),
      throwsA(isA<TransportFailure>()),
    );

    await error;
    await hybrid.dispose();
  });

  test('fails atomically when Wi-Fi advertising cannot start', () async {
    final lan = _FakeLan()..failAdvertising = true;
    final nearby = _FakeNearby();
    final hybrid = HybridTransport(lan: lan, nearby: nearby);
    final error = expectLater(hybrid.errors, emits(isA<TransportFailure>()));

    await expectLater(
      hybrid.startAdvertising(self),
      throwsA(isA<TransportFailure>()),
    );

    await error;
    await hybrid.dispose();
  });

  test(
    'fails discovery atomically when either transport cannot start',
    () async {
      final lan = _FakeLan()..failDiscovery = true;
      final nearby = _FakeNearby();
      final hybrid = HybridTransport(lan: lan, nearby: nearby);

      await expectLater(
        hybrid.startDiscovery(self),
        throwsA(isA<TransportFailure>()),
      );

      await hybrid.dispose();
    },
  );

  test('leaving discovery clears routes and old transport listeners', () async {
    final lan = _FakeLan();
    final nearby = _FakeNearby();
    final hybrid = HybridTransport(lan: lan, nearby: nearby);
    final firstValues = <List<DiscoveredSession>>[];
    final firstSub = hybrid.discoveredSessions.listen(firstValues.add);
    await hybrid.startDiscovery(self);
    nearby.sessions.add(const [
      DiscoveredSession(
        id: 'old-host',
        name: 'Old host',
        kind: TransportKind.bluetooth,
        endpointId: 'old',
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(firstValues.last.single.id, 'old-host');

    await hybrid.leave();
    final secondValues = <List<DiscoveredSession>>[];
    final secondSub = hybrid.discoveredSessions.listen(secondValues.add);
    await hybrid.startDiscovery(self);
    nearby.sessions.add(const [
      DiscoveredSession(
        id: 'new-host',
        name: 'New host',
        kind: TransportKind.bluetooth,
        endpointId: 'new',
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(secondValues, hasLength(1));
    expect(secondValues.single.single.id, 'new-host');
    await firstSub.cancel();
    await secondSub.cancel();
    await hybrid.dispose();
  });
}

mixin _FakeBase implements SyncTransport {
  final messages = StreamController<SessionMessage>.broadcast();
  final peerValues = StreamController<List<Peer>>.broadcast();
  final states = StreamController<TransportConnectionState>.broadcast();
  final sessions = StreamController<List<DiscoveredSession>>.broadcast();
  int joinCount = 0;
  int sendCount = 0;
  int sendToCount = 0;
  @override
  Stream<SessionMessage> get onMessage => messages.stream;
  @override
  Stream<List<Peer>> get peers => peerValues.stream;
  @override
  Stream<TransportConnectionState> get connectionState => states.stream;
  @override
  Stream<List<DiscoveredSession>> get discoveredSessions => sessions.stream;
  @override
  Future<void> startAdvertising(SessionInfo info) async {}
  @override
  Future<void> startDiscovery(SessionInfo self) async {}
  @override
  Future<void> send(SessionMessage message) async {
    sendCount++;
  }

  @override
  Future<void> sendTo(String peerId, SessionMessage message) async {
    sendToCount++;
  }

  @override
  Future<void> leave() async {}
  @override
  Future<void> dispose() async {
    await messages.close();
    await peerValues.close();
    await states.close();
    await sessions.close();
  }
}

class _FakeLan extends LanTransport with _FakeBase {
  bool failAdvertising = false;
  bool failDiscovery = false;

  @override
  TransportKind get kind => TransportKind.wifi;
  @override
  Future<void> startAdvertising(SessionInfo info) async {
    if (failAdvertising) throw StateError('LAN unavailable');
  }

  @override
  Future<void> startDiscovery(SessionInfo self) async {
    if (failDiscovery) throw StateError('LAN discovery unavailable');
  }

  @override
  Future<void> join(DiscoveredSession session, SessionInfo self) async {
    joinCount++;
  }
}

class _FakeNearby extends NearbyTransport with _FakeBase {
  _FakeNearby();
  bool failJoin = false;
  bool failAdvertising = false;
  final confirmationValues =
      StreamController<ConnectionConfirmation>.broadcast();
  @override
  Stream<ConnectionConfirmation> get confirmations => confirmationValues.stream;
  @override
  TransportKind get kind => TransportKind.bluetooth;
  @override
  Future<void> startAdvertising(SessionInfo info) async {
    if (failAdvertising) throw StateError('nearby unavailable');
  }

  @override
  Future<void> join(DiscoveredSession session, SessionInfo self) async {
    joinCount++;
    if (failJoin) throw StateError('no nearby');
  }

  @override
  Future<void> confirmConnection(String endpointId, bool accept) async {}
  @override
  Future<void> dispose() async {
    await confirmationValues.close();
    await messages.close();
    await peerValues.close();
    await states.close();
    await sessions.close();
  }
}
