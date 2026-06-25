import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('audio handler source swaps', () {
    late String source;

    setUp(() {
      source = File('lib/services/audio_handler.dart').readAsStringSync();
    });

    test('playByIndex uses classic one-song source flow', () {
      expect(
        _usesClassicOneSongSourceFlow(_caseBlock(source, 'playByIndex')),
        isTrue,
      );
    });

    test('setSourceNPlay uses classic one-song source flow', () {
      expect(
        _usesClassicOneSongSourceFlow(_caseBlock(source, 'setSourceNPlay')),
        isTrue,
      );
    });

    test('repeat mode uses just_audio native loop mode', () {
      final block = _methodBlock(source, 'setRepeatMode');

      expect(block, contains('await _player.setLoopMode('));
      expect(block, contains('LoopMode.one'));
      expect(block, contains('LoopMode.off'));
    });

    test(
      'auto advance listens for completion instead of end-position polling',
      () {
        final block = _methodBlock(source, '_listenToPlaybackForNextSong');

        expect(block, contains('_player.processingStateStream.listen'));
        expect(block, contains('ProcessingState.completed'));
        expect(block, contains('loopModeEnabled'));
        expect(block, contains('_completionInProgress'));
        expect(block, isNot(contains('_player.positionStream.listen')));
        expect(block, isNot(contains('_player.duration')));
      },
    );

    test('repeat completion restarts the current source from the beginning', () {
      final listenerBlock = _methodBlock(source, '_listenToPlaybackForNextSong');
      final repeatBlock = _methodBlock(source, '_repeatCurrentSongFromStart');

      expect(listenerBlock, contains('await _repeatCurrentSongFromStart();'));
      expect(listenerBlock, contains('return;'));
      expect(repeatBlock, contains('await _player.seek(Duration.zero, index: 0);'));
      expect(repeatBlock, contains('unawaited('));
      expect(repeatBlock, contains('_player.play().catchError'));
    });

    test('restores saved repeat mode to the underlying player on init', () {
      final block = _methodBlock(source, '_init');

      expect(block, contains('PrefKeys.isLoopModeEnabled'));
      expect(block, contains('await _player.setLoopMode('));
      expect(block, contains('LoopMode.one'));
      expect(block, contains('LoopMode.off'));
    });

    test('completion guard is declared on the audio handler', () {
      expect(source, contains('bool _completionInProgress = false;'));
    });
  });
}

String _caseBlock(String source, String caseName) {
  final caseStart = source.indexOf("case '$caseName':");
  expect(caseStart, isNot(-1), reason: "Missing $caseName case");

  final nextCase = source.indexOf('\n      case ', caseStart + 1);
  final switchEnd = source.indexOf('\n    }\n', caseStart + 1);
  final caseEnd = nextCase == -1 ? switchEnd : nextCase;
  expect(caseEnd, isNot(-1), reason: "Could not find end of $caseName case");

  return source.substring(caseStart, caseEnd);
}

String _methodBlock(String source, String methodName) {
  var methodStart = source.indexOf('void $methodName(');
  if (methodStart == -1) {
    methodStart = source.indexOf('Future<void> $methodName(');
  }
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

bool _usesClassicOneSongSourceFlow(String block) {
  final stopIndex = block.indexOf('await _player.stop();');
  final clearIndex = block.indexOf('await _playList.clear();');
  if (stopIndex == -1 || clearIndex == -1 || stopIndex > clearIndex)
    return false;

  final addIndex = block.indexOf('await _playList.add', clearIndex);
  if (addIndex == -1) return false;

  final playIndex = block.indexOf('await _player.play();', addIndex);
  final seekIndex = block.indexOf(
    'await _player.seek(Duration.zero, index: 0);',
    addIndex,
  );

  return seekIndex != -1 &&
      playIndex != -1 &&
      addIndex < seekIndex &&
      seekIndex < playIndex;
}
