import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../utils/helper.dart';
import '../constant.dart';
import 'heos_models.dart';

class HeosClient {
  HeosClient({this.timeout = const Duration(seconds: 5)});

  final Duration timeout;
  Socket? _socket;
  StreamSubscription<String>? _subscription;
  final _pending = <_PendingHeosCommand>[];

  bool get isConnected => _socket != null;

  Future<void> connect(String host) async {
    await close();
    final socket = await Socket.connect(host, 1255, timeout: timeout);
    _socket = socket;
    _subscription = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine, onError: _handleSocketError, onDone: _failAll);
  }

  Future<List<HeosPlayer>> getPlayers() async {
    final response = await send('heos://player/get_players');
    return response.payload
        .whereType<Map>()
        .map((item) => HeosPlayer.fromJson(Map<String, dynamic>.from(item)))
        .where((player) => player.pid.isNotEmpty)
        .toList();
  }

  Future<void> playStream({
    required String playerId,
    required String url,
  }) async {
    await send(
      heosCommand('browse/play_stream', {'pid': playerId, 'url': url}),
    );
  }

  Future<void> setPlayState({
    required String playerId,
    required String state,
  }) async {
    await send(
      heosCommand('player/set_play_state', {'pid': playerId, 'state': state}),
    );
  }

  Future<void> setVolume({required String playerId, required int level}) async {
    await send(
      heosCommand('player/set_volume', {
        'pid': playerId,
        'level': level.clamp(0, 100).toString(),
      }),
    );
  }

  Future<HeosResponse> send(String command) async {
    final socket = _socket;
    if (socket == null) {
      throw const SocketException('HEOS client is not connected');
    }
    final pending = _PendingHeosCommand(command, timeout);
    _pending.add(pending);
    socket.write('$command\r\n');
    await socket.flush();
    return pending.future;
  }

  void _handleLine(String line) {
    if (line.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) return;
      final response = HeosResponse.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      final index = _pending.indexWhere(
        (pending) => response.command == _commandName(pending.command),
      );
      if (index == -1) return;
      final pending = _pending.removeAt(index);
      pending.complete(response);
    } catch (error, stackTrace) {
      printERROR('Unable to parse HEOS response: $error', tag: LogTags.heos);
      printERROR(stackTrace, tag: LogTags.heos);
    }
  }

  void _handleSocketError(Object error, StackTrace stackTrace) {
    printERROR('HEOS socket error: $error', tag: LogTags.heos);
    printERROR(stackTrace, tag: LogTags.heos);
    _failAll(error);
  }

  void _failAll([Object? error]) {
    final failure = error ?? const SocketException('HEOS connection closed');
    final pending = List<_PendingHeosCommand>.from(_pending);
    _pending.clear();
    for (final command in pending) {
      command.completeError(failure);
    }
  }

  Future<void> close() async {
    _failAll();
    await _subscription?.cancel();
    _subscription = null;
    final socket = _socket;
    _socket = null;
    socket?.destroy();
  }
}

String heosCommand(String command, Map<String, String> parameters) {
  final buffer = StringBuffer('heos://$command');
  if (parameters.isEmpty) return buffer.toString();
  buffer.write('?');
  var first = true;
  for (final entry in parameters.entries) {
    if (!first) buffer.write('&');
    first = false;
    buffer
      ..write(Uri.encodeQueryComponent(entry.key))
      ..write('=')
      ..write(Uri.encodeQueryComponent(entry.value));
  }
  return buffer.toString();
}

String _commandName(String command) {
  final uri = Uri.tryParse(command);
  if (uri == null || uri.host.isEmpty) return command;
  final path = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
  return path.isEmpty ? uri.host : '${uri.host}/$path';
}

class _PendingHeosCommand {
  _PendingHeosCommand(this.command, Duration timeout) {
    _timer = Timer(timeout, () {
      completeError(TimeoutException('HEOS command timed out', timeout));
    });
  }

  final String command;
  final _completer = Completer<HeosResponse>();
  late final Timer _timer;

  Future<HeosResponse> get future => _completer.future;

  void complete(HeosResponse response) {
    if (_completer.isCompleted) return;
    _timer.cancel();
    if (response.isSuccess) {
      _completer.complete(response);
    } else {
      _completer.completeError(
        StateError('HEOS command failed: ${response.message}'),
      );
    }
  }

  void completeError(Object error) {
    if (_completer.isCompleted) return;
    _timer.cancel();
    _completer.completeError(error);
  }
}
