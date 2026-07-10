import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nsd/nsd.dart' as nsd;

import '../constant.dart';
import '../../utils/helper.dart';
import 'session_message.dart';
import 'sync_transport.dart';

/// Same-Wi-Fi transport: mDNS (via `nsd`) for discovery and a `dart:io`
/// WebSocket server/clients for messaging. Star topology — the host runs the
/// WebSocket server and every guest connects to it.
class LanTransport implements SyncTransport {
  static const String _serviceType = '_harmonymusic._tcp';
  static const String _txtIdKey = 'id';

  @override
  TransportKind get kind => TransportKind.lan;

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

  // Host side ----------------------------------------------------------------
  HttpServer? _server;
  nsd.Registration? _registration;
  final Set<WebSocket> _guestSockets = {};
  final Map<String, WebSocket> _socketByPeerId = {};
  final Map<String, String> _nameByPeerId = {};

  // Guest side ----------------------------------------------------------------
  WebSocket? _hostSocket;

  // Discovery -----------------------------------------------------------------
  nsd.Discovery? _discovery;
  StreamController<List<DiscoveredSession>>? _discoveryController;
  void Function()? _discoveryListener;

  bool get _isHost => _server != null;

  // ---------------------------------------------------------------------------
  // Host
  // ---------------------------------------------------------------------------

  @override
  Future<void> startAdvertising(SessionInfo info) async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    server.listen(
      _handleHttpRequest,
      onError:
          (Object e) =>
              printERROR('server error: $e', tag: LogTags.listenTogether),
    );

