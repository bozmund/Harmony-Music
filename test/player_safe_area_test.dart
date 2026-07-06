import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('player queue handle stays above Android navigation area', () {
    final panelSource = File(
      'lib/ui/player/components/player_queue_panel.dart',
    ).readAsStringSync();
    final handleSource = File(
      'lib/ui/player/components/player_queue_handle.dart',
    ).readAsStringSync();

    expect(panelSource, contains('mediaQuery.viewPadding.bottom'));
    expect(
      panelSource,
      contains('minHeight: settingsController.playerUi.value == 0'),
    );
    expect(panelSource, contains('65 + bottomPadding'));
    expect(handleSource, contains('65 + bottomPadding'));
    expect(
      handleSource,
      contains('padding: EdgeInsets.only(bottom: bottomPadding)'),
    );
  });

  test('player shell delegates queue panel details', () {
    final playerSource = File('lib/ui/player/player.dart').readAsStringSync();

    expect(playerSource, contains('const Scaffold(body: PlayerQueuePanel())'));
    expect(playerSource, isNot(contains('SlidingUpPanel')));
    expect(playerSource, isNot(contains('UpNextQueue')));
    expect(playerSource, isNot(contains('BackdropFilter')));
  });
}
