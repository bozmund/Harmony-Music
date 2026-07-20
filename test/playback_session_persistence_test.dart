import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('playback session persistence', () {
    late String source;

    setUp(() {
      source = File('lib/services/audio_handler.dart').readAsStringSync();
    });

    test('handler wires the session persistence listeners on init', () {
      expect(
        _methodBlock(source, '_init'),
        contains('_listenForSessionPersistence();'),
      );
    });

    test('saves trigger on track change, pause, and queue changes', () {
      final listener = _methodBlock(source, '_listenForSessionPersistence');
      expect(listener, contains('mediaItem'));
      expect(listener, contains('.distinct('));
      expect(listener, contains('playingStream'));
      expect(listener, contains('queue.listen('));
      // A new song starts at zero; the live position is unreliable mid switch.
      expect(listener, contains('positionOverride: Duration.zero'));
      // A source-switch stop must not save the previous song's position.
      expect(listener, contains('_sourceSwitchInProgress'));
      expect(listener, contains('isSongLoading'));
    });

    test('scheduled saves never fabricate index 0', () {
      final schedule = _methodBlock(source, '_scheduleSessionSave');
      expect(schedule, contains('currentIndex is! int'));
      expect(schedule, contains('_suppressSessionSave'));
      expect(schedule, contains('Duration(milliseconds: 800)'));
      expect(schedule, contains('saveSessionData(positionOverride:'));
    });

    test('periodic saver persists position only, gated by the setting', () {
      final periodic = _methodBlock(source, '_syncPeriodicPositionSaves');
      expect(periodic, contains('Duration(seconds: 30)'));
      expect(periodic, contains('savePosition('));
      expect(periodic, contains('getRestorePlaybackSession()'));
      expect(periodic, contains('_periodicPositionSaveTimer?.cancel();'));
    });

    test('session restore suppresses automatic saves until it finishes', () {
      final playByIndex = _caseBlock(source, 'playByIndex');
      expect(
        playByIndex,
        contains('if (restoreSession) _suppressSessionSave = true;'),
      );
      expect(playByIndex, contains('} finally {'));
      expect(
        playByIndex,
        contains('if (restoreSession) _suppressSessionSave = false;'),
      );
    });

    test('dispose cancels the session persistence timers', () {
      final dispose = _caseBlock(source, 'dispose');
      expect(dispose, contains('_sessionSaveDebounce?.cancel();'));
      expect(dispose, contains('_periodicPositionSaveTimer?.cancel();'));
    });

    test('audio service stays foreground while paused', () {
      // Both flags must flip together: the AudioServiceConfig assert forbids
      // androidNotificationOngoing: true with androidStopForegroundOnPause:
      // false, and stop-foreground-on-pause is what made the service an
      // OOM-kill target during phone calls (no auto-resume, stale
      // notification).
      expect(source, contains('androidNotificationOngoing: false'));
      expect(source, contains('androidStopForegroundOnPause: false'));
      expect(source, isNot(contains('androidNotificationOngoing: true')));
      expect(source, isNot(contains('androidStopForegroundOnPause: true')));
    });

    test('paused foreground service releases the CPU wakelock', () {
      final javaSource = File(
        'third_party/audio_service/android/src/main/java/com/ryanheise/audioservice/AudioService.java',
      ).readAsStringSync();
      final start = javaSource.indexOf('private void exitPlayingState()');
      expect(start, isNot(-1), reason: 'Missing exitPlayingState');
      final end = javaSource.indexOf('private void', start + 1);
      final exitPlayingState = javaSource.substring(start, end);
      expect(exitPlayingState, contains('releaseWakeLock();'));
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
