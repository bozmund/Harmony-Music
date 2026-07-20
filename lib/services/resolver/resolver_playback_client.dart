import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/repositories/settings_repository.dart';
import 'resolver_audio_source.dart';
import 'resolver_configuration.dart';
import 'resolver_discovery_service.dart';

class ResolverOpenCancellation {
  final Set<void Function()> _listeners = <void Function()>{};
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = _listeners.toList();
    _listeners.clear();
    for (final listener in listeners) {
      try {
        listener();
      } catch (_) {
        // Cancellation remains best-effort across every pending operation.
      }
    }
  }

  void Function() _listen(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

class ResolverRequestCancelled implements Exception {
  const ResolverRequestCancelled();
}

class ResolverPlaybackClient {
  ResolverPlaybackClient({
    required SettingsRepository settings,
    required Future<String?> Function() accessToken,
    bool enabled = true,
    ResolverDiscoveryService? discovery,
    HttpClient? httpClient,
    Duration connectionTimeout = defaultConnectionTimeout,
  }) : _settings = settings,
       _accessToken = accessToken,
       _enabled = enabled,
       _discovery = discovery,
       _httpClient = httpClient ?? HttpClient() {
    _httpClient
      ..maxConnectionsPerHost = maxConnectionsPerAuthority
      ..idleTimeout = idleConnectionTimeout
      ..connectionTimeout = connectionTimeout;
  }

  static const maxConnectionsPerAuthority = 4;
  static const idleConnectionTimeout = Duration(minutes: 5);
  static const defaultConnectionTimeout = Duration(seconds: 5);
  static const ingestionPollTimeout = Duration(seconds: 30);

  final SettingsRepository _settings;
  final Future<String?> Function() _accessToken;
  final bool _enabled;
  final ResolverDiscoveryService? _discovery;
  final HttpClient _httpClient;
  Future<void>? _warmUpInFlight;
  bool _disposed = false;

  Future<ResolverAudioSource?> open(
    String videoId, {
    ResolverOpenCancellation? cancellation,
    void Function()? onResponseHeaders,
    void Function()? onFirstEncodedByte,
  }) async {
    if (!_enabled || _disposed || cancellation?.isCancelled == true) {
      return null;
    }
    final configuration = ResolverConfiguration.load(_settings);
    final baseUrl = configuration.baseUrl;
    if (!configuration.enabled || baseUrl == null) return null;

    try {
      final primary = await _openAt(
        baseUrl,
        videoId,
        configuration,
        allowDebugToken: true,
        cancellation: cancellation,
        onResponseHeaders: onResponseHeaders,
        onFirstEncodedByte: onFirstEncodedByte,
      );
      if (primary != null || configuration.isProduction || _discovery == null) {
        return primary;
      }

      final discovered = await _discovery.discover();
      for (final endpoint in discovered.where((item) => item != baseUrl)) {
        _throwIfCancelled(cancellation);
        final source = await _openAt(
          endpoint,
          videoId,
          configuration,
          allowDebugToken: false,
          cancellation: cancellation,
          onResponseHeaders: onResponseHeaders,
          onFirstEncodedByte: onFirstEncodedByte,
        );
        if (source != null) return source;
      }
    } on ResolverRequestCancelled {
      return null;
    } catch (_) {}
    return null;
  }

  Future<ResolverAudioSource?> _openAt(
    Uri baseUrl,
    String videoId,
    ResolverConfiguration configuration, {
    required bool allowDebugToken,
    ResolverOpenCancellation? cancellation,
    void Function()? onResponseHeaders,
    void Function()? onFirstEncodedByte,
  }) async {
    final uri = baseUrl.resolve('v1/tracks/$videoId/audio');
    final headers = <String, String>{'Accept': 'audio/ogg'};
    if (baseUrl.scheme == 'https' ||
        (!configuration.isProduction && allowDebugToken)) {
      final token = await _accessToken();
      if (token != null && token.isNotEmpty) {
        headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
      }
    }

    // A cold miss is filled out-of-band by the downloader fleet. Keep polling
    // within a monotonic deadline while the phone's existing resolver races
    // this request independently.
    final pollingClock = Stopwatch()..start();
    var retriedWithoutToken = false;
    while (true) {
      _throwIfCancelled(cancellation);
      try {
        final request = await _getUrl(uri, cancellation);
        headers.forEach(request.headers.set);
        final response = await _waitForCancellation(
          request.close(),
          cancellation,
          onCancel: () => request.abort(),
        );

        if (response.statusCode == HttpStatus.unauthorized &&
            headers.containsKey(HttpHeaders.authorizationHeader) &&
            !retriedWithoutToken) {
          await response.drain<void>();
          headers.remove(HttpHeaders.authorizationHeader);
          retriedWithoutToken = true;
          continue;
        }
        if (response.statusCode == HttpStatus.accepted) {
          final retryAfter =
              int.tryParse(
                response.headers.value(HttpHeaders.retryAfterHeader) ?? '',
              ) ??
              2;
          await response.drain<void>();
          if (pollingClock.elapsed >= ingestionPollTimeout) return null;
          await _waitForCancellation(
            Future<void>.delayed(Duration(seconds: retryAfter.clamp(1, 5))),
            cancellation,
          );
          continue;
        }

        final mimeType = response.headers.contentType?.mimeType;
        if ((response.statusCode != HttpStatus.ok &&
                response.statusCode != HttpStatus.partialContent) ||
            mimeType != 'audio/ogg') {
          await response.drain<void>();
          return null;
        }

        onResponseHeaders?.call();
        final iterator = StreamIterator<List<int>>(response);
        final prefix = BytesBuilder(copy: false);
        while (prefix.length < 4 &&
            await _waitForCancellation(
              iterator.moveNext(),
              cancellation,
              onCancel: () => unawaited(iterator.cancel()),
            )) {
          prefix.add(iterator.current);
        }
        final bytes = prefix.takeBytes();
        if (bytes.isNotEmpty) onFirstEncodedByte?.call();
        if (bytes.length < 4 ||
            bytes[0] != 0x4f ||
            bytes[1] != 0x67 ||
            bytes[2] != 0x67 ||
            bytes[3] != 0x53) {
          await iterator.cancel();
          return null;
        }

        return ResolverAudioSource(
          uri: uri,
          headers: Map<String, String>.unmodifiable(headers),
          httpClient: _httpClient,
          initialResponse: response,
          initialIterator: iterator,
          initialPrefix: Uint8List.fromList(bytes),
          onResponseHeaders: onResponseHeaders,
          onFirstEncodedByte: onFirstEncodedByte,
        );
      } on ResolverRequestCancelled {
        rethrow;
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> prefetch(List<String> videoIds) async {
    if (videoIds.isEmpty || _disposed) return;
    final configuration = ResolverConfiguration.load(_settings);
    final baseUrl = configuration.baseUrl;
    if (!configuration.enabled || baseUrl == null) return;

    try {
      final token = await _accessToken();
      Future<int> send(String? bearerToken) async {
        final request = await _httpClient.postUrl(
          baseUrl.resolve('v1/prefetch'),
        );
        request.headers.contentType = ContentType.json;
        if (bearerToken != null && bearerToken.isNotEmpty) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $bearerToken',
          );
        }
        request.write(jsonEncode({'videoIds': videoIds.take(3).toList()}));
        final response = await request.close();
        final statusCode = response.statusCode;
        await response.drain<void>();
        return statusCode;
      }

      final statusCode = await send(token);
      if (statusCode == HttpStatus.unauthorized &&
          token != null &&
          token.isNotEmpty) {
        await send(null);
      }
    } catch (_) {
      // Server prefetch is best-effort and must never interrupt playback.
    }
  }

  Future<void> warmUp() {
    if (_disposed || !_enabled) return Future<void>.value();
    final inFlight = _warmUpInFlight;
    if (inFlight != null) return inFlight;

    late final Future<void> task;
    task = _warmUpOnce()
        .catchError((Object _) {
          // Warming is opportunistic and must never delay app or playback.
        })
        .whenComplete(() {
          if (identical(_warmUpInFlight, task)) _warmUpInFlight = null;
        });
    _warmUpInFlight = task;
    return task;
  }

  Future<void> _warmUpOnce() async {
    final configuration = ResolverConfiguration.load(_settings);
    final baseUrl = configuration.baseUrl;
    if (_disposed || !configuration.enabled || baseUrl == null) return;
    final request = await _httpClient.getUrl(baseUrl.resolve('health/live'));
    final response = await request.close();
    await response.drain<void>();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _httpClient.close(force: true);
  }

  void _throwIfCancelled(ResolverOpenCancellation? cancellation) {
    if (_disposed || cancellation?.isCancelled == true) {
      throw const ResolverRequestCancelled();
    }
  }

  Future<HttpClientRequest> _getUrl(
    Uri uri,
    ResolverOpenCancellation? cancellation,
  ) {
    final operation = _httpClient.getUrl(uri);
    return _waitForCancellation(
      operation,
      cancellation,
      onCancel: () {
        unawaited(
          operation.then<void>(
            (request) => request.abort(),
            onError: (Object _, StackTrace __) {},
          ),
        );
      },
    );
  }

  Future<T> _waitForCancellation<T>(
    Future<T> operation,
    ResolverOpenCancellation? cancellation, {
    void Function()? onCancel,
  }) {
    if (cancellation == null) return operation;
    final result = Completer<T>();
    late final void Function() removeCancellationListener;
    removeCancellationListener = cancellation._listen(() {
      if (result.isCompleted) return;
      try {
        onCancel?.call();
      } finally {
        result.completeError(const ResolverRequestCancelled());
      }
    });
    unawaited(
      operation.then<void>(
        (value) {
          removeCancellationListener();
          if (!result.isCompleted) result.complete(value);
        },
        onError: (Object error, StackTrace stackTrace) {
          removeCancellationListener();
          if (!result.isCompleted) result.completeError(error, stackTrace);
        },
      ),
    );
    return result.future;
  }
}
