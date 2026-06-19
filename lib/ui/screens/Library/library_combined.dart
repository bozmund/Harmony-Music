import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/player/player_controller.dart';
import '/ui/screens/Home/home_screen_controller.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '/ui/widgets/piped_sync_widget.dart';
import '/ui/widgets/scroll_to_hide.dart';
import '../../widgets/create_playlist_dialog.dart';
import 'library.dart';

class CombinedLibrary extends StatelessWidget {
  const CombinedLibrary({super.key});

  @override
  Widget build(BuildContext context) {
    final tabCon = Get.put(CombinedLibraryController());
    final settingscrnController = Get.find<SettingsScreenController>();
    final homeScreenController = Get.find<HomeScreenController>();
    final playerController = Get.find<PlayerController>();

    return SizedBox.expand(
      child: Column(
        children: [
          _LibraryHeader(settingsController: settingscrnController),
          Expanded(
            child: Obx(() {
              const double tabBarHeight = 50;
              final bottomOffset = _tabBarBottomOffset(
                  context, settingscrnController, homeScreenController,
                  playerController);

              return Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding:
                          EdgeInsets.only(bottom: bottomOffset + tabBarHeight),
                      child: TabBarView(
                        controller: tabCon.tabController,
                        children: const [
                          SongsLibraryWidget(
                            isBottomNavActive: true,
                          ),
                          LibrarySearchWidget(isBottomNavActive: true),
                          PlaylistNAlbumLibraryWidget(
                              isAlbumContent: false,
                              isBottomNavActive: true),
                          PlaylistNAlbumLibraryWidget(
                              isBottomNavActive: true),
                          LibraryArtistWidget(isBottomNavActive: true),
                        ],
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
                            controller: tabCon.tabController),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  double _tabBarBottomOffset(
      BuildContext context,
      SettingsScreenController settingsController,
      HomeScreenController homeScreenController,
      PlayerController playerController) {
    final bottomNavHeight = settingsController.isBottomNavBarEnabled.isTrue &&
            homeScreenController.isHomeSreenOnTop.isTrue &&
            playerController.isPanelGTHOpened.isFalse
        ? ScrollToHideWidget.visibleHeight(context) + 55
        : 0.0;

    final panelHeight = playerController.playerPanelMinHeight.value;
    final miniPlayerHeight = playerController.currentSong.value != null &&
            playerController.isPlayerpanelTopVisible.isTrue
        ? settingsController.isBottomNavBarEnabled.isTrue
            ? 75.0
            : panelHeight > 0
                ? panelHeight
                : 75.0
        : 0.0;

    return bottomNavHeight + miniPlayerHeight;
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
              Obx(() => settingsController.isLinkedWithPiped.isTrue
                  ? const PipedSyncWidget(
                      padding: EdgeInsets.only(right: 10))
                  : const SizedBox.shrink()),
              SizedBox(
                height: 40,
                width: 50,
                child: FittedBox(
                  child: FloatingActionButton.extended(
                      elevation: 0,
                      onPressed: () {
                        showDialog(
                            context: context,
                            builder: (context) =>
                                const CreateNRenamePlaylistPopup());
                      },
                      label: const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Icon(
                            Icons.add,
                          ),
                        ],
                      )),
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
  const _LibraryTabBar({required this.controller});

  final TabController controller;

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
      tabs: [
        Tab(text: "songs".tr),
        Tab(text: "searches".tr),
        Tab(text: "playlists".tr),
        Tab(text: "albums".tr),
        Tab(text: "artists".tr),
      ],
    );
  }
}

class CombinedLibraryController extends GetxController
    with GetSingleTickerProviderStateMixin {
  late TabController tabController;

  @override
  void onInit() {
    super.onInit();
    tabController = TabController(vsync: this, length: 5);
  }

  @override
  void onClose() {
    tabController.dispose();
    super.onClose();
  }
}
