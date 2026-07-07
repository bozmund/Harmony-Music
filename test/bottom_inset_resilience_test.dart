import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against the Samsung One UI / Android 15 edge-to-edge inset bug where
/// [MediaQuery.of] reports a stale, wrong, or transiently-0 bottom inset (the
/// app then "thinks" gesture nav is active, collapsing the library offset and
/// mini-player height). The whole inset reads must go through the root-view
/// helper with a non-zero floor, and must not mix in [padding.bottom] (which
/// can collapse to 0 under a SafeArea ancestor).
void main() {
  group('bottom nav inset resilience', () {
    late final String scrollToHideSource;
    late final String insetsSource;

    setUpAll(() {
      scrollToHideSource = File(
        'lib/ui/widgets/scroll_to_hide.dart',
      ).readAsStringSync();
      insetsSource = File('lib/utils/insets.dart').readAsStringSync();
    });

    test('single source of truth helper exists with a non-zero floor', () {
      // Root-view read so an ancestor MediaQuery can't shrink the inset.
      expect(
        insetsSource,
        contains('MediaQueryData.fromView(View.of(context)).viewPadding.bottom'),
      );
      // Floor against transient 0 reports during immersive/resume transitions.
      expect(insetsSource, contains('_maxSeenBottomInset'));
      expect(insetsSource, contains('raw > _maxSeenBottomInset'));
      expect(insetsSource, isNot(contains('MediaQuery.of(context).viewPadding')));
    });

    test('ScrollToHideWidget.visibleHeight uses the floor helper', () {
      expect(
        scrollToHideSource,
        contains('80.0 + bottomNavInset(context)'),
      );
      // No longer reads the ancestor-narrowable MediaQuery directly.
      expect(
        scrollToHideSource.contains('MediaQuery.of(context).viewPadding.bottom'),
        isFalse,
      );
    });

    test('no bottom-nav spacing still uses MediaQuery.of(...).padding.bottom',
        () {
      // The nav-bar footprint must not come from `padding` (collapses under
      // SafeArea) in the files that reserve nav-bar / mini-player space.
      final offenders = <String, String>{
        'home.dart': File('lib/ui/home.dart').readAsStringSync(),
        'standard_player.dart':
            File('lib/ui/player/components/standard_player.dart')
                .readAsStringSync(),
        'gesture_player.dart':
            File('lib/ui/player/components/gesture_player.dart')
                .readAsStringSync(),
        'up_next_queue.dart':
            File('lib/ui/widgets/up_next_queue.dart').readAsStringSync(),
        'main.dart': File('lib/main.dart').readAsStringSync(),
        'player_controller.dart':
            File('lib/ui/player/player_controller.dart').readAsStringSync(),
      };
      for (final entry in offenders.entries) {
        expect(
          entry.value.contains('MediaQuery.of(context).padding.bottom') ||
              entry.value.contains('mQuery.padding.bottom'),
          isFalse,
          reason: '${entry.key} should reserve nav space via bottomNavInset',
        );
      }
      // And they must now reference the helper instead.
      for (final entry in offenders.entries) {
        expect(
          entry.value,
          contains('bottomNavInset('),
          reason: '${entry.key} should call bottomNavInset for nav spacing',
        );
      }
    });
  });
}
