import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../utils/helper.dart';
import '../screens/Home/home_screen_controller.dart';
import '../screens/Settings/settings_screen_controller.dart';
import 'common_dialog_widget.dart';

class NewVersionDialog extends StatelessWidget {
  const NewVersionDialog({super.key, required this.updateInfo});
  final UpdateInfo updateInfo;

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsScreenController>();
    return CommonDialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: Get.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 36),
              child: Text(
                "newVersionAvailable".tr,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: SizedBox.square(
                dimension: 100,
                child: FittedBox(
                  child: FloatingActionButton(
                    onPressed: () {
                      settingsController.downloadAndInstallUpdate(updateInfo);
                    },
                    child: Obx(
                      () => settingsController.isUpdateDownloading.value
                          ? const SizedBox.square(
                              dimension: 28,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            )
                          : const Icon(Icons.download, size: 30),
                    ),
                  ),
                ),
              ),
            ),
            Obx(() {
              if (!settingsController.isUpdateDownloading.value) {
                return const SizedBox(height: 20);
              }
              final progress =
                  (settingsController.updateDownloadProgress.value * 100)
                      .clamp(0, 100)
                      .round();
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  "Downloading update $progress%",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            }),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GetX<HomeScreenController>(
                    builder: (controller) {
                      return Checkbox(
                        value: controller.showVersionDialog.isFalse,
                        onChanged: (val) {
                          controller.onChangeVersionVisibility(val ?? false);
                        },
                        shape: const CircleBorder(),
                      );
                    },
                  ),
                  Flexible(child: Text("dontShowInfoAgain".tr)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 20, top: 6),
              child: Obx(
                () => Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _DialogActionButton(
                      label: "download".tr,
                      enabled: !settingsController.isUpdateDownloading.value,
                      onTap: () {
                        settingsController.downloadAndInstallUpdate(updateInfo);
                      },
                    ),
                    _DialogActionButton(
                      label: "dismiss".tr,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogActionButton extends StatelessWidget {
  const _DialogActionButton({
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).canvasColor;
    return Opacity(
      opacity: enabled ? 1 : 0.65,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).textTheme.titleLarge!.color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15.0, vertical: 10),
            child: Text(label, style: TextStyle(color: foreground)),
          ),
        ),
      ),
    );
  }
}
