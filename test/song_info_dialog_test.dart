import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'SongInfoDialog reads cached stream info through repository decoding',
    () {
      final source = File(
        'lib/ui/widgets/song_info_dialog.dart',
      ).readAsStringSync();
      final block = _methodBlock(source, '_getStreamInfo');

      expect(block, contains('songCacheRepository.getStreamInfo('));
      expect(
        block,
        contains('audio == null ? _nullStreamInfo : audio.toJson()'),
      );
      expect(block, isNot(contains('runtimeType.toString()')));
      expect(block, isNot(contains('getStreamCacheEntry')));
    },
  );
}

String _methodBlock(String source, String methodName) {
  final methodStart = source.indexOf(
    'Future<Map<dynamic, dynamic>> $methodName(',
  );
  expect(methodStart, isNot(-1), reason: 'Missing $methodName');
  final bodyStart = _methodBodyStart(source, methodStart);
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

int _methodBodyStart(String source, int methodStart) {
  var parenDepth = 0;
  for (
    var index = source.indexOf('(', methodStart);
    index < source.length;
    index++
  ) {
    final char = source[index];
    if (char == '(') {
      parenDepth++;
    } else if (char == ')') {
      parenDepth--;
      if (parenDepth == 0) {
        return source.indexOf('{', index);
      }
    }
  }

  return -1;
}
