import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/widgets/modification_list.dart';
import '../../../models/playlist.dart';
import '../../widgets/piped_sync_widget.dart';
import 'library_controller.dart';
import 'library_combined.dart';
import '../../widgets/content_list_widget_item.dart';
import '../../widgets/list_widget.dart';
import '../../widgets/sort_widget.dart';
import '../Settings/settings_screen_controller.dart';

class SongsLibraryWidget extends StatelessWidget {
  const SongsLibraryWidget({super.key, this.isBottomNavActive = false});
  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context) {
    final topPadding = context.isLandscape ? 50.0 : 90.0;
    return Padding(
      padding: isBottomNavActive
          ? const EdgeInsets.only(left: 15)
          : EdgeInsets.only(left: 5.0, top: topPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          isBottomNavActive
              ? const SizedBox(height: 10)
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "libSongs".tr,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
          Obx(() {
            final libSongsController = Get.find<LibrarySongsController>();
            return SortWidget(
              tag: LibrarySongsController.sortWidgetTag,
              screenController: libSongsController,
              itemCountTitle: "${libSongsController.librarySongsList.length}",
              itemIcon: Icons.music_note,
              titleLeftPadding: 9,
              requiredSortTypes: buildSortTypeSet(true, true),
              initialSortType: LibrarySongsController.defaultSortType,
              initialIsAscending: LibrarySongsController.defaultSortAscending,
              isSearchFeatureRequired: true,
              isSongDeletionFeatureRequired: true,
              onSort: (type, ascending) {
                libSongsController.onSort(type, ascending);
              },
              onSearch: libSongsController.onSearch,
              onSearchClose: libSongsController.onSearchClose,
              onSearchStart: libSongsController.onSearchStart,
              startAdditionalOperation:
                  libSongsController.startAdditionalOperation,
              selectAll: libSongsController.selectAll,
              performAdditionalOperation:
                  libSongsController.performAdditionalOperation,
              cancelAdditionalOperation:
                  libSongsController.cancelAdditionalOperation,
            );
          }),
          GetX<LibrarySongsController>(
            builder: (controller) {
              return controller.librarySongsList.isNotEmpty
                  ? (controller.additionalOperationMode.value ==
                            OperationMode.none
                        ? ListWidget(
                            controller.librarySongsList,
                            "library Songs",
                            true,
                            isPlaylistOrAlbum: true,
                            playlist: Playlist(
                              title: "Library Songs",
                              playlistId: "SongsDownloads",
                              thumbnailUrl: "",
                              isCloudPlaylist: false,
                            ),
                          )
                        : ModificationList(
                            mode: controller.additionalOperationMode.value,
                            screenController: controller,
                          ))
                  : Expanded(
                      child: Center(
                        child: Text(
                          "noOfflineSong".tr,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    );
            },
          ),
        ],
      ),
    );
  }
}

