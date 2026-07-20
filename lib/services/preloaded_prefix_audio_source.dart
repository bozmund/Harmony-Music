// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:just_audio/just_audio.dart';

class PreloadedPrefixAudioSource extends StreamAudioSource {
  PreloadedPrefixAudioSource(
    this.uri, {
    required this.prefixFile,
    required this.contentType,
    this.sourceLength,
    this.headers,
    this.stallTimeout = defaultStallTimeout,
    this.onResponseReady,
    this.onFirstEncodedByte,
    super.tag,
  });

  static const defaultStallTimeout = Duration(seconds: 15);

  final Uri uri;
  final File prefixFile;
  final String contentType;
  final int? sourceLength;
  final Map<String, String>? headers;
  final void Function()? onResponseReady;
  final void Function()? onFirstEncodedByte;

  /// Bounds connection setup, response headers, and each gap between body
  /// chunks. Backpressure pauses from the player do not count against it.
  final Duration stallTimeout;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    var firstByteReported = false;
    void reportFirstByte() {
      if (firstByteReported) return;
      firstByteReported = true;
      onFirstEncodedByte?.call();
    }

    final rangeStart = start ?? 0;
    final prefixLength = await prefixFile.exists()
        ? await prefixFile.length()
        : 0;

    if (prefixLength <= 0 || rangeStart >= prefixLength) {
      final response = await _openNetworkResponse(
        start,
        end,
        onFirstByte: reportFirstByte,
      );
      onResponseReady?.call();
      return response.audioResponse;
    }

    final prefixEnd = end == null ? prefixLength : min(prefixLength, end);
    final prefixStream = prefixFile.openRead(rangeStart, prefixEnd);

    if (end != null && end <= prefixLength) {
      onResponseReady?.call();
      return StreamAudioResponse(
        rangeRequestsSupported: true,
        sourceLength: sourceLength,
        contentLength: end - rangeStart,
        offset: rangeStart,
        contentType: contentType,
        stream: _markFirstByte(prefixStream, reportFirstByte),
      );
    }

    // Start connecting to the tail now, but deliberately do not await its
    // headers. The player can consume the local prefix while that work runs.
    // Convert failures into values immediately so a delayed stream listener
    // cannot produce an unhandled asynchronous error.
    final networkTail =
        _openNetworkResponse(
          prefixEnd,
          end,
          onFirstByte: reportFirstByte,
        ).then<_NetworkOutcome>(
          _NetworkOutcome.success,
          onError: (Object error, StackTrace stackTrace) =>
              _NetworkOutcome.failure(error, stackTrace),
        );
    onResponseReady?.call();
    return StreamAudioResponse(
      rangeRequestsSupported: true,
      sourceLength: sourceLength,
      contentLength: end != null
          ? end - rangeStart
          : sourceLength == null
          ? null
          : sourceLength! - rangeStart,
      offset: rangeStart,
      contentType: contentType,
      stream: _prefixThenNetwork(prefixStream, networkTail, reportFirstByte),
    );
  }

  Future<_OwnedNetworkResponse> _openNetworkResponse(
    int? start,
    int? end, {
    required void Function() onFirstByte,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = stallTimeout;
    try {
      final request = await client.getUrl(uri).timeout(stallTimeout);
      headers?.forEach((name, value) {
        request.headers.set(name, value);
      });
      if (start != null) {
        request.headers.set(
          HttpHeaders.rangeHeader,
          "bytes=$start-${end == null ? "" : end - 1}",
        );
      }

      final response = await request.close().timeout(stallTimeout);
      final isRangeRequest = start != null;
      final isValidStatus = isRangeRequest
          ? response.statusCode == HttpStatus.partialContent
          : response.statusCode == HttpStatus.ok ||
                response.statusCode == HttpStatus.partialContent;
      if (!isValidStatus) {
        client.close(force: true);
        throw HttpException(
          "Unexpected preload source status ${response.statusCode}",
          uri: uri,
        );
      }

      final sourceLength =
          _sourceLengthFromContentRange(
            response.headers.value(HttpHeaders.contentRangeHeader),
          ) ??
          this.sourceLength;
      final responseContentType =
          response.headers.contentType?.mimeType ?? contentType;
      final contentLength = response.contentLength == -1
          ? null
          : response.contentLength;

      return _OwnedNetworkResponse(
        client: client,
        audioResponse: StreamAudioResponse(
          rangeRequestsSupported: true,
          sourceLength: isRangeRequest ? sourceLength : null,
          contentLength: contentLength,
          offset: start,
          contentType: responseContentType,
          stream: _closeClientOnDone(client, response, onFirstByte),
        ),
      );
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }

  int? _sourceLengthFromContentRange(String? contentRange) {
    if (contentRange == null) return null;
    final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  Stream<List<int>> _prefixThenNetwork(
    Stream<List<int>> prefix,
    Future<_NetworkOutcome> networkTail,
    void Function() onFirstByte,
  ) async* {
    var tailAttached = false;
    try {
      yield* _markFirstByte(prefix, onFirstByte);
      final outcome = await networkTail;
      if (outcome.error != null) {
        Error.throwWithStackTrace(outcome.error!, outcome.stackTrace!);
      }
      tailAttached = true;
      yield* outcome.response!.audioResponse.stream;
    } finally {
      if (!tailAttached) {
        unawaited(_discardNetworkTail(networkTail));
      }
    }
  }

  Future<void> _discardNetworkTail(Future<_NetworkOutcome> networkTail) async {
    final outcome = await networkTail;
    outcome.response?.discard();
  }

  Stream<List<int>> _markFirstByte(
    Stream<List<int>> stream,
    void Function() onFirstByte,
  ) async* {
    var marked = false;
    await for (final chunk in stream) {
      if (!marked && chunk.isNotEmpty) {
        marked = true;
        onFirstByte();
      }
      yield chunk;
    }
  }

  Stream<List<int>> _closeClientOnDone(
    HttpClient client,
    Stream<List<int>> stream,
    void Function() onFirstByte,
  ) async* {
    var marked = false;
    try {
      // Stream.timeout suspends its timer while the subscription is paused,
      // so only a genuinely stalled connection trips it — not the player
      // pausing reads because its buffers are full.
      await for (final chunk in stream.timeout(
        stallTimeout,
        onTimeout: (sink) {
          sink.addError(TimeoutException('Audio stream stalled', stallTimeout));
          sink.close();
        },
      )) {
        if (!marked && chunk.isNotEmpty) {
          marked = true;
          onFirstByte();
        }
        yield chunk;
      }
    } finally {
      client.close(force: true);
    }
  }
}

class _OwnedNetworkResponse {
  const _OwnedNetworkResponse({
    required this.client,
    required this.audioResponse,
  });

  final HttpClient client;
  final StreamAudioResponse audioResponse;

  void discard() => client.close(force: true);
}

class _NetworkOutcome {
  const _NetworkOutcome.success(this.response)
    : error = null,
      stackTrace = null;

  const _NetworkOutcome.failure(this.error, this.stackTrace) : response = null;

  final _OwnedNetworkResponse? response;
  final Object? error;
  final StackTrace? stackTrace;
}
