import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/release_prompt.dart';

void main() {
  group('stable is the default update channel', () {
    test('persisted setting falls back to stable', () {
      final source = File(
        'lib/data/repositories/hive_settings_repository.dart',
      ).readAsStringSync();
      expect(source, contains("?? 'stable'"));
      expect(source, isNot(contains("?? 'rolling'")));
    });

    test('settings controller starts on stable before loading the setting',
        () {
      final source = File(
        'lib/ui/screens/Settings/settings_screen_controller.dart',
      ).readAsStringSync();
      expect(
        source,
        contains('ObservableValue(UpdateChannel.stable)'),
      );
    });
  });

  group('one-time release prompt', () {
    test('6.0.0 ships the channel-choice prompt', () {
      expect(currentReleasePrompt, isNotNull);
      expect(currentReleasePrompt!.id, 'channel-choice-6.0.0');
    });

    test('home shows the prompt before the update check runs', () {
      final source = File(
        'lib/ui/screens/Home/home_screen_controller.dart',
      ).readAsStringSync();
      final initStart = source.indexOf('Future<void> init()');
      final promptIndex = source.indexOf(
        'await _maybeShowReleasePrompt();',
        initStart,
      );
      final updateCheckIndex = source.indexOf('_checkNewVersion();', initStart);
      expect(promptIndex, greaterThan(initStart));
      // The chosen channel must be persisted before the update check reads it.
      expect(updateCheckIndex, greaterThan(promptIndex));
    });

    test('prompt is skipped once answered and never re-asked', () {
      final controllerSource = File(
        'lib/ui/screens/Home/home_screen_controller.dart',
      ).readAsStringSync();
      expect(
        controllerSource,
        contains('if (_settingsRepository.isReleasePromptAnswered(prompt.id))'),
      );
      expect(
        controllerSource,
        contains('setReleasePromptAnswered(prompt.id)'),
      );

      final hiveSource = File(
        'lib/data/repositories/hive_settings_repository.dart',
      ).readAsStringSync();
      expect(hiveSource, contains('PrefKeys.answeredReleasePrompts'));
    });

    test('choosing a channel persists it and opens the settings tab', () {
      final dialogSource = File(
        'lib/ui/widgets/release_prompt_dialog.dart',
      ).readAsStringSync();
      final answeredIndex =
          dialogSource.indexOf('markReleasePromptAnswered()');
      final channelIndex = dialogSource.indexOf('changeUpdateChannel(');
      final revealIndex =
          dialogSource.indexOf('requestUpdateChannelReveal()');
      final settingsTabIndex = dialogSource.indexOf('openSettingsTab()');
      expect(answeredIndex, greaterThan(-1));
      expect(channelIndex, greaterThan(-1));
      // The reveal must be requested before navigating so the settings
      // screen mounts with the update-channel section opened.
      expect(revealIndex, greaterThan(-1));
      expect(settingsTabIndex, greaterThan(revealIndex));
      // Both channels must be offered.
      expect(dialogSource, contains('UpdateChannel.stable'));
      expect(dialogSource, contains('UpdateChannel.rolling'));
    });

    test('settings screen opens the section holding the channel setting', () {
      final screenSource = File(
        'lib/ui/screens/Settings/settings_screen.dart',
      ).readAsStringSync();
      final consumeIndex =
          screenSource.indexOf('consumeUpdateChannelReveal()');
      expect(consumeIndex, greaterThan(-1));
      // The reveal flag must expand the App Info tile — the section that
      // contains the update-channel row.
      final appInfoIndex = screenSource.indexOf('"appInfo".tr');
      final revealTileIndex = screenSource.indexOf(
        'initiallyExpanded: revealUpdateChannel',
        appInfoIndex,
      );
      final channelRowIndex = screenSource.indexOf("'Update channel'");
      expect(appInfoIndex, greaterThan(-1));
      expect(revealTileIndex, greaterThan(appInfoIndex));
      expect(
        screenSource.indexOf('"Update channel"'),
        greaterThan(revealTileIndex),
        reason: 'the update-channel row must live inside the revealed tile',
      );
      expect(channelRowIndex, -1);

      final tileSource = File(
        'lib/ui/screens/Settings/components/custom_expansion_tile.dart',
      ).readAsStringSync();
      // Revealed tiles both expand and scroll themselves into view.
      expect(tileSource, contains('initiallyExpanded'));
      expect(tileSource, contains('Scrollable.ensureVisible'));
    });
  });
}
