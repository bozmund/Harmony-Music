import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('downloader metadata writes', () {
    late String source;

    setUp(() {
      source = File('lib/services/downloader.dart').readAsStringSync();
    });

    test('download completion does not mutate the live MediaItem URL', () {
      final block = _methodBlock(source, 'writeFileStream');

      expect(block, isNot(contains("song.extras?['url'] = filePath")));
      expect(block, contains("songJson['url'] = filePath"));
      expect(
        block,
        contains("songJson['date'] ??= DateTime.now().millisecondsSinceEpoch"),
      );
      expect(block, contains("..['url'] = filePath"));
      expect(block, contains("streamInfoJson['url'] = filePath"));
    });

    test('download metadata is validated before saving to the repository', () {
      final block = _methodBlock(source, 'writeFileStream');

      final validationIndex = block.indexOf(
        'final downloadedSong = MediaItemBuilder.fromJson(songJson);',
      );
      final saveIndex = block.indexOf(
        'await _downloadRepository.saveDownloadedSongJson(song.id, songJson);',
      );

      expect(validationIndex, isNonNegative);
      expect(saveIndex, isNonNegative);
      expect(validationIndex, lessThan(saveIndex));
      expect(block, contains('Map<String, dynamic>.from('));
    });
  });
}

String _methodBlock(String source, String methodName) {
  final methodStart = source.indexOf('Future<void> $methodName(');
  expect(methodStart, isNot(-1), reason: 'Missing $methodName');
  final bodyStart = source.indexOf('{', methodStart);
  expect(bodyStart, isNot(-1), reason: 'Missing body for $methodName');

  var depth = 0;
  for (var index = bodyStart; index < source.length; index++) {
    final char = source[index];
    if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
      if (depth == 0) {
        return source.substring(methodStart, index + 1);
      }
    }
  }

  fail('Could not find end of $methodName');
}
