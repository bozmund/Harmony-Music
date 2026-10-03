import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/l10n/l10n.dart';

import '../../app/providers/controller_providers.dart';
import '../../models/mobile_nav_item.dart';
import 'bottom_nav_bar_dimensions.dart';
import 'update_badged_settings_icon.dart';

class BottomNavBar extends ConsumerWidget {
  const BottomNavBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeScreenController = ref.watch(homeScreenControllerProvider);
    final settingsScreenController = ref.watch(settingsScreenControllerProvider);

    return AnimatedBuilder(
      animation: Listenable.merge([
        homeScreenController,
        settingsScreenController,
      ]),
      builder: (context, _) {
        final order = settingsScreenController.mobileNavOrder.isEmpty
            ? defaultMobileNavOrder
            : settingsScreenController.mobileNavOrder.toList();

        final selectedVisualIndex = order.indexWhere(
              (item) => item.tabIndex == homeScreenController.tabIndex,
        );

        return NavigationBar(
          height: compactBottomNavBarHeight,
          onDestinationSelected: (visualIndex) {
            if (visualIndex < 0 || visualIndex >= order.length) {
              return;
            }

            final item = order[visualIndex];

            homeScreenController.onBottonBarTabSelected(
              item.tabIndex,
            );
          },
          selectedIndex:
          selectedVisualIndex >= 0 ? selectedVisualIndex : 0,
          backgroundColor: Theme.of(context).primaryColor,
          indicatorColor: Theme.of(context).colorScheme.secondary,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: order
              .map(
                (item) => _buildDestination(
              context,
              item,
            ),
          )
              .toList(),
        );
      },
    );
  }

  NavigationDestination _buildDestination(
      BuildContext context,
      MobileNavItem item,
      ) {
    return switch (item) {
      MobileNavItem.home => NavigationDestination(
        selectedIcon: const Icon(Icons.home),
        icon: const Icon(Icons.home_outlined),
        label: modifyNGetLabel(context.l10n.home),
      ),
      MobileNavItem.library => NavigationDestination(
        icon: const Icon(Icons.library_music),
        label: modifyNGetLabel(context.l10n.library),
      ),
      MobileNavItem.search => NavigationDestination(
        icon: const Icon(Icons.search),
        label: modifyNGetLabel(context.l10n.search),
      ),
      MobileNavItem.settings => NavigationDestination(
        selectedIcon: const UpdateBadgedSettingsIcon(
          icon: Icons.settings,
        ),
        icon: const UpdateBadgedSettingsIcon(
          icon: Icons.settings_outlined,
        ),
        label: modifyNGetLabel(context.l10n.settings),
      ),
    };
  }

  String modifyNGetLabel(String label) {
    if (label.length > 9) {
      return "${label.substring(0, 8)}..";
    }
    return label;
  }
}