import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/preloaded_prefix_audio_source.dart';

void main() {
  group('PreloadedPrefixAudioSource', () {
    late Directory tempDir;
    late HttpServer server;
    late Uri uri;
    late List<int> audioBytes;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'harmony_prefix_source_test_',
      );
      audioBytes = List<int>.generate(64, (index) => index);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      uri = Uri.parse('http://${server.address.host}:${server.port}/song.opus');
      _serveBytes(server, audioBytes);
    });

    tearDown(() async {
      await server.close(force: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('full request emits prefix plus network tail', () async {
      final source = await _source(
        uri: uri,
        tempDir: tempDir,
        audioBytes: audioBytes,
        prefixLength: 12,
      );

      final response = await source.request();
      final bytes = await _readAll(response.stream);

      expect(bytes, audioBytes);
      expect(response.offset, 0);
      expect(response.sourceLength, audioBytes.length);
      expect(response.contentLength, audioBytes.length);
    });

    test('range inside prefix returns prefix bytes with offset', () async {
      final source = await _source(
        uri: uri,
        tempDir: tempDir,
        audioBytes: audioBytes,
        prefixLength: 12,
      );

      final response = await source.request(3, 9);
      final bytes = await _readAll(response.stream);

      expect(bytes, audioBytes.sublist(3, 9));
      expect(response.offset, 3);
      expect(response.sourceLength, audioBytes.length);
      expect(response.contentLength, 6);
    });

    test(
      'range crossing prefix boundary returns prefix and network tail',
      () async {
        final source = await _source(
          uri: uri,
          tempDir: tempDir,
          audioBytes: audioBytes,
          prefixLength: 12,
        );

        final response = await source.request(8, 20);
        final bytes = await _readAll(response.stream);

        expect(bytes, audioBytes.sublist(8, 20));
        expect(response.offset, 8);
        expect(response.sourceLength, audioBytes.length);
        expect(response.contentLength, 12);
      },
    );
  });
}

Future<PreloadedPrefixAudioSource> _source({
  required Uri uri,
  required Directory tempDir,
  required List<int> audioBytes,
  required int prefixLength,
}) async {
  final prefixFile = File('${tempDir.path}/song.prefix');
  await prefixFile.writeAsBytes(audioBytes.take(prefixLength).toList());
  return PreloadedPrefixAudioSource(
    uri,
    prefixFile: prefixFile,
    contentType: 'audio/opus',
    sourceLength: audioBytes.length,
  );
}

void _serveBytes(HttpServer server, List<int> audioBytes) {
  server.listen((request) async {
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    final range = _parseRange(rangeHeader, audioBytes.length);
    final start = range.$1;
    final endInclusive = range.$2;
    final responseBytes = audioBytes.sublist(start, endInclusive + 1);

    request.response.headers.contentType = ContentType('audio', 'opus');
    request.response.contentLength = responseBytes.length;
    if (rangeHeader != null) {
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$endInclusive/${audioBytes.length}',
      );
    } else {
      request.response.statusCode = HttpStatus.ok;
    }
    request.response.add(responseBytes);
    await request.response.close();
  });
}

(int, int) _parseRange(String? rangeHeader, int sourceLength) {
  if (rangeHeader == null) return (0, sourceLength - 1);
  final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(rangeHeader);
  if (match == null) return (0, sourceLength - 1);
  final start = int.parse(match.group(1)!);
  final end = match.group(2)!.isEmpty
      ? sourceLength - 1
      : int.parse(match.group(2)!);
  return (start, end.clamp(start, sourceLength - 1).toInt());
}

Future<List<int>> _readAll(Stream<List<int>> stream) async {
  final bytes = <int>[];
  await for (final chunk in stream) {
    bytes.addAll(chunk);
  }
  return bytes;
}
