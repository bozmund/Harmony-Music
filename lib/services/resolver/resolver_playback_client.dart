import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/repositories/settings_repository.dart';
import 'resolver_audio_source.dart';
import 'resolver_configuration.dart';
import 'resolver_discovery_service.dart';

class ResolverPlaybackClient {
  ResolverPlaybackClient({
    required SettingsRepository settings,
    required Future<String?> Function() accessToken,
    bool enabled = true,
    ResolverDiscoveryService? discovery,
  }) : _settings = settings,
       _accessToken = accessToken,
       _enabled = enabled,
       _discovery = discovery;

  final SettingsRepository _settings;
  final Future<String?> Function() _accessToken;
  final bool _enabled;
  final ResolverDiscoveryService? _discovery;

  Future<ResolverAudioSource?> open(String videoId) async {
    if (!_enabled) return null;
    final configuration = ResolverConfiguration.load(_settings);
    final baseUrl = configuration.baseUrl;
    if (!configuration.enabled || baseUrl == null) return null;
    final primary = await _openAt(
      baseUrl,
      videoId,
      configuration,
      allowDebugToken: true,
    );
    if (primary != null || configuration.isProduction || _discovery == null) {
      return primary;
    }
    try {
      final discovered = await _discovery.discover();
      for (final endpoint in discovered.where((item) => item != baseUrl)) {
        final source = await _openAt(
          endpoint,
          videoId,
          configuration,
          allowDebugToken: false,
        );
        if (source != null) return source;
      }
    } catch (_) {}
    return null;
  }

  Future<ResolverAudioSource?> _openAt(
    Uri baseUrl,
    String videoId,
    ResolverConfiguration configuration, {
    required bool allowDebugToken,
  }) async {
    final uri = baseUrl.resolve('/v1/tracks/$videoId/audio');
    final headers = <String, String>{'Accept': 'audio/ogg'};
    if (baseUrl.scheme == 'https' ||
        (!configuration.isProduction && allowDebugToken)) {
      final token = await _accessToken();
      if (token != null && token.isNotEmpty) {
        headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
      }
    }

    for (var attempt = 0; attempt < 4; attempt++) {
      final client = HttpClient();
      try {
        final request = await client.getUrl(uri);
        headers.forEach(request.headers.set);
        final response = await request.close();
        if (response.statusCode == HttpStatus.accepted) {
          final retryAfter =
              int.tryParse(
                response.headers.value(HttpHeaders.retryAfterHeader) ?? '',
              ) ??
              2;
          await response.drain<void>();
          client.close();
          await Future<void>.delayed(Duration(seconds: retryAfter.clamp(1, 3)));
          continue;
        }
        final mimeType = response.headers.contentType?.mimeType;
        if ((response.statusCode != HttpStatus.ok &&
                response.statusCode != HttpStatus.partialContent) ||
            mimeType != 'audio/ogg') {
          await response.drain<void>();
          client.close(force: true);
          return null;
        }
        final iterator = StreamIterator<List<int>>(response);
        final prefix = BytesBuilder(copy: false);
        while (prefix.length < 4 && await iterator.moveNext()) {
          prefix.add(iterator.current);
        }
        final bytes = prefix.takeBytes();
        if (bytes.length < 4 ||
            bytes[0] != 0x4f ||
            bytes[1] != 0x67 ||
            bytes[2] != 0x67 ||
            bytes[3] != 0x53) {
          await iterator.cancel();
          client.close(force: true);
          return null;
        }
        return ResolverAudioSource(
          uri: uri,
          headers: headers,
          initialClient: client,
          initialResponse: response,
          initialIterator: iterator,
          initialPrefix: Uint8List.fromList(bytes),
        );
      } catch (_) {
        client.close(force: true);
        return null;
      }
    }
    return null;
  }
}
