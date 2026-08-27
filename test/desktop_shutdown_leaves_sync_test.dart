import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('desktop shutdown ends a cloud session', () {
    late String tray;

    setUp(() {
      tray = File('lib/utils/system_tray.dart').readAsStringSync();
    });

    test('both exit paths leave sync before exit(0)', () {
      // Closing the app is the same intent as tapping "Leave sync": the other
      // device must not be left playing, and the server's target marker must
      // not outlive the app that claimed it. Quitting from the tray and
      // closing the window are separate paths and both call exit(0), so
      // covering only one leaves the other silently broken.
      final exits = 'exit(0);'.allMatches(tray).length;
      final cleanups = '_endCloudSessionBeforeExit('.allMatches(tray).length;
      expect(exits, 2, reason: 'tray Quit and window close');
      expect(
        cleanups,
        exits + 1,
        reason: 'every exit path, plus the declaration itself',
      );

      for (final path in tray.split('exit(0);')) {
        if (!path.contains('customAction("saveSession")')) continue;
        expect(
          path,
          contains('_endCloudSessionBeforeExit('),
          reason: 'cleanup must run before this exit, not after',
        );
      }
    });

    test('cleanup is bounded and cannot block quitting', () {
      // exit(0) skips the detached lifecycle callback, so this is the only
      // chance to run - but an unreachable server must not hold the window
      // open. Losing the cleanup beats refusing to quit.
      expect(tray, contains('receiver.leaveSync().timeout('));
      expect(tray, contains('if (!receiver.isEngaged) return;'));
      expect(tray, contains('catch (error, stackTrace)'));
    });

    test('hiding to the tray keeps the session alive', () {
      // Background play hides the window instead of exiting; the app is still
      // running and still the audio target, so it must not disconnect.
      final branchStart = tray.indexOf('backgroundPlayEnabled');
      final hideBranch = tray.substring(
        branchStart,
        // Anchored: the Show/Hide menu item calls hide() earlier in the file.
        tray.indexOf('windowManager.hide()', branchStart),
      );
      expect(hideBranch, isNot(contains('_endCloudSessionBeforeExit(')));
    });
  });
}
