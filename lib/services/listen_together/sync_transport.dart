import 'session_message.dart';

/// Which underlying medium a transport uses.
enum TransportKind {
  /// Same Wi-Fi / LAN: mDNS discovery + WebSocket connections.
  lan,

  /// Bluetooth / Wi-Fi-Direct P2P (Nearby Connections / Multipeer).
  nearby,
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

  @override
  bool operator ==(Object other) =>
      other is DiscoveredSession && other.id == id && other.kind == kind;

  @override
  int get hashCode => Object.hash(id, kind);
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

  /// Become the host: publish a discoverable session and accept guests.
  Future<void> startAdvertising(SessionInfo info);

  /// Become a guest browser: emits the current list of discovered host
  /// sessions as they appear/disappear.
  Stream<List<DiscoveredSession>> startDiscovery(SessionInfo self);

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
