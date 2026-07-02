import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/utils/get_localization.dart';
import 'package:harmonymusic/ui/utils/theme_controller.dart';
import 'package:toggle_switch/toggle_switch.dart';

import '../../../app/providers/controller_providers.dart';

class LyricsSwitch extends ConsumerWidget {
  const LyricsSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerController = ref.read(playerControllerProvider);
    return AnimatedBuilder(
      animation: Listenable.merge([
        playerController.showLyricsFlag,
        playerController.lyricsMode,
      ]),
      builder: (context, _) => playerController.showLyricsFlag.value
          ? Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: ToggleSwitch(
                minWidth: 90.0,
                cornerRadius: 20.0,
                activeBgColors: [
                  [Theme.of(context).primaryColor.withLightness(0.4)],
                  [Theme.of(context).primaryColor.withLightness(0.4)],
                ],
                activeFgColor: Colors.white,
                inactiveBgColor: Theme.of(context).colorScheme.secondary,
                inactiveFgColor: Colors.white,
                initialLabelIndex: playerController.lyricsMode.value,
                totalSwitches: 2,
                labels: ['synced'.tr, 'plain'.tr],
                radiusStyle: true,
                onToggle: playerController.changeLyricsMode,
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
