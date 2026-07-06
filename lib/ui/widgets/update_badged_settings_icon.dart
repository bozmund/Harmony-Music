import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/controller_providers.dart';
import '../../utils/update_check_flag_file.dart';

class UpdateBadgedSettingsIcon extends ConsumerWidget {
  const UpdateBadgedSettingsIcon({
    super.key,
    required this.icon,
    this.size,
    this.dotSize = 8,
  });

  final IconData icon;
  final double? size;
  final double dotSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsController = ref.watch(settingsScreenControllerProvider);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: size),
        if (updateCheckFlag)
          AnimatedBuilder(
            animation: settingsController,
            builder: (context, _) =>
                settingsController.isNewVersionAvailable.value
                ? Positioned(
                    top: -1,
                    right: -1,
                    child: Container(
                      width: dotSize,
                      height: dotSize,
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
      ],
    );
  }
}
