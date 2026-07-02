import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/controller_providers.dart';
import '../../../utils/runtime_platform.dart';

class PlayerQueueHandle extends ConsumerWidget {
  const PlayerQueueHandle({super.key, required this.bottomPadding});

  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerController = ref.read(playerControllerProvider);
    return InkWell(
      onTap: () async {
        if (RuntimePlatform.isDesktop) {
          playerController.homeScaffoldKey.currentState?.openEndDrawer();
          return;
        }
        await playerController.queuePanelController.open();
      },
      child: Container(
        color: Theme.of(context).primaryColor,
        height: 65 + bottomPadding,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomPadding),
          child: Center(
            child: Icon(
              color: Theme.of(context).textTheme.titleMedium!.color,
              Icons.keyboard_arrow_up,
              size: 40,
            ),
          ),
        ),
      ),
    );
  }
}
