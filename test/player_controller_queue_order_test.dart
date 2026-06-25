import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('player controller queue ordering', () {
    late String source;

    setUp(() {
      source = File('lib/ui/player/player_controller.dart').readAsStringSync();
    });

    test(
      'normal song taps start playback before background queue update completes',
      () {
        final block = _methodBlock(source, 'pushSongToQueue');

        final queueUpdateIndex = block.indexOf(
          'final queueUpdate = Future.delayed',
        );
        final backgroundUpdateIndex = block.indexOf('queueUpdate.then');
        final panelCheckIndex = block.indexOf(
          'unawaited(_playerPanelCheck());',
        );
        final setSourceIndex = block.indexOf('"setSourceNPlay"');

        expect(queueUpdateIndex, isNot(-1));
        expect(backgroundUpdateIndex, isNot(-1));
        expect(panelCheckIndex, isNot(-1));
        expect(setSourceIndex, isNot(-1));
        expect(queueUpdateIndex, lessThan(backgroundUpdateIndex));
        expect(backgroundUpdateIndex, lessThan(setSourceIndex));
        expect(panelCheckIndex, lessThan(setSourceIndex));
      },
    );

    test('playlist-id playback waits for queue update before playByIndex', () {
      final block = _methodBlock(source, 'pushSongToQueue');
      final playlistBranchIndex = block.indexOf('if (playlistId != null)');
      final awaitQueueUpdateIndex = block.indexOf(
        'await queueUpdate;',
        playlistBranchIndex,
      );
      final playByIndexIndex = block.indexOf(
        '"playByIndex"',
        awaitQueueUpdateIndex,
      );

      expect(playlistBranchIndex, isNot(-1));
      expect(awaitQueueUpdateIndex, isNot(-1));
      expect(playByIndexIndex, isNot(-1));
      expect(awaitQueueUpdateIndex, lessThan(playByIndexIndex));
    });

    test('playlist playback updates queue before playByIndex', () {
      final block = _methodBlock(source, 'playPlayListSong');
      final panelIndex = block.indexOf('await _playerPanelCheck();');
      final updateQueueIndex = block.indexOf('await _audioHandler.updateQueue');
      final shuffleIndex = block.indexOf('"shuffleCmd"');
      final playByIndexIndex = block.indexOf('"playByIndex"');

      expect(panelIndex, isNot(-1));
      expect(updateQueueIndex, isNot(-1));
      expect(shuffleIndex, isNot(-1));
      expect(playByIndexIndex, isNot(-1));
      expect(panelIndex, lessThan(updateQueueIndex));
      expect(updateQueueIndex, lessThan(playByIndexIndex));
      expect(shuffleIndex, lessThan(playByIndexIndex));
    });

    test('enqueue into an empty queue starts playback', () {
      final block = _methodBlock(source, 'enqueueSong');

      expect(block, contains('if (currentQueue.isEmpty)'));
      expect(block, contains('await playPlayListSong([mediaItem], 0);'));
    });

    test('transport request methods are fire-and-forget wrappers', () {
      expect(
        _methodBlock(source, 'requestPlay'),
        contains('_runPlaybackCommand'),
      );
      expect(
        _methodBlock(source, 'requestPause'),
        contains('_runPlaybackCommand'),
      );
      expect(
        _methodBlock(source, 'requestPlayPause'),
        contains('_runPlaybackCommand'),
      );
      expect(
        _methodBlock(source, 'requestPrev'),
        contains('_runPlaybackCommand'),
      );
      expect(
        _methodBlock(source, 'requestNext'),
        contains('_runPlaybackCommand'),
      );
      expect(
        _methodBlock(source, 'requestSeek'),
        contains('_runPlaybackCommand'),
      );
    });

    test('playback command runner intentionally discards command futures', () {
      final block = _methodBlock(source, '_runPlaybackCommand');

      expect(block, contains('unawaited('));
      expect(block, contains('_playbackCommand'));
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
  var started = false;
  for (var index = bodyStart; index < source.length; index++) {
    final char = source[index];
    if (char == '{') {
      depth++;
      started = true;
    } else if (char == '}') {
      depth--;
      if (started && depth == 0) {
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