class PlaylistNAlbumLibraryWidget extends StatelessWidget {
  const PlaylistNAlbumLibraryWidget({
    super.key,
    this.isAlbumContent = true,
    this.isBottomNavActive = false,
  });
  final bool isAlbumContent;
  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context) {
    final libraryAlbumController = Get.find<LibraryAlbumsController>();
    final libraryPlaylistController = Get.find<LibraryPlaylistsController>();
    final settingsScreenController = Get.find<SettingsScreenController>();
    final size = MediaQuery.of(context).size;

    const double itemHeight = 180;
    const double itemWidth = 130;
    final topPadding = context.isLandscape ? 50.0 : 90.0;

    return Padding(
      padding: isBottomNavActive
          ? const EdgeInsets.only(left: 15)
          : EdgeInsets.only(top: topPadding),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 5.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                isBottomNavActive
                    ? const SizedBox(height: 10)
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          isAlbumContent ? "libAlbums".tr : "libPlaylists".tr,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                (settingsScreenController.isBottomNavBarEnabled.isTrue ||
                        isAlbumContent ||
                        settingsScreenController.isLinkedWithPiped.isFalse)
                    ? const SizedBox.shrink()
                    : PipedSyncWidget(
                        padding: EdgeInsets.only(right: size.width * .05),
                      ),
              ],
            ),
          ),
          Obx(
            () => isAlbumContent
                ? SortWidget(
                    tag: "LibAlbumSort",
                    screenController: libraryAlbumController,
                    isAdditionalOperationRequired: false,
                    isSearchFeatureRequired: true,
                    itemCountTitle:
                        "${libraryAlbumController.libraryAlbums.length} ${"items".tr}",
                    requiredSortTypes: buildSortTypeSet(true),
                    onSort: (type, ascending) {
                      libraryAlbumController.onSort(type, ascending);
                    },
                    onSearch: libraryAlbumController.onSearch,
                    onSearchClose: libraryAlbumController.onSearchClose,
                    onSearchStart: libraryAlbumController.onSearchStart,
                  )
                : SortWidget(
                    tag: "LibPlaylistSort",
                    screenController: libraryPlaylistController,
                    isAdditionalOperationRequired: false,
                    isSearchFeatureRequired: true,
                    itemCountTitle:
                        "${libraryPlaylistController.libraryPlaylists.length} ${"items".tr}",
                    requiredSortTypes: buildSortTypeSet(),
                    onSort: (type, ascending) {
                      libraryPlaylistController.onSort(type, ascending);
                    },
                    onSearch: libraryPlaylistController.onSearch,
                    onSearchClose: libraryPlaylistController.onSearchClose,
                    onSearchStart: libraryPlaylistController.onSearchStart,
                    isImportFeatureRequired: true,
                  ),
          ),
          Expanded(
            child: Obx(
              () =>
                  (isAlbumContent
                      ? libraryAlbumController.libraryAlbums.isNotEmpty
                      : libraryPlaylistController.libraryPlaylists.isNotEmpty)
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        //Fix for grid in mobile screen
                        final availableWidth =
                            constraints.maxWidth > 300 &&
                                constraints.maxWidth < 394
                            ? 310.0
                            : constraints.maxWidth;
                        int columns = (availableWidth / itemWidth).floor();
                        return SizedBox(
                          width: availableWidth,
                          child: GridView.builder(
                            physics: const BouncingScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  childAspectRatio: itemWidth / itemHeight,
                                ),
                            controller: ScrollController(
                              keepScrollOffset: false,
                            ),
                            shrinkWrap: true,
                            scrollDirection: Axis.vertical,
                            padding: const EdgeInsets.only(
                              bottom: 200,
                              top: 10,
                            ),
                            itemCount: isAlbumContent
                                ? libraryAlbumController.libraryAlbums.length
                                : libraryPlaylistController
                                      .libraryPlaylists
                                      .length,
                            itemBuilder: (context, index) => Center(
                              child: ContentListItem(
                                content: isAlbumContent
                                    ? libraryAlbumController
                                          .libraryAlbums[index]
                                    : libraryPlaylistController
                                          .libraryPlaylists[index],
                                isLibraryItem: true,
                              ),
                            ),
                          ),
                        );
                      },
                    )
                  : Center(
                      child: Text(
                        "noBookmarks".tr,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class LibraryArtistWidget extends StatelessWidget {
  const LibraryArtistWidget({super.key, this.isBottomNavActive = false});
  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context) {
    final libraryArtistsController = Get.find<LibraryArtistsController>();
    final topPadding = context.isLandscape ? 50.0 : 90.0;
    return Padding(
      padding: isBottomNavActive
          ? const EdgeInsets.only(left: 15)
          : EdgeInsets.only(left: 5, top: topPadding),
      child: Column(
        children: [
          isBottomNavActive
              ? const SizedBox(height: 10)
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "libArtists".tr,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
          Obx(
            () => SortWidget(
              tag: "LibArtistSort",
              screenController: libraryArtistsController,
              isAdditionalOperationRequired: false,
              isSearchFeatureRequired: true,
              itemCountTitle:
                  "${libraryArtistsController.libraryArtists.length} ${"items".tr}",
              onSort: (type, ascending) {
                libraryArtistsController.onSort(type, ascending);
              },
              onSearch: libraryArtistsController.onSearch,
              onSearchClose: libraryArtistsController.onSearchClose,
              onSearchStart: libraryArtistsController.onSearchStart,
            ),
          ),
          Obx(
            () => libraryArtistsController.libraryArtists.isNotEmpty
                ? ListWidget(
                    libraryArtistsController.libraryArtists,
                    "Library Artists",
                    true,
                  )
                : Expanded(
                    child: Center(
                      child: Text(
                        "noBookmarks".tr,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class LibrarySearchWidget extends StatelessWidget {
  const LibrarySearchWidget({super.key, this.isBottomNavActive = false});
  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(LibrarySearchesController());
    final topPadding = context.isLandscape ? 50.0 : 90.0;
    return Padding(
      padding: isBottomNavActive
          ? const EdgeInsets.only(left: 15)
          : EdgeInsets.only(left: 5, top: topPadding),
      child: Column(
        children: [
          isBottomNavActive
              ? const SizedBox(height: 10)
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "searches".tr,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
          Expanded(
            child: Obx(
              () => controller.savedSearches.isNotEmpty
                  ? ListView.builder(
                      itemCount: controller.savedSearches.length,
                      itemBuilder: (context, index) {
                        final query = controller.savedSearches[index];
                        return ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(query),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => controller.deleteSearch(query),
                          ),
                          onTap: () {
                            // Find CombinedLibraryController to switch tabs
                            final combinedLibController =
                                Get.find<CombinedLibraryController>();

                            // All saved searches apply to the Songs tab
                            int targetTab = 0;

                            combinedLibController.tabController.animateTo(
                              targetTab,
                            );

                            // Apply search to the Songs controller
                            Future.delayed(
                              const Duration(milliseconds: 300),
                              () {
                                const tag = LibrarySongsController.sortWidgetTag;
                                final targetController =
                                    Get.find<LibrarySongsController>();
                                if (!Get.isRegistered<SortWidgetController>(
                                  tag: tag,
                                )) {
                                  return;
                                }

                                final sortWidgetController =
                                    Get.find<SortWidgetController>(tag: tag);
                                if (!sortWidgetController
                                    .isSearchingEnabled
                                    .value) {
                                  targetController.onSearchStart(tag);
                                  sortWidgetController.toggleSearch();
                                }
                                sortWidgetController
                                        .textEditingController
                                        .text =
                                    query;
                                targetController.onSearch(query, tag);
                              },
                            );
                          },
                        );
                      },
                    )
                  : Center(
                      child: Text(
                        "noSavedSearches".tr,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
