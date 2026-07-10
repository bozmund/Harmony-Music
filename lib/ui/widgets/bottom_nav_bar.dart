import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/l10n/l10n.dart';

import '../../app/providers/controller_providers.dart';
import 'bottom_nav_bar_dimensions.dart';
import 'update_badged_settings_icon.dart';

class BottomNavBar extends ConsumerWidget {
  const BottomNavBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeScreenController = ref.watch(homeScreenControllerProvider);
    return AnimatedBuilder(
      animation: homeScreenController,
      builder: (context, _) => NavigationBar(
        height: compactBottomNavBarHeight,
        onDestinationSelected: homeScreenController.onBottonBarTabSelected,
        selectedIndex: homeScreenController.tabIndex,
        backgroundColor: Theme.of(context).primaryColor,
        indicatorColor: Theme.of(context).colorScheme.secondary,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(
            selectedIcon: const Icon(Icons.home),
            icon: const Icon(Icons.home_outlined),
            label: modifyNGetLabel(context.l10n.home),
          ),
          NavigationDestination(
            icon: const Icon(Icons.search),
            label: modifyNGetLabel(context.l10n.search),
          ),
          NavigationDestination(
            icon: const Icon(Icons.library_music),
            label: modifyNGetLabel(context.l10n.library),
          ),
          NavigationDestination(
            selectedIcon: const UpdateBadgedSettingsIcon(icon: Icons.settings),
            icon: const UpdateBadgedSettingsIcon(icon: Icons.settings_outlined),
            label: modifyNGetLabel(context.l10n.settings),
          ),
        ],
      ),
    );
  }

  String modifyNGetLabel(String label) {
    if (label.length > 9) {
      return "${label.substring(0, 8)}..";
    }
    return label;
  }
}
