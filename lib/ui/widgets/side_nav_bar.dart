import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/l10n/l10n.dart';
import 'package:sidebar_with_animation/animated_side_bar.dart';

import '../../app/providers/controller_providers.dart';
import 'update_badged_settings_icon.dart';

class SideNavBar extends ConsumerWidget {
  const SideNavBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.of(context).size;
    final isMobileOrTabScreen = size.width < 480;
    final homeScreenController = ref.watch(homeScreenControllerProvider);
    return Align(
      alignment: Alignment.topCenter,
      child: isMobileOrTabScreen
          ? SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 80),
              child: IntrinsicHeight(
                child: AnimatedBuilder(
                  animation: homeScreenController,
                  builder: (context, _) => NavigationRail(
                    useIndicator: !isMobileOrTabScreen,
                    selectedIndex:
                        homeScreenController.tabIndex, //_selectedIndex,
                    onDestinationSelected:
                        homeScreenController.onSideBarTabSelected,
                    minWidth: 60,
                    leading: SizedBox(height: size.height < 750 ? 30 : 60),
                    minExtendedWidth: 250,
                    extended: !isMobileOrTabScreen,
                    labelType: isMobileOrTabScreen
                        ? NavigationRailLabelType.all
                        : NavigationRailLabelType.none,
                    //backgroundColor: Colors.green,
                    destinations: <NavigationRailDestination>[
                      railDestination(
                        context.l10n.home,
                        isMobileOrTabScreen,
                        Icons.home,
                      ),
                      railDestination(
                        context.l10n.songs,
                        isMobileOrTabScreen,
                        Icons.art_track,
                      ),
                      railDestination(
                        context.l10n.playlists,
                        isMobileOrTabScreen,
                        Icons.featured_play_list,
                      ),
                      railDestination(
                        context.l10n.albums,
                        isMobileOrTabScreen,
                        Icons.album,
                      ),
                      railDestination(
                        context.l10n.artists,
                        isMobileOrTabScreen,
                        Icons.people,
                      ),
                      //railDestination("Settings")
                      const NavigationRailDestination(
                        padding: EdgeInsets.only(top: 10, bottom: 10),
                        icon: UpdateBadgedSettingsIcon(
                          icon: Icons.settings_outlined,
                        ),
                        label: SizedBox.shrink(),
                        selectedIcon: UpdateBadgedSettingsIcon(
                          icon: Icons.settings,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.only(bottom: 100.0),
              child: SideBarAnimated(
                onTap: homeScreenController.onSideBarTabSelected,
                sideBarColor: Theme.of(context).primaryColor.withAlpha(250),
                animatedContainerColor: Theme.of(context).colorScheme.secondary,
                hoverColor: Theme.of(
                  context,
                ).colorScheme.secondary.withAlpha(180),
                splashColor: Theme.of(context).colorScheme.secondary,
                highlightColor: Theme.of(
                  context,
                ).colorScheme.secondary.withAlpha(180),
                widthSwitch: 800,
                mainLogoImage: 'assets/icons/icon.png',
                sidebarItems: [
                  SideBarItem(
                    iconSelected: Icons.home,
                    iconUnselected: Icons.home_outlined,
                    text: context.l10n.home,
                  ),
                  SideBarItem(
                    iconSelected: Icons.audiotrack,
                    iconUnselected: Icons.audiotrack,
                    text: context.l10n.songs,
                  ),
                  SideBarItem(
                    iconSelected: Icons.library_music,
                    iconUnselected: Icons.library_music_outlined,
                    text: context.l10n.playlists,
                  ),
                  SideBarItem(
                    iconSelected: Icons.album,
                    iconUnselected: Icons.album_outlined,
                    text: context.l10n.albums,
                  ),
                  SideBarItem(
                    iconSelected: Icons.person,
                    text: context.l10n.artists,
                  ),
                  SideBarItem(
                    iconSelected: Icons.settings,
                    iconUnselected: Icons.settings_outlined,
                    text: context.l10n.settings,
                  ),
                ],
              ),
            ),
    );
  }

  NavigationRailDestination railDestination(
    String label,
    bool isMobileOrTabScreen,
    IconData icon,
  ) {
    return isMobileOrTabScreen
        ? NavigationRailDestination(
            icon: const SizedBox.shrink(),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: isMobileOrTabScreen
                  ? RotatedBox(quarterTurns: -1, child: Text(label))
                  : Text(label),
            ),
          )
        : NavigationRailDestination(
            icon: Icon(icon),
            label: Text(label),
            padding: const EdgeInsets.only(left: 10),
            indicatorShape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            indicatorColor: Colors.amber,
          );
  }
}
