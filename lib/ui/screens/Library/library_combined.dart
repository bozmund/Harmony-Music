import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/player/player_controller.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '/ui/widgets/piped_sync_widget.dart';
import '../../widgets/create_playlist_dialog.dart';
import 'library.dart';

class CombinedLibrary extends StatelessWidget {
  const CombinedLibrary({super.key});

  @override
  Widget build(BuildContext context) {
    final tabCon = Get.put(CombinedLibraryController());
    final settingscrnController = Get.find<SettingsScreenController>();
    final PlayerController playerController = Get.find<PlayerController>();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 85,
        backgroundColor: Theme.of(context).canvasColor,
        elevation: 0,
        actions: [
          Obx(() => (settingscrnController.isLinkedWithPiped.isTrue)
              ? const PipedSyncWidget(
                  padding: EdgeInsets.only(right: 10, top: 50))
              : const SizedBox.shrink()),
          Padding(
            padding: const EdgeInsets.only(top: 50.0, right: 25),
            child: SizedBox(
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
          ),
        ],
        title: Padding(
          padding: const EdgeInsets.only(top: 60.0, left: 5),
          child:
              Text('library'.tr, style: Theme.of(context).textTheme.titleLarge),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 110),
              child: TabBarView(
                controller: tabCon.tabController,
                children: const [
                  SongsLibraryWidget(
                    isBottomNavActive: true,
                  ),
                  LibrarySearchWidget(isBottomNavActive: true),
                  PlaylistNAlbumLibraryWidget(
                      isAlbumContent: false, isBottomNavActive: true),
                  PlaylistNAlbumLibraryWidget(isBottomNavActive: true),
                  LibraryArtistWidget(isBottomNavActive: true),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Obx(() {
              final minHeight = playerController.playerPanelMinHeight.value;
              // If minHeight is small (likely just safe area), we add a base offset
              // for the BottomNavBar which is usually around 120dp.
              final bottomPadding = minHeight > 40 ? 200.0 : 120.0;
              return Container(
                padding: EdgeInsets.only(bottom: bottomPadding),
                decoration: BoxDecoration(
                  color: Theme.of(context).canvasColor,
                ),
                child: SizedBox(
                  height: 50,
                  child: TabBar(
                    isScrollable: true,
                    splashFactory: NoSplash.splashFactory,
                    controller: tabCon.tabController,
                    labelColor: Theme.of(context).colorScheme.secondary,
                    unselectedLabelColor:
                        Theme.of(context).textTheme.bodySmall!.color,
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
                  ),
                ),
              );
            }),
          ),
        ],
      ),
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
