import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('audio handler source swaps', () {
    late String source;

    setUp(() {
      source = File('lib/services/audio_handler.dart').readAsStringSync();
    });

    test('playByIndex resets a stopped source swap before playing', () {
      expect(_sourceSwapIsSafe(_caseBlock(source, 'playByIndex')), isTrue);
    });

    test('setSourceNPlay resets a stopped source swap before playing', () {
      expect(_sourceSwapIsSafe(_caseBlock(source, 'setSourceNPlay')), isTrue);
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

bool _sourceSwapIsSafe(String block) {
  final stopIndex = block.indexOf('await _player.stop();');
  final clearIndex = block.indexOf('await _playList.clear();');
  if (stopIndex == -1 || clearIndex == -1 || stopIndex > clearIndex) {
    return true;
  }

  final addIndex = block.indexOf('await _playList.add', clearIndex);
  final seekZeroIndex = block.indexOf(
    'await _player.seek(Duration.zero, index: 0);',
    addIndex,
  );
  final playIndex = block.indexOf('await _player.play();', addIndex);

  return addIndex != -1 &&
      seekZeroIndex != -1 &&
      playIndex != -1 &&
      addIndex < seekZeroIndex &&
      seekZeroIndex < playIndex;
}
