import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('settings playback mode', () {
    late String source;

    setUp(() {
      source = File(
        'lib/ui/screens/Settings/settings_screen_controller.dart',
      ).readAsStringSync();
    });

    test('classic mode persists mode and disables preloading', () {
      final block = _methodBlock(source, 'setPlaybackMode');
      final classicBranchIndex = block.indexOf(
        'if (selectedMode == PlaybackMode.classic)',
      );
      final rangeZeroIndex = block.indexOf(
        'playbackPreloadRange.value = 0;',
        classicBranchIndex,
      );
      final persistedRangeZeroIndex = block.indexOf(
        'setBox.put(PrefKeys.playbackPreloadRange, 0)',
        classicBranchIndex,
      );

      expect(block, contains('setBox.put(PrefKeys.playbackMode'));
      expect(classicBranchIndex, isNot(-1));
      expect(rangeZeroIndex, isNot(-1));
      expect(persistedRangeZeroIndex, isNot(-1));
      expect(classicBranchIndex, lessThan(rangeZeroIndex));
    });

    test('preloaded mode normalizes zero range to one', () {
      final block = _methodBlock(source, 'setPlaybackMode');
      final preloadedBranchIndex = block.indexOf(
        'playbackPreloadRange.value == 0',
      );
      final rangeOneIndex = block.indexOf(
        'playbackPreloadRange.value = 1;',
        preloadedBranchIndex,
      );
      final persistedRangeOneIndex = block.indexOf(
        'setBox.put(PrefKeys.playbackPreloadRange, 1)',
        preloadedBranchIndex,
      );

      expect(preloadedBranchIndex, isNot(-1));
      expect(rangeOneIndex, isNot(-1));
      expect(persistedRangeOneIndex, isNot(-1));
    });

    test('mode and range changes notify the audio handler', () {
      final setModeBlock = _methodBlock(source, 'setPlaybackMode');
      final setRangeBlock = _methodBlock(source, 'setPlaybackPreloadRange');

      expect(setModeBlock, contains('"updatePlaybackMode"'));
      expect(setModeBlock, contains('"updatePlaybackPreloadRange"'));
      expect(setRangeBlock, contains('"updatePlaybackPreloadRange"'));
    });

    test('initialization repairs persisted preloaded mode with zero range', () {
      final initBlock = _methodBlock(source, '_setInitValue');

      expect(
        initBlock,
        contains('playbackMode.value == PlaybackMode.preloaded'),
      );
      expect(initBlock, contains('playbackPreloadRange.value == 0'));
      expect(initBlock, contains('playbackPreloadRange.value = 1;'));
      expect(
        initBlock,
        contains('setBox.put(PrefKeys.playbackPreloadRange, 1)'),
      );
    });
  });
}

String _methodBlock(String source, String methodName) {
  var methodStart = source.indexOf('Future<void> $methodName(');
  if (methodStart == -1) {
    methodStart = source.indexOf('void $methodName(');
  }
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
