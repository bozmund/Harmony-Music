import 'dart:async';
import 'dart:io';
import 'dart:math';

class HeosLocalHttpServer {
  HttpServer? _server;
  File? _activeFile;
  String? _token;
  bool _isListening = false;

  Future<String> serveFile(String path) async {
    final file = _fileFromPath(path);
    if (!await file.exists()) {
      throw FileSystemException('Local audio file not found', file.path);
    }
    _activeFile = file;
    _token = _randomToken();
    _server ??= await HttpServer.bind(InternetAddress.anyIPv4, 0);
    if (!_isListening) {
      _isListening = true;
      _server!.listen(_handleRequest, onError: (_) {});
    }
    final host = await _lanIpv4Address();
    final encodedName = Uri.encodeComponent(file.uri.pathSegments.last);
    return 'http://$host:${_server!.port}/heos/$_token/$encodedName';
  }

  File _fileFromPath(String path) {
    final uri = Uri.tryParse(path);
    if (uri != null && uri.scheme == 'file') {
      return File(uri.toFilePath());
    }
    return File(path);
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _activeFile = null;
    _token = null;
    _isListening = false;
    await server?.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final file = _activeFile;
    final token = _token;
    if (file == null ||
        token == null ||
        request.uri.pathSegments.length < 2 ||
        request.uri.pathSegments[0] != 'heos' ||
        request.uri.pathSegments[1] != token) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    request.response.headers.contentType = ContentType(
      'audio',
      _contentSubtype(file.path),
    );
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    await file.openRead().pipe(request.response);
  }

  Future<String> _lanIpv4Address() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback && address.address.isNotEmpty) {
          return address.address;
        }
      }
    }
    return InternetAddress.loopbackIPv4.address;
  }

  String _contentSubtype(String path) {
    final lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('.m4a') || lowerPath.endsWith('.mp4')) {
      return 'mp4';
    }
    if (lowerPath.endsWith('.aac')) return 'aac';
    if (lowerPath.endsWith('.ogg') || lowerPath.endsWith('.opus')) {
      return 'ogg';
    }
    if (lowerPath.endsWith('.wav')) return 'wav';
    return 'mpeg';
  }

  String _randomToken() {
    final random = Random.secure();
    final values = List<int>.generate(16, (_) => random.nextInt(256));
    return values
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
