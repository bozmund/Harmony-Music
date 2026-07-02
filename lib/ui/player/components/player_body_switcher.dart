import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/controller_providers.dart';
import 'gesture_player.dart';
import 'standard_player.dart';

class PlayerBodySwitcher extends ConsumerWidget {
  const PlayerBodySwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsController = ref.watch(settingsScreenControllerProvider);
    return AnimatedBuilder(
      animation: settingsController,
      builder: (context, _) => settingsController.playerUi.value == 0
          ? const StandardPlayer()
          : const GesturePlayer(),
    );
  }
}
