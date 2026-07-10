import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/l10n/l10n.dart';

import '../../app/providers/controller_providers.dart';
import '../../utils/helper.dart';
import 'common_dialog_widget.dart';

class NewVersionDialog extends ConsumerWidget {
  const NewVersionDialog({super.key, required this.updateInfo});

  final UpdateInfo updateInfo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsController = ref.watch(settingsScreenControllerProvider);
    final homeController = ref.watch(homeScreenControllerProvider);
    return CommonDialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 36),
              child: Text(
                context.l10n.newVersionAvailable,
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
                    onPressed: () async {
                      await settingsController.downloadAndInstallUpdate(
                        updateInfo,
                      );
                    },
                    child: AnimatedBuilder(
                      animation: settingsController,
                      builder: (context, _) =>
                          settingsController.isUpdateDownloading.value
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
            AnimatedBuilder(
              animation: settingsController,
              builder: (context, _) {
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
              },
            ),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: homeController,
                    builder: (context, _) => Checkbox(
                      value: !homeController.showVersionDialog,
                      onChanged: (val) {
                        homeController.onChangeVersionVisibility(val ?? false);
                      },
                      shape: const CircleBorder(),
                    ),
                  ),
                  Flexible(child: Text(context.l10n.dontShowInfoAgain)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 20, top: 6),
              child: AnimatedBuilder(
                animation: settingsController,
                builder: (context, _) => Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _DialogActionButton(
                      label: context.l10n.download,
                      enabled: !settingsController.isUpdateDownloading.value,
                      onTap: () async {
                        await settingsController.downloadAndInstallUpdate(
                          updateInfo,
                        );
                      },
                    ),
                    _DialogActionButton(
                      label: context.l10n.dismiss,
                      onTap: () {
                        // If the user just turned off the startup update
                        // popup, send them to the Settings App Info section
                        // (which holds "Check for updates") so they know
                        // where to look — otherwise a future update would go
                        // unnoticed. The checkbox reflects showVersionDialog,
                        // so a false value means the popup was disabled.
                        final disabledStartupPopup =
                            !homeController.showVersionDialog;
                        Navigator.of(context).pop();
                        if (disabledStartupPopup) {
                          settingsController.requestUpdateSectionReveal();
                          homeController.openSettingsTab();
                        }
                      },
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
