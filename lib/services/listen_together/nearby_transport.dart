import 'dart:async';

import 'session_message.dart';
import 'sync_transport.dart';

/// Bluetooth / Wi-Fi-Direct P2P transport (Nearby Connections / Multipeer).
///
/// NOTE: This is currently a stub. The obvious cross-platform package for this
/// (`flutter_nearby_connections`) is abandoned and references Flutter's removed
/// v1 Android embedding (`PluginRegistry.Registrar`), so it does not compile
/// against modern Flutter SDKs. To keep the app building, the Bluetooth path is
/// disabled for now and reports as unavailable.
///
/// The full working implementation (against `flutter_nearby_connections`'s API)
/// lives in git history and can be restored once a compatible plugin is chosen
/// — e.g. the Android-only `nearby_connections` package, or a maintained fork.
/// All the surrounding code (protocol, controller, UI) is transport-agnostic,
/// so re-enabling BT only means filling in this class.
class NearbyTransport implements SyncTransport {
  @override
  TransportKind get kind => TransportKind.nearby;

  final _messageController = StreamController<SessionMessage>.broadcast();
  final _peersController = StreamController<List<Peer>>.broadcast();
  final _connController =
      StreamController<TransportConnectionState>.broadcast();

  @override
  Stream<SessionMessage> get onMessage => _messageController.stream;
  @override
  Stream<List<Peer>> get peers => _peersController.stream;
  @override
  Stream<TransportConnectionState> get connectionState =>
      _connController.stream;

  static const String _unavailable =
      'Bluetooth listening is not available yet — use Wi-Fi for now.';

  @override
  Future<void> startAdvertising(SessionInfo info) async =>
      throw UnsupportedError(_unavailable);

  @override
  Stream<List<DiscoveredSession>> startDiscovery(SessionInfo self) =>
      Stream<List<DiscoveredSession>>.error(UnsupportedError(_unavailable));

  @override
  Future<void> join(DiscoveredSession session, SessionInfo self) async =>
      throw UnsupportedError(_unavailable);

  @override
  Future<void> send(SessionMessage message) async {}

  @override
  Future<void> sendTo(String peerId, SessionMessage message) async {}

  @override
  Future<void> leave() async {}

  @override
  Future<void> dispose() async {
    await _messageController.close();
    await _peersController.close();
    await _connController.close();
  }
}
