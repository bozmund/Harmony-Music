import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/controller_providers.dart';
import '../../../utils/runtime_platform.dart';
import '../../widgets/sliding_up_panel.dart';
import '../../widgets/up_next_queue.dart';
import 'player_body_switcher.dart';
import 'player_queue_footer_controls.dart';
import 'player_queue_handle.dart';

class PlayerQueuePanel extends ConsumerWidget {
  const PlayerQueuePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final bottomPadding = mediaQuery.viewPadding.bottom;
    final playerController = ref.read(playerControllerProvider);
    final settingsController = ref.read(settingsScreenControllerProvider);

    return AnimatedBuilder(
      animation: settingsController.playerUi,
      builder: (context, _) => SlidingUpPanel(
        setsScreenMode: false,
        boxShadow: const [],
        minHeight: settingsController.playerUi.value == 0
            ? 65 + bottomPadding
            : 0,
        maxHeight: size.height,
        isDraggable: !RuntimePlatform.isDesktop,
        controller: RuntimePlatform.isDesktop
            ? null
            : playerController.queuePanelController,
        collapsed: PlayerQueueHandle(bottomPadding: bottomPadding),
        panelBuilder: (scrollController, onReorderStart, onReorderEnd) {
          playerController.scrollController = scrollController;
          return Stack(
            children: [
              UpNextQueue(
                onReorderEnd: onReorderEnd,
                onReorderStart: onReorderStart,
              ),
              PlayerQueueFooterControls(bottomPadding: bottomPadding),
            ],
          );
        },
        body: const PlayerBodySwitcher(),
      ),
    );
  }
}
