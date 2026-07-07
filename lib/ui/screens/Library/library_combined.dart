import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/utils/get_localization.dart';

import '../../../app/providers/controller_providers.dart';
import '/services/constant.dart';
import '/ui/player/player_controller.dart';
import '/ui/screens/Home/home_screen_controller.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '/ui/widgets/piped_sync_widget.dart';
import '/ui/widgets/scroll_to_hide.dart';
import '../../widgets/create_playlist_dialog.dart';
import 'library.dart';

List<String> getOrderedTabKeys(int firstTabIndex) {
  final keys = List<String>.from(libraryTabKeys);
  if (firstTabIndex >= 0 && firstTabIndex < keys.length) {
    final firstKey = keys.removeAt(firstTabIndex);
    keys.insert(0, firstKey);
  }
  return keys;
}

List<Widget> getOrderedLibraryWidgets(int firstTabIndex) {
  final widgets = [
    const SongsLibraryWidget(isBottomNavActive: true),
    const LibrarySearchWidget(isBottomNavActive: true),
    const PlaylistNAlbumLibraryWidget(
      isAlbumContent: false,
      isBottomNavActive: true,
    ),
    const PlaylistNAlbumLibraryWidget(isBottomNavActive: true),
    const LibraryArtistWidget(isBottomNavActive: true),
  ];
  if (firstTabIndex >= 0 && firstTabIndex < widgets.length) {
    final firstWidget = widgets.removeAt(firstTabIndex);
    widgets.insert(0, firstWidget);
  }
  return widgets;
}

class CombinedLibrary extends ConsumerStatefulWidget {
  const CombinedLibrary({super.key});

  @override
  ConsumerState<CombinedLibrary> createState() => _CombinedLibraryState();
}

class _CombinedLibraryState extends ConsumerState<CombinedLibrary>
    with SingleTickerProviderStateMixin {
  late final TabController tabController;
  late final SettingsScreenController settingScreenController;
  late final HomeScreenController homeScreenController;
  late final PlayerController playerController;
  StreamSubscription<int>? _libraryFirstTabSubscription;

  @override
  void initState() {
    super.initState();
    tabController = TabController(
      vsync: this,
      length: libraryTabKeys.length,
      initialIndex: 0,
    );
    settingScreenController = ref.read(settingsScreenControllerProvider);
    homeScreenController = ref.read(homeScreenControllerProvider);
    playerController = ref.read(playerControllerProvider);
    _libraryFirstTabSubscription = settingScreenController.libraryFirstTab
        .listen((_) => _resetToFirstTab());
  }

  void _resetToFirstTab() {
    if (tabController.index == 0) return;
    tabController.animateTo(0);
  }

  @override
  void dispose() {
    final subscription = _libraryFirstTabSubscription;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CombinedLibraryTabControllerScope(
      controller: tabController,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          settingScreenController,
          homeScreenController,
          playerController,
        ]),
        builder: (context, _) => SizedBox.expand(
        child: Column(
          children: [
            _LibraryHeader(settingsController: settingScreenController),
            Expanded(
              child: Builder(builder: (context) {
                const double tabBarHeight = 50;
                final bottomOffset = _tabBarBottomOffset(
                  context,
                  settingScreenController,
                  homeScreenController,
                  playerController,
                );

                return Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: EdgeInsets.only(
                          bottom: bottomOffset + tabBarHeight,
                        ),
                        child: TabBarView(
                          controller: tabController,
                          children: getOrderedLibraryWidgets(
                            settingScreenController.libraryFirstTab.value,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: bottomOffset,
                      child: ColoredBox(
                        color: Theme.of(context).canvasColor,
                        child: SizedBox(
                          height: tabBarHeight,
                          child: _LibraryTabBar(
                            controller: tabController,
                            firstTabIndex:
                                settingScreenController.libraryFirstTab.value,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
        ),
      ),
    );
  }

  double _tabBarBottomOffset(
    BuildContext context,
    SettingsScreenController settingsController,
    HomeScreenController homeScreenController,
    PlayerController playerController,
  ) {
    // The sliding panel lays the library out at full screen height (behind
    // the bottom nav bar), so the tab bar must clear whatever occupies the
    // bottom of the screen: the nav bar (when shown) plus the mini player.
    // Reserve exactly the nav bar's real footprint — ScrollToHideWidget's
    // own height, which already tracks the system gesture/button inset via
    // viewPadding.bottom — with no extra padding, so no dead space is left.
    final bottomNavHeight =
        settingsController.isBottomNavBarEnabled.value &&
            homeScreenController.isHomeScreenOnTop &&
            !playerController.playerPanelOpen.value
        ? ScrollToHideWidget.visibleHeight(context)
        : 0.0;

    final panelHeight = playerController.playerPanelMinHeight.value;
    final miniPlayerHeight =
        playerController.currentSong.value != null &&
            playerController.playerPanelTopVisible.value
        ? settingsController.isBottomNavBarEnabled.value
              ? 75.0
              : panelHeight > 0
              ? panelHeight
              : 75.0
        : 0.0;

    return bottomNavHeight + miniPlayerHeight;
  }
}

class CombinedLibraryTabControllerScope extends InheritedWidget {
  const CombinedLibraryTabControllerScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final TabController controller;

  static TabController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CombinedLibraryTabControllerScope>()
        ?.controller;
  }

  @override
  bool updateShouldNotify(CombinedLibraryTabControllerScope oldWidget) {
    return controller != oldWidget.controller;
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({required this.settingsController});

  final SettingsScreenController settingsController;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).canvasColor,
      child: SizedBox(
        height: 85,
        child: Padding(
          padding: const EdgeInsets.only(left: 25, right: 25, top: 45),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'library'.tr,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              AnimatedBuilder(
                animation: settingsController,
                builder: (context, _) => settingsController.isLinkedWithPiped.value
                    ? const PipedSyncWidget(padding: EdgeInsets.only(right: 10))
                    : const SizedBox.shrink(),
              ),
              SizedBox(
                height: 40,
                width: 50,
                child: FittedBox(
                  child: FloatingActionButton.extended(
                    elevation: 0,
                    onPressed: () async {
                      await showDialog(
                        context: context,
                        builder: (context) =>
                            const CreateNRenamePlaylistPopup(),
                      );
                    },
                    label: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [Icon(Icons.add)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryTabBar extends StatelessWidget {
  const _LibraryTabBar({required this.controller, required this.firstTabIndex});

  final TabController controller;
  final int firstTabIndex;

  @override
  Widget build(BuildContext context) {
    return TabBar(
      isScrollable: true,
      splashFactory: NoSplash.splashFactory,
      controller: controller,
      labelColor: Theme.of(context).colorScheme.secondary,
      unselectedLabelColor: Theme.of(context).textTheme.bodySmall!.color,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(
          width: 3.0,
          color: Theme.of(context).colorScheme.secondary,
        ),
        insets: const EdgeInsets.symmetric(horizontal: 16.0),
      ),
      tabs: getOrderedTabKeys(
        firstTabIndex,
      )
          .map(
            (key) => Tab(
              height: 50,
              child: Text(
                key.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
    );
  }
}
