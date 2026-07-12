// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

class ResolverAudioSource extends StreamAudioSource {
  ResolverAudioSource({
    required this.uri,
    required this.headers,
    required HttpClient initialClient,
    required HttpClientResponse initialResponse,
    required StreamIterator<List<int>> initialIterator,
    required Uint8List initialPrefix,
    super.tag,
  }) : _initialClient = initialClient,
       _initialResponse = initialResponse,
       _initialIterator = initialIterator,
       _initialPrefix = initialPrefix,
       _etag = initialResponse.headers.value(HttpHeaders.etagHeader);

  final Uri uri;
  final Map<String, String> headers;
  HttpClient? _initialClient;
  HttpClientResponse? _initialResponse;
  StreamIterator<List<int>>? _initialIterator;
  Uint8List? _initialPrefix;
  final String? _etag;

  ResolverAudioSource withTag(Object tag) {
    final tagged = ResolverAudioSource(
      uri: uri,
      headers: headers,
      initialClient: _initialClient!,
      initialResponse: _initialResponse!,
      initialIterator: _initialIterator!,
      initialPrefix: _initialPrefix!,
      tag: tag,
    );
    _initialClient = null;
    _initialResponse = null;
    _initialIterator = null;
    _initialPrefix = null;
    return tagged;
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    if (start == null && _initialResponse != null) {
      final response = _initialResponse!;
      final iterator = _initialIterator!;
      final prefix = _initialPrefix!;
      final client = _initialClient!;
      _initialResponse = null;
      _initialIterator = null;
      _initialPrefix = null;
      _initialClient = null;
      return _toAudioResponse(
        response,
        offset: 0,
        stream: _initialStream(prefix, iterator, client),
      );
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      headers.forEach(request.headers.set);
      if (start != null) {
        request.headers.set(
          HttpHeaders.rangeHeader,
          'bytes=$start-${end == null ? '' : end - 1}',
        );
        if (_etag != null) {
          request.headers.set(HttpHeaders.ifRangeHeader, _etag);
        }
      }
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw HttpException(
          'Resolver audio returned ${response.statusCode}',
          uri: uri,
        );
      }
      return _toAudioResponse(
        response,
        offset: start ?? 0,
        stream: _closeClientOnDone(client, response),
      );
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }

  StreamAudioResponse _toAudioResponse(
    HttpClientResponse response, {
    required int offset,
    required Stream<List<int>> stream,
  }) {
    final contentLength = response.contentLength < 0
        ? null
        : response.contentLength;
    return StreamAudioResponse(
      rangeRequestsSupported:
          response.statusCode == HttpStatus.partialContent || offset == 0,
      sourceLength: _sourceLength(response) ?? contentLength,
      contentLength: contentLength,
      offset: offset,
      contentType: response.headers.contentType?.mimeType ?? 'audio/ogg',
      stream: stream,
    );
  }

  int? _sourceLength(HttpClientResponse response) {
    final value = response.headers.value(HttpHeaders.contentRangeHeader);
    final match = value == null ? null : RegExp(r'/(\d+)$').firstMatch(value);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  Stream<List<int>> _initialStream(
    Uint8List prefix,
    StreamIterator<List<int>> iterator,
    HttpClient client,
  ) async* {
    try {
      yield prefix;
      while (await iterator.moveNext()) {
        yield iterator.current;
      }
    } finally {
      await iterator.cancel();
      client.close();
    }
  }

  Stream<List<int>> _closeClientOnDone(
    HttpClient client,
    Stream<List<int>> response,
  ) async* {
    try {
      yield* response;
    } finally {
      client.close();
    }
  }

  Future<void> disposeInitial() async {
    await _initialIterator?.cancel();
    _initialClient?.close(force: true);
    _initialIterator = null;
    _initialClient = null;
    _initialResponse = null;
    _initialPrefix = null;
  }
}
