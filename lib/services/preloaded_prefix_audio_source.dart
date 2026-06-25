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
    this.headers,
    super.tag,
  });

  final Uri uri;
  final File prefixFile;
  final String contentType;
  final Map<String, String>? headers;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final rangeStart = start ?? 0;
    final prefixLength = await prefixFile.exists()
        ? await prefixFile.length()
        : 0;

    if (prefixLength <= 0 || rangeStart >= prefixLength) {
      return _networkResponse(start, end);
    }

    final prefixEnd = end == null ? prefixLength : min(prefixLength, end);
    final prefixStream = prefixFile.openRead(rangeStart, prefixEnd);

    if (end != null && end <= prefixLength) {
      return StreamAudioResponse(
        rangeRequestsSupported: true,
        sourceLength: null,
        contentLength: end - rangeStart,
        offset: start,
        contentType: contentType,
        stream: prefixStream.asBroadcastStream(),
      );
    }

    final networkResponse = await _networkResponse(prefixEnd, end);
    return StreamAudioResponse(
      rangeRequestsSupported: true,
      sourceLength: networkResponse.sourceLength,
      contentLength: end == null ? null : end - rangeStart,
      offset: start,
      contentType: networkResponse.contentType,
      stream: _concatStreams(
        prefixStream,
        networkResponse.stream,
      ).asBroadcastStream(),
    );
  }

  Future<StreamAudioResponse> _networkResponse(int? start, int? end) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      headers?.forEach((name, value) {
        request.headers.set(name, value);
      });
      if (start != null) {
        request.headers.set(
          HttpHeaders.rangeHeader,
          "bytes=$start-${end == null ? "" : end - 1}",
        );
      }

      final response = await request.close();
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

      final sourceLength = _sourceLengthFromContentRange(
        response.headers.value(HttpHeaders.contentRangeHeader),
      );
      final responseContentType =
          response.headers.contentType?.mimeType ?? contentType;
      final contentLength = response.contentLength == -1
          ? null
          : response.contentLength;

      return StreamAudioResponse(
        rangeRequestsSupported: true,
        sourceLength: isRangeRequest ? sourceLength : null,
        contentLength: contentLength,
        offset: start,
        contentType: responseContentType,
        stream: _closeClientOnDone(client, response).asBroadcastStream(),
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

  Stream<List<int>> _concatStreams(
    Stream<List<int>> first,
    Stream<List<int>> second,
  ) async* {
    yield* first;
    yield* second;
  }

  Stream<List<int>> _closeClientOnDone(
    HttpClient client,
    Stream<List<int>> stream,
  ) async* {
    try {
      await for (final chunk in stream) {
        yield chunk;
      }
    } finally {
      client.close(force: true);
    }
  }
}
