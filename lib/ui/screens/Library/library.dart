import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/utils/get_localization.dart';

import '../../../app/providers/controller_providers.dart';
import '../../../app/providers/repository_providers.dart';
import '/ui/widgets/modification_list.dart';
import '../../../models/playlist.dart';
import '../../widgets/piped_sync_widget.dart';
import 'library_controller.dart';
import 'library_combined.dart';
import '../../widgets/content_list_widget_item.dart';
import '../../widgets/list_widget.dart';
import '../../widgets/sort_widget.dart';

class SongsLibraryWidget extends ConsumerWidget {
  const SongsLibraryWidget({super.key, this.isBottomNavActive = false});
  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libSongsController = ref.watch(librarySongsControllerProvider);
    LibrarySongsControllerRegistry.register(libSongsController);
    final topPadding =
        MediaQuery.orientationOf(context) == Orientation.landscape ? 50.0 : 90.0;
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
          AnimatedBuilder(
            animation: libSongsController,
            builder: (context, _) => SortWidget(
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
              onMounted: libSongsController.clearStaleSearch,
              startAdditionalOperation:
                  libSongsController.startAdditionalOperation,
              selectAll: libSongsController.selectAll,
              performAdditionalOperation:
                  libSongsController.performAdditionalOperation,
              cancelAdditionalOperation:
                  libSongsController.cancelAdditionalOperation,
            ),
          ),
          AnimatedBuilder(
            animation: libSongsController,
            builder: (context, _) {
              return libSongsController.librarySongsList.isNotEmpty
                  ? (libSongsController.additionalOperationMode ==
                            OperationMode.none
                        ? ListWidget(
                            libSongsController.librarySongsList,
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
                            mode: libSongsController.additionalOperationMode,
                            screenController: libSongsController,
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

class PlaylistNAlbumLibraryWidget extends ConsumerWidget {
  const PlaylistNAlbumLibraryWidget({
    super.key,
    this.isAlbumContent = true,
    this.isBottomNavActive = false,
  });
  final bool isAlbumContent;
  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryAlbumController = ref.watch(libraryAlbumsControllerProvider);
    final libraryPlaylistController = ref.watch(
      libraryPlaylistsControllerProvider,
    );
    final settingsScreenController = ref.watch(
      settingsScreenControllerProvider,
    );
    LibraryAlbumsControllerRegistry.register(libraryAlbumController);
    final size = MediaQuery.of(context).size;

    const double itemHeight = 180;
    const double itemWidth = 130;
    final topPadding =
        MediaQuery.orientationOf(context) == Orientation.landscape ? 50.0 : 90.0;

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
                (settingsScreenController.isBottomNavBarEnabled.value ||
                        isAlbumContent ||
                        !settingsScreenController.isLinkedWithPiped.value)
                    ? const SizedBox.shrink()
                    : PipedSyncWidget(
                        padding: EdgeInsets.only(right: size.width * .05),
                      ),
              ],
            ),
          ),
          isAlbumContent
              ? AnimatedBuilder(
                  animation: libraryAlbumController,
                  builder: (context, _) => SortWidget(
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
                    onMounted: libraryAlbumController.clearStaleSearch,
                  ),
                )
              : AnimatedBuilder(
                  animation: libraryPlaylistController,
                  builder: (context, _) => SortWidget(
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
                    onMounted: libraryPlaylistController.clearStaleSearch,
                    isImportFeatureRequired: true,
                  ),
                ),
          Expanded(
            child: isAlbumContent
                ? AnimatedBuilder(
                    animation: libraryAlbumController,
                    builder: (context, _) => _LibraryContentGrid(
                      itemHeight: itemHeight,
                      itemWidth: itemWidth,
                      items: libraryAlbumController.libraryAlbums,
                    ),
                  )
                : AnimatedBuilder(
                    animation: libraryPlaylistController,
                    builder: (context, _) => _LibraryContentGrid(
                      itemHeight: itemHeight,
                      itemWidth: itemWidth,
                      items: libraryPlaylistController.libraryPlaylists,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LibraryContentGrid extends StatelessWidget {
  const _LibraryContentGrid({
    required this.itemHeight,
    required this.itemWidth,
    required this.items,
  });

  final double itemHeight;
  final double itemWidth;
  final List<dynamic> items;

  @override
  Widget build(BuildContext context) {
    return items.isNotEmpty
        ? LayoutBuilder(
            builder: (context, constraints) {
              //Fix for grid in mobile screen
              final availableWidth =
                  constraints.maxWidth > 300 && constraints.maxWidth < 394
                  ? 310.0
                  : constraints.maxWidth;
              int columns = (availableWidth / itemWidth).floor();
              return SizedBox(
                width: availableWidth,
                child: GridView.builder(
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    childAspectRatio: itemWidth / itemHeight,
                  ),
                  controller: ScrollController(keepScrollOffset: false),
                  shrinkWrap: true,
                  scrollDirection: Axis.vertical,
                  padding: const EdgeInsets.only(bottom: 200, top: 10),
                  itemCount: items.length,
                  itemBuilder: (context, index) => Center(
                    child: ContentListItem(
                      content: items[index],
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
          );
  }
}

class LibraryArtistWidget extends ConsumerWidget {
  const LibraryArtistWidget({super.key, this.isBottomNavActive = false});
  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryArtistsController = ref.watch(
      libraryArtistsControllerProvider,
    );
    LibraryArtistsControllerRegistry.register(libraryArtistsController);
    final topPadding =
        MediaQuery.orientationOf(context) == Orientation.landscape ? 50.0 : 90.0;
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
          AnimatedBuilder(
            animation: libraryArtistsController,
            builder: (context, _) => SortWidget(
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
              onMounted: libraryArtistsController.clearStaleSearch,
            ),
          ),
          AnimatedBuilder(
            animation: libraryArtistsController,
            builder: (context, _) =>
                libraryArtistsController.libraryArtists.isNotEmpty
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

class LibrarySearchWidget extends ConsumerStatefulWidget {
  const LibrarySearchWidget({super.key, this.isBottomNavActive = false});
  final bool isBottomNavActive;

  @override
  ConsumerState<LibrarySearchWidget> createState() =>
      _LibrarySearchWidgetState();
}

class _LibrarySearchWidgetState extends ConsumerState<LibrarySearchWidget> {
  late final LibrarySearchesController controller;

  @override
  void initState() {
    super.initState();
    controller = LibrarySearchesController(
      libraryRepository: ref.read(libraryRepositoryProvider),
    );
    unawaited(controller.init());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding =
        MediaQuery.orientationOf(context) == Orientation.landscape ? 50.0 : 90.0;
    return Padding(
      padding: widget.isBottomNavActive
          ? const EdgeInsets.only(left: 15)
          : EdgeInsets.only(left: 5, top: topPadding),
      child: Column(
        children: [
          widget.isBottomNavActive
              ? const SizedBox(height: 10)
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "searches".tr,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
          Expanded(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => controller.savedSearches.isNotEmpty
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
                            // All saved searches apply to the Songs tab
                            int targetTab = 0;

                            final tabController =
                                CombinedLibraryTabControllerScope.maybeOf(
                                  context,
                                );
                            if (tabController != null) {
                              tabController.animateTo(targetTab);
                            }

                            // Apply search to the Songs controller
                            Future.delayed(
                              const Duration(milliseconds: 300),
                              () {
                                const tag =
                                    LibrarySongsController.sortWidgetTag;
                                final targetController =
                                    LibrarySongsControllerRegistry.current;
                                final sortWidgetController =
                                    SortWidgetRegistry.maybeOf(tag);
                                if (sortWidgetController == null ||
                                    targetController == null) {
                                  return;
                                }
                                if (!sortWidgetController.isSearchingEnabled) {
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
