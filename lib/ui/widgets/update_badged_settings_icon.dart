import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../utils/update_check_flag_file.dart';
import '../screens/Settings/settings_screen_controller.dart';

class UpdateBadgedSettingsIcon extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsScreenController>();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: size),
        if (updateCheckFlag)
          Obx(
            () => settingsController.isNewVersionAvailable.value
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