    _registration = await nsd.register(
      nsd.Service(
        name: info.name,
        type: _serviceType,
        port: server.port,
        txt: {_txtIdKey: Uint8List.fromList(utf8.encode(info.id))},
      ),
    );
    _emitConn(TransportConnectionState.advertising);
    printINFO(
      'LAN advertising on port ${server.port}',
      tag: LogTags.listenTogether,
    );
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    _guestSockets.add(socket);
    _emitConn(TransportConnectionState.connected);
    socket.listen(
      (dynamic data) => _onHostSocketData(socket, data),
      onDone: () => _removeGuestSocket(socket),
      onError: (Object e) {
        printERROR('guest socket error: $e', tag: LogTags.listenTogether);
        _removeGuestSocket(socket);
      },
      cancelOnError: true,
    );
  }

  void _onHostSocketData(WebSocket socket, dynamic data) {
    final message = _tryDecode(data);
    if (message == null) return;
    // Learn the guest's identity from any message it sends.
    if (!_socketByPeerId.containsKey(message.senderId)) {
      _socketByPeerId[message.senderId] = socket;
      _nameByPeerId[message.senderId] = message.senderName;
      _emitPeers();
    } else if (_nameByPeerId[message.senderId] != message.senderName) {
      _nameByPeerId[message.senderId] = message.senderName;
      _emitPeers();
    }
    if (message.type == SessionMessageType.bye) {
      _removeGuestSocket(socket);
    }
    _messageController.add(message);
  }

  void _removeGuestSocket(WebSocket socket) {
    _guestSockets.remove(socket);
    final peerId =
        _socketByPeerId.entries
            .cast<MapEntry<String, WebSocket>?>()
            .firstWhere((e) => e!.value == socket, orElse: () => null)
            ?.key;
    if (peerId != null) {
      _socketByPeerId.remove(peerId);
      _nameByPeerId.remove(peerId);
    }
    unawaited(socket.close());
    _emitPeers();
  }

  void _emitPeers() {
    if (_isHost) {
      _peersController.add(
        _socketByPeerId.keys
            .map((id) => Peer(id: id, name: _nameByPeerId[id] ?? 'Guest'))
            .toList(),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Discovery (guest)
  // ---------------------------------------------------------------------------

  @override
  Stream<List<DiscoveredSession>> startDiscovery(SessionInfo self) {
    final controller = StreamController<List<DiscoveredSession>>.broadcast();
    _discoveryController = controller;

    unawaited(() async {
      try {
        final discovery = await nsd.startDiscovery(
          _serviceType,
          ipLookupType: nsd.IpLookupType.v4,
        );
        _discovery = discovery;
        void listener() {
          final sessions = <DiscoveredSession>[];
          for (final service in discovery.services) {
            final id = _serviceId(service);
            if (id == null || id == self.id) continue; // skip self
            final host = _hostFor(service);
            if (host == null || service.port == null) continue;
            sessions.add(
              DiscoveredSession(
                id: id,
                name: service.name ?? 'Session',
                kind: TransportKind.lan,
                host: host,
                port: service.port,
                raw: service,
              ),
            );
          }
          controller.add(sessions);
        }

        _discoveryListener = listener;
        discovery.addListener(listener);
        listener();
        _emitConn(TransportConnectionState.discovering);
      } catch (e) {
        printERROR('startDiscovery failed: $e', tag: LogTags.listenTogether);
        controller.addError(e);
      }
    }());

    return controller.stream;
  }

  String? _serviceId(nsd.Service service) {
    final raw = service.txt?[_txtIdKey];
    if (raw == null) return null;
    return utf8.decode(raw);
  }

  /// Prefer a resolved IP (from [nsd.IpLookupType.v4]) over the mDNS hostname,
  /// which may be a `.local` name that some platforms cannot resolve.
  String? _hostFor(nsd.Service service) {
    final addresses = service.addresses;
    if (addresses != null && addresses.isNotEmpty) {
      return addresses.first.address;
    }
    return service.host;
  }

  // ---------------------------------------------------------------------------
  // Join (guest)
  // ---------------------------------------------------------------------------

  @override
  Future<void> join(DiscoveredSession session, SessionInfo self) async {
    _emitConn(TransportConnectionState.connecting);
    final host = session.host;
    final port = session.port;
    if (host == null || port == null) {
      throw StateError('Discovered session is missing host/port');
    }
    final socket = await WebSocket.connect('ws://$host:$port');
    _hostSocket = socket;
    // Surface the host as our single peer until the roster arrives.
    _peersController.add([Peer(id: session.id, name: session.name)]);
    socket.listen(
      (dynamic data) {
        final message = _tryDecode(data);
        if (message != null) _messageController.add(message);
      },
      onDone: () => _emitConn(TransportConnectionState.disconnected),
      onError: (Object e) {
        printERROR('host socket error: $e', tag: LogTags.listenTogether);
        _emitConn(TransportConnectionState.error);
      },
      cancelOnError: true,
    );
    _emitConn(TransportConnectionState.connected);
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  @override
  Future<void> send(SessionMessage message) async {
    final raw = message.encode();
    if (_isHost) {
      for (final socket in _guestSockets.toList()) {
        _safeAdd(socket, raw);
      }
    } else {
      _safeAdd(_hostSocket, raw);
    }
  }

  @override
  Future<void> sendTo(String peerId, SessionMessage message) async {
    final raw = message.encode();
    if (_isHost) {
      _safeAdd(_socketByPeerId[peerId], raw);
    } else {
      _safeAdd(_hostSocket, raw); // guest only ever talks to the host
    }
  }

  void _safeAdd(WebSocket? socket, String raw) {
    if (socket == null || socket.readyState != WebSocket.open) return;
    try {
      socket.add(raw);
    } catch (e) {
      printERROR('socket add failed: $e', tag: LogTags.listenTogether);
    }
  }

  SessionMessage? _tryDecode(dynamic data) {
    try {
      if (data is String) return SessionMessage.decode(data);
      if (data is List<int>) return SessionMessage.decodeBytes(data);
    } catch (e) {
      printERROR('decode failed: $e', tag: LogTags.listenTogether);
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Teardown
  // ---------------------------------------------------------------------------

  @override
  Future<void> leave() async {
    // Discovery
    final listener = _discoveryListener;
    if (_discovery != null && listener != null) {
      _discovery!.removeListener(listener);
    }
    if (_discovery != null) {
      try {
        await _bounded(nsd.stopDiscovery(_discovery!), 'stopDiscovery');
      } catch (_) {}
    }
    _discovery = null;
    _discoveryListener = null;
    await _bounded(_discoveryController?.close(), 'discovery close');
    _discoveryController = null;

    // Guest socket
    await _bounded(_hostSocket?.close(), 'host socket close');
    _hostSocket = null;

    // Host sockets + service
    for (final socket in _guestSockets.toList()) {
      await _bounded(socket.close(), 'guest socket close');
    }
    _guestSockets.clear();
    _socketByPeerId.clear();
    _nameByPeerId.clear();
    if (_registration != null) {
      try {
        await _bounded(nsd.unregister(_registration!), 'unregister');
      } catch (_) {}
    }
    _registration = null;
    await _bounded(_server?.close(force: true), 'server close');
    _server = null;

    _emitConn(TransportConnectionState.idle);
  }

  Future<void> _bounded(Future<void>? future, String label) async {
    if (future == null) return;
    try {
      await future.timeout(_leaveStepTimeout);
    } on TimeoutException {
      printERROR('$label timed out during leave', tag: LogTags.listenTogether);
    } catch (e) {
      printERROR('$label failed during leave: $e', tag: LogTags.listenTogether);
    }
  }

  @override
  Future<void> dispose() async {
    await leave();
    await _messageController.close();
    await _peersController.close();
    await _connController.close();
  }

  void _emitConn(TransportConnectionState state) {
    if (_connController.isClosed) return;
    _connController.add(state);
  }

  static const Duration _leaveStepTimeout = Duration(milliseconds: 800);
}
