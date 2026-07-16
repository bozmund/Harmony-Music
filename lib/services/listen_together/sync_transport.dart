import 'session_message.dart';

/// Which underlying medium a transport uses.
enum TransportKind {
  /// Same Wi-Fi / LAN: mDNS discovery + WebSocket connections.
  wifi,

  /// Bluetooth Low Energy through Nearby Connections low-power mode.
  bluetooth,

  /// Bluetooth and Wi-Fi discovery run concurrently.
  both,
}

enum TransportFailureCode {
  bluetoothDisabled,
  wifiDisabled,
  permissionDenied,
  playServicesUnavailable,
  radioFailure,
  startupFailure,
}

class TransportFailure implements Exception {
  const TransportFailure(this.code, {this.platformCode});

  final TransportFailureCode code;
  final String? platformCode;

  @override
  String toString() => 'TransportFailure(${code.name}, $platformCode)';
}

class TransportAvailability {
  const TransportAvailability({
    required this.bluetoothEnabled,
    required this.wifiEnabled,
    required this.playServicesAvailable,
    this.bluetoothPermissionGranted = true,
  });

  final bool bluetoothEnabled;
  final bool wifiEnabled;
  final bool playServicesAvailable;
  final bool bluetoothPermissionGranted;

  bool supports(TransportKind kind) => switch (kind) {
    TransportKind.bluetooth =>
      bluetoothEnabled && playServicesAvailable && bluetoothPermissionGranted,
    TransportKind.wifi => wifiEnabled,
    TransportKind.both =>
      bluetoothEnabled &&
          wifiEnabled &&
          playServicesAvailable &&
          bluetoothPermissionGranted,
  };
}

/// Coarse lifecycle state shared by every transport, surfaced to the UI.
enum TransportConnectionState {
  idle,
  advertising,
  discovering,
  connecting,
  connected,
  disconnected,
  error,
}

/// Identity of the local participant, chosen when hosting or joining.
class SessionInfo {
  const SessionInfo({required this.id, required this.name});

  /// Stable per-app-instance id (uuid-ish). Used to de-duplicate peers and to
  /// ignore our own advertised service during discovery.
  final String id;

  /// Human-readable display name (e.g. device name).
  final String name;
}

/// A remote participant currently connected to the session.
class Peer {
  const Peer({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, String> toJson() => {'id': id, 'name': name};

  factory Peer.fromJson(Map<String, String> json) =>
      Peer(id: json['id'] ?? '', name: json['name'] ?? '');

  @override
  bool operator ==(Object other) => other is Peer && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A host session found during discovery that a guest can [SyncTransport.join].
class DiscoveredSession {
  const DiscoveredSession({
    required this.id,
    required this.name,
    required this.kind,
    this.host,
    this.port,
    this.endpointId,
    this.raw,
    this.routes = const [],
  });

  final String id;
  final String name;
  final TransportKind kind;

  /// LAN only: resolved host address + port of the host's WebSocket server.
  final String? host;
  final int? port;

  /// Nearby only: opaque endpoint id used to request a connection.
  final String? endpointId;

  /// Transport-specific raw handle (e.g. the underlying discovered service).
  final Object? raw;
  final List<DiscoveredSession> routes;

  @override
  bool operator ==(Object other) =>
      other is DiscoveredSession && other.id == id && other.kind == kind;

  @override
  int get hashCode => Object.hash(id, kind);
}

class ConnectionConfirmation {
  const ConnectionConfirmation({
    required this.endpointId,
    required this.name,
    required this.code,
  });
  final String endpointId;
  final String name;
  final String code;
}

abstract interface class ConnectionAuthenticatingTransport {
  Stream<ConnectionConfirmation> get confirmations;
  Future<void> confirmConnection(String endpointId, bool accept);
}

/// Optional channel for recoverable transport failures.
abstract interface class TransportErrorReporting {
  Stream<Object> get errors;
}

/// Abstraction over "how phones find and talk to each other". A concrete
/// transport handles discovery and message delivery; the
/// `ListenTogetherController` sits on top and speaks [SessionMessage] without
/// caring whether the bytes travel over Wi-Fi or Bluetooth.
///
/// Topology is a star: exactly one host advertises and every guest connects to
/// it. The host is responsible for relaying/broadcasting to all guests.
abstract class SyncTransport {
  TransportKind get kind;

  /// Inbound messages from any peer (host receives from guests and vice-versa).
  Stream<SessionMessage> get onMessage;

  /// The current set of connected peers. On the host this is every guest; on a
  /// guest it is the host (and, via [SessionMessageType.peerList], the roster).
  Stream<List<Peer>> get peers;

  /// Coarse connection lifecycle for the UI.
  Stream<TransportConnectionState> get connectionState;

  /// Current discovery results. The stream remains valid across repeated
  /// discovery sessions until [dispose].
  Stream<List<DiscoveredSession>> get discoveredSessions;

  /// Become the host: publish a discoverable session and accept guests.
  Future<void> startAdvertising(SessionInfo info);

  /// Become a guest browser. Completes only after discovery has started, so
  /// startup failures can be presented before the UI enters searching state.
  Future<void> startDiscovery(SessionInfo self);

  /// Connect to a discovered host session as a guest.
  Future<void> join(DiscoveredSession session, SessionInfo self);

  /// Broadcast to all connected peers.
  Future<void> send(SessionMessage message);

  /// Send to a single peer by id.
  Future<void> sendTo(String peerId, SessionMessage message);

  /// Tear down the current session (stop advertising/discovery, close sockets)
  /// but keep the transport reusable.
  Future<void> leave();

  /// Release all resources permanently.
  Future<void> dispose();
}
