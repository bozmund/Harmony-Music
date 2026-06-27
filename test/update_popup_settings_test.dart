import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('settings update popup behavior', () {
    late String homeController;
    late String settingsController;
    late String updateDialog;
    late String bottomNav;
    late String sideNav;
    late String badgeIcon;

    setUp(() {
      homeController = File(
        'lib/ui/screens/Home/home_screen_controller.dart',
      ).readAsStringSync();
      settingsController = File(
        'lib/ui/screens/Settings/settings_screen_controller.dart',
      ).readAsStringSync();
      updateDialog = File(
        'lib/ui/widgets/new_version_dialog.dart',
      ).readAsStringSync();
      bottomNav = File('lib/ui/widgets/bottom_nav_bar.dart').readAsStringSync();
      sideNav = File('lib/ui/widgets/side_nav_bar.dart').readAsStringSync();
      badgeIcon = File(
        'lib/ui/widgets/update_badged_settings_icon.dart',
      ).readAsStringSync();
    });

    test('startup update logic still honors visibility preference', () {
      final checkBlock = _methodBlock(homeController, '_checkNewVersion');

      expect(checkBlock, contains('isStartupUpdatePopupEnabled()'));
      expect(checkBlock, contains('if (showVersionDialog.isTrue)'));
      expect(checkBlock, contains('settingsController.checkNewVersion()'));
    });

    test('visibility helper writes the existing startup popup preference', () {
      final helperBlock = _methodBlock(
        homeController,
        'setStartupUpdatePopupEnabled',
      );
      final checkboxBlock = _methodBlock(
        homeController,
        'onChangeVersionVisibility',
      );

      expect(helperBlock, contains('PrefKeys.newVersionVisibility'));
      expect(helperBlock, contains('showVersionDialog.value = enabled'));
      expect(checkboxBlock, contains('setStartupUpdatePopupEnabled(!val)'));
    });

    test(
      'settings manual update dialog disables future startup popups on tap',
      () {
        final checkUpdateBlock = _methodBlock(
          settingsController,
          'checkUpdate',
        );

        expect(checkUpdateBlock, contains('checkNewVersion()'));
        expect(checkUpdateBlock, isNot(contains('showVersionDialog')));
        expect(
          checkUpdateBlock,
          contains('disableStartupPopupOnUpdateTap: true'),
        );
        expect(
          updateDialog,
          contains('disableStartupPopupOnUpdateTap = false'),
        );
        expect(updateDialog, contains('disableStartupUpdatePopup()'));
      },
    );

    test(
      'settings navigation icons are badged when an update is available',
      () {
        expect(bottomNav, contains('UpdateBadgedSettingsIcon'));
        expect(sideNav, contains('UpdateBadgedSettingsIcon'));
        expect(badgeIcon, contains('updateCheckFlag'));
        expect(badgeIcon, contains('isNewVersionAvailable.value'));
        expect(badgeIcon, contains('Colors.orange'));
      },
    );
  });
}

String _methodBlock(String source, String methodName) {
  var methodStart = source.indexOf('Future<void> $methodName(');
  if (methodStart == -1) {
    methodStart = source.indexOf('void $methodName(');
  }
  if (methodStart == -1) {
    methodStart = source.indexOf('bool $methodName(');
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
