import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/utils/get_localization.dart';

import '../../app/providers/controller_providers.dart';
import '../../utils/helper.dart';
import 'common_dialog_widget.dart';

/// The one-time prompt shipped with 6.0.0 (see
/// lib/services/release_prompt.dart): stable became the default update
/// channel, so users pick explicitly which channel they want to follow.
/// Choosing writes the setting, then opens the Settings tab so the user
/// sees where the choice can be changed later.
class ReleasePromptDialog extends ConsumerWidget {
  const ReleasePromptDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CommonDialog(
      child: Container(
        padding: const EdgeInsets.only(top: 30, bottom: 25, left: 20, right: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "chooseUpdateChannel".tr,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 18),
              child: Text(
                "chooseUpdateChannelDes".tr,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
            _ChannelChoiceTile(
              title: "stableChannelOption".tr,
              description: "stableChannelOptionDes".tr,
              onTap: () => _choose(context, ref, UpdateChannel.stable),
            ),
            const SizedBox(height: 10),
            _ChannelChoiceTile(
              title: "rollingChannelOption".tr,
              description: "rollingChannelOptionDes".tr,
              onTap: () => _choose(context, ref, UpdateChannel.rolling),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    UpdateChannel channel,
  ) async {
    final settingsController = ref.read(settingsScreenControllerProvider);
    final homeController = ref.read(homeScreenControllerProvider);

    await homeController.markReleasePromptAnswered();
    Navigator.of(context, rootNavigator: true).pop();
    // The channel change kicks off an update check; don't block the UI on it.
    unawaited(settingsController.changeUpdateChannel(channel.name));
    // Land the user on the Settings tab with the section containing the
    // update-channel setting opened, so they see where to change it later.
    settingsController.requestUpdateChannelReveal();
    homeController.openSettingsTab();
  }
}

class _ChannelChoiceTile extends StatelessWidget {
  const _ChannelChoiceTile({
    required this.title,
    required this.description,
    required this.onTap,
  });

  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
