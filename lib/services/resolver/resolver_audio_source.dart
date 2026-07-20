// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

class ResolverAudioSource extends StreamAudioSource {
  ResolverAudioSource({
    required this.uri,
    required this.headers,
    required HttpClient httpClient,
    required HttpClientResponse initialResponse,
    required StreamIterator<List<int>> initialIterator,
    required Uint8List initialPrefix,
    void Function()? onResponseHeaders,
    void Function()? onFirstEncodedByte,
    super.tag,
  }) : _httpClient = httpClient,
       _initialResponse = initialResponse,
       _initialIterator = initialIterator,
       _initialPrefix = initialPrefix,
       _etag = initialResponse.headers.value(HttpHeaders.etagHeader),
       _onResponseHeaders = onResponseHeaders,
       _onFirstEncodedByte = onFirstEncodedByte;

  final Uri uri;
  final Map<String, String> headers;
  final HttpClient _httpClient;
  HttpClientResponse? _initialResponse;
  StreamIterator<List<int>>? _initialIterator;
  Uint8List? _initialPrefix;
  final String? _etag;
  final void Function()? _onResponseHeaders;
  final void Function()? _onFirstEncodedByte;

  ResolverAudioSource withTag(Object tag) {
    final tagged = ResolverAudioSource(
      uri: uri,
      headers: headers,
      httpClient: _httpClient,
      initialResponse: _initialResponse!,
      initialIterator: _initialIterator!,
      initialPrefix: _initialPrefix!,
      onResponseHeaders: _onResponseHeaders,
      onFirstEncodedByte: _onFirstEncodedByte,
      tag: tag,
    );
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
      _initialResponse = null;
      _initialIterator = null;
      _initialPrefix = null;
      return _toAudioResponse(
        response,
        offset: 0,
        stream: _initialStream(prefix, iterator),
      );
    }

    final request = await _httpClient.getUrl(uri);
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
    _onResponseHeaders?.call();
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      await response.drain<void>();
      throw HttpException(
        'Resolver audio returned ${response.statusCode}',
        uri: uri,
      );
    }
    return _toAudioResponse(
      response,
      offset: start ?? 0,
      stream: _markFirstByte(response),
    );
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
  ) async* {
    try {
      yield prefix;
      while (await iterator.moveNext()) {
        yield iterator.current;
      }
    } finally {
      await iterator.cancel();
    }
  }

  Stream<List<int>> _markFirstByte(Stream<List<int>> response) async* {
    var marked = false;
    await for (final chunk in response) {
      if (!marked && chunk.isNotEmpty) {
        marked = true;
        _onFirstEncodedByte?.call();
      }
      yield chunk;
    }
  }

  Future<void> disposeInitial() async {
    await _initialIterator?.cancel();
    _initialIterator = null;
    _initialResponse = null;
    _initialPrefix = null;
  }
}
