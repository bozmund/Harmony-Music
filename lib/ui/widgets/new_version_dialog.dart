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
      child: Container(
        height: 320,
        padding: const EdgeInsets.only(top: 40, bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              "newVersionAvailable".tr,
              style: Theme.of(context).textTheme.titleMedium,
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
                  Text("dontShowInfoAgain".tr),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).textTheme.titleLarge!.color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: InkWell(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15.0,
                    vertical: 10,
                  ),
                  child: Text(
                    "dismiss".tr,
                    style: TextStyle(color: Theme.of(context).canvasColor),
                  ),
                ),
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
