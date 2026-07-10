import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/utils/get_localization.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/playing_from.dart';
import 'package:harmonymusic/models/thumbnail.dart';
import 'package:harmonymusic/services/app_platform_service.dart';
import 'package:harmonymusic/ui/widgets/playlist_album_scroll_behaviour.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '../../../app/providers/controller_providers.dart';
import '../../../app/providers/repository_providers.dart';
import '../../../app/providers/service_providers.dart';
import '../../../utils/runtime_platform.dart';
import '../../widgets/awaitable_button.dart';
import '../../widgets/loader.dart';
import '../../widgets/snackbar.dart';
import '../../widgets/song_list_tile.dart';
import '../../widgets/song_info_bottom_sheet.dart';
import '../../widgets/sort_widget.dart';
import 'album_screen_controller.dart';

class AlbumScreen extends ConsumerStatefulWidget {
  const AlbumScreen({super.key});

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen>
    with SingleTickerProviderStateMixin {
  late final String tag;
  AlbumScreenController? _albumController;

  @override
  void initState() {
    super.initState();
    tag = widget.key.hashCode.toString();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_albumController != null) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final controller = AlbumScreenController(
      musicServices: container.read(musicServiceContractProvider),
      playlistRepository: container.read(playlistRepositoryProvider),
      libraryRepository: container.read(libraryRepositoryProvider),
      homeScreenController: container.read(homeScreenControllerProvider),
    );
    AlbumScreenControllerRegistry.register(tag, controller);
    final routeArgs =
        ModalRoute.of(context)?.settings.arguments as (Album?, String)?;
    if (routeArgs == null) {
      throw StateError('AlbumScreen requires (Album?, String) route arguments');
    }
    controller.initialize(args: routeArgs, vsync: this);
    _albumController = controller;
  }

  @override
  void dispose() {
    final controller = _albumController;
    if (controller != null) {
      AlbumScreenControllerRegistry.unregister(tag, controller);
      controller.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final albumController = _albumController!;
    final size = MediaQuery.of(context).size;
    final playerController = ref.read(playerControllerProvider);
    final downloader = ref.watch(downloaderProvider);
    final landscape = size.width > size.height;
    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification scrollInfo) {
          final scrollOffset = scrollInfo.metrics.pixels;

          if (landscape) {
            albumController.scrollOffset.value = 0;
          } else {
            albumController.scrollOffset.value = scrollOffset;
          }
          if (scrollOffset > 270 || (landscape && scrollOffset > 225)) {
            albumController.appBarTitleVisible.value = true;
          } else {
            albumController.appBarTitleVisible.value = false;
          }
          return true;
        },
        child: AnimatedBuilder(
          animation: Listenable.merge([albumController, downloader]),
          builder:
              (context, _) => Stack(
                children: [
                  // The artwork depends on scrollOffset, which updates every
                  // scroll frame — give it its own listener instead of putting
                  // scrollOffset in the screen-wide merge (that would rebuild the
                  // entire Stack, song list included, per frame).
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      albumController.scrollOffset,
                      albumController.isSearchingOn,
                      albumController.isContentFetched,
                    ]),
                    builder:
                        (context, _) =>
                            albumController.isContentFetched.value
                                ? Positioned(
                                  top:
                                      landscape
                                          ? 0
                                          : -.25 *
                                              albumController
                                                  .scrollOffset
                                                  .value,
                                  right: landscape ? 0 : null,
                                  child: Builder(
                                    builder: (context) {
                                      final opacityValue =
                                          1 -
                                          albumController.scrollOffset.value /
                                              (size.width - 100);
                                      return Opacity(
                                        opacity:
                                            opacityValue < 0 ||
                                                    albumController
                                                        .isSearchingOn
                                                        .value
                                                ? 0
                                                : opacityValue,
                                        child: DecoratedBox(
                                          position:
                                              DecorationPosition.foreground,
                                          decoration: BoxDecoration(
                                            boxShadow: [
                                              BoxShadow(
                                                color:
                                                    Theme.of(
                                                      context,
                                                    ).canvasColor,
                                                spreadRadius: 200,
                                                blurRadius: 100,
                                                offset: Offset(-size.height, 0),
                                              ),
                                              BoxShadow(
                                                color:
                                                    Theme.of(
                                                      context,
                                                    ).canvasColor,
                                                spreadRadius: 200,
                                                blurRadius: 100,
                                                offset: Offset(
                                                  0,
                                                  landscape
                                                      ? size.height
                                                      : size.width + 80,
                                                ),
                                              ),
                                            ],
                                          ),
                                          child: CachedNetworkImage(
                                            imageUrl:
                                                Thumbnail(
                                                  albumController
                                                      .album
                                                      .value
                                                      .thumbnailUrl,
                                                ).extraHigh,
                                            fit:
                                                landscape
                                                    ? BoxFit.fitHeight
                                                    : BoxFit.fitWidth,
                                            width:
                                                landscape ? null : size.width,
                                            height:
                                                landscape ? size.height : null,
                                            // placeholder: (context, n) => Align(
                                            //   alignment:landscape?Alignment.centerLeft: Alignment.topCenter,
                                            //   child: SizedBox(
                                            //     width: landscape ? size.height : size.width,
                                            //     height: landscape ? size.height : size.width,
                                            //     child: Center(
                                            //       child: Icon(Icons.album,
                                            //           size: 150,
                                            //           color: Theme.of(context)
                                            //               .textTheme.titleSmall!.color
                                            //         ),
                                            //     ),
                                            //   ),
                                            // ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                )
                                : SizedBox(
                                  height: size.width,
                                  width: size.width,
                                ),
                  ),
                  Column(
                    children: [
                      Container(
                        padding: EdgeInsets.only(
                          top: MediaQuery.of(context).padding.top + 10,
                          left: 10,
                          right: 10,
                        ),
                        height: 80,
                        child: Center(
                          child: Row(
                            children: [
                              SizedBox(
                                width: 50,
                                child: IconButton(
                                  tooltip: "back".tr,
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                  },
                                  icon: const Icon(Icons.arrow_back_ios),
                                ),
                              ),
                              Expanded(
                                // appBarTitleVisible is written from the scroll
                                // listener; it needs its own listener to rebuild.
                                child: AnimatedBuilder(
                                  animation: albumController.appBarTitleVisible,
                                  builder:
                                      (context, _) => Marquee(
                                        delay: const Duration(
                                          milliseconds: 300,
                                        ),
                                        duration: const Duration(seconds: 5),
                                        id:
                                            "${albumController.album.value.title.hashCode.toString()}_appbar",
                                        child: Text(
                                          albumController
                                                  .appBarTitleVisible
                                                  .value
                                              ? albumController
                                                  .album
                                                  .value
                                                  .title
                                              : "",
                                          maxLines: 1,
                                          style:
                                              Theme.of(
                                                context,
                                              ).textTheme.titleLarge,
                                        ),
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 800),
                            child: ScrollConfiguration(
                              behavior: PlaylistAlbumScrollBehaviour(),
                              child: ListView.builder(
                                padding: EdgeInsets.only(
                                  top:
                                      albumController.isSearchingOn.value
                                          ? 0
                                          : landscape
                                          ? 150
                                          : 200,
                                  bottom: 200,
                                ),
                                itemCount:
                                    albumController.songList.isEmpty
                                        ? 4
                                        : albumController.songList.length + 3,
                                itemBuilder: (_, index) {
                                  if (index == 0) {
                                    return Padding(
                                      padding: EdgeInsets.only(
                                        left:
                                            RuntimePlatform.isDesktop
                                                ? 15.0
                                                : 10.0,
                                      ),
                                      child: SizedBox(
                                        height: 40,
                                        child: Row(
                                          children: [
                                            // Bookmark button
                                            AwaitableIconButton(
                                              tooltip:
                                                  albumController
                                                              .isAddedToLibrary
                                                              .value ==
                                                          false
                                                      ? "addToLibrary".tr
                                                      : "removeFromLibrary".tr,
                                              splashRadius: 10,
                                              onPressed: () async {
                                                final add =
                                                    albumController
                                                        .isAddedToLibrary
                                                        .value ==
                                                    false;
                                                await albumController
                                                    .addNRemoveFromLibrary(
                                                      albumController
                                                          .album
                                                          .value,
                                                      add: add,
                                                    )
                                                    .then((value) {
                                                      if (!context.mounted) {
                                                        return;
                                                      }

                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        snackbar(
                                                          context,
                                                          value
                                                              ? add
                                                                  ? "albumBookmarkAddAlert"
                                                                      .tr
                                                                  : "albumBookmarkRemoveAlert"
                                                                      .tr
                                                              : "operationFailed"
                                                                  .tr,
                                                          size:
                                                              SanckBarSize
                                                                  .MEDIUM,
                                                        ),
                                                      );
                                                    });
                                              },
                                              icon: Icon(
                                                albumController
                                                            .isAddedToLibrary
                                                            .value ==
                                                        false
                                                    ? Icons.bookmark_add
                                                    : Icons.bookmark_added,
                                              ),
                                            ),
                                            // Play button
                                            AwaitableIconButton(
                                              tooltip: "play".tr,
                                              onPressed: () async {
                                                await playerController
                                                    .playPlayListSong(
                                                      List<MediaItem>.from(
                                                        albumController
                                                            .songList,
                                                      ),
                                                      0,
                                                      playFrom: PlayingFrom(
                                                        name:
                                                            albumController
                                                                .album
                                                                .value
                                                                .title,
                                                        type:
                                                            PlayingFromType
                                                                .ALBUM,
                                                      ),
                                                    );
                                              },
                                              icon: Icon(
                                                Icons.play_circle,
                                                color:
                                                    Theme.of(context)
                                                        .textTheme
                                                        .titleMedium!
                                                        .color,
                                              ),
                                            ),
                                            // Enqueue button
                                            AwaitableIconButton(
                                              tooltip: "enqueueAlbumSongs".tr,
                                              onPressed: () async {
                                                await playerController
                                                    .enqueueSongList(
                                                      albumController.songList
                                                          .toList(),
                                                    )
                                                    .whenComplete(() {
                                                      if (context.mounted) {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          snackbar(
                                                            context,
                                                            "songEnqueueAlert"
                                                                .tr,
                                                            size:
                                                                SanckBarSize
                                                                    .MEDIUM,
                                                          ),
                                                        );
                                                      }
                                                    });
                                              },
                                              icon: Icon(
                                                Icons.merge,
                                                color:
                                                    Theme.of(context)
                                                        .textTheme
                                                        .titleMedium!
                                                        .color,
                                              ),
                                            ),

                                            // Download button
                                            Builder(
                                              builder: (context) {
                                                final id =
                                                    albumController
                                                        .album
                                                        .value
                                                        .browseId;
                                                return IconButton(
                                                  tooltip:
                                                      "downloadAlbumSongs".tr,
                                                  onPressed: () async {
                                                    if (albumController
                                                        .isDownloaded
                                                        .value) {
                                                      return;
                                                    }
                                                    await downloader
                                                        .downloadPlaylist(
                                                          id,
                                                          albumController
                                                              .songList
                                                              .toList(),
                                                        );
                                                  },
                                                  icon:
                                                      albumController
                                                              .isDownloaded
                                                              .value
                                                          ? const Icon(
                                                            Icons.download_done,
                                                          )
                                                          : downloader
                                                                  .playlistQueue
                                                                  .containsKey(
                                                                    id,
                                                                  ) &&
                                                              downloader
                                                                      .currentPlaylistId
                                                                      .value ==
                                                                  id
                                                          ? Stack(
                                                            children: [
                                                              Center(
                                                                child: Text(
                                                                  "${downloader.playlistDownloadingProgress.value}/${albumController.songList.length}",
                                                                  style: Theme.of(
                                                                        context,
                                                                      )
                                                                      .textTheme
                                                                      .titleMedium!
                                                                      .copyWith(
                                                                        fontSize:
                                                                            10,
                                                                        fontWeight:
                                                                            FontWeight.bold,
                                                                      ),
                                                                ),
                                                              ),
                                                              const Center(
                                                                child:
                                                                    LoadingIndicator(
                                                                      dimension:
                                                                          30,
                                                                    ),
                                                              ),
                                                            ],
                                                          )
                                                          : downloader
                                                              .playlistQueue
                                                              .containsKey(id)
                                                          ? const Stack(
                                                            children: [
                                                              Center(
                                                                child: Icon(
                                                                  Icons
                                                                      .hourglass_bottom,
                                                                  size: 20,
                                                                ),
                                                              ),
                                                              Center(
                                                                child:
                                                                    LoadingIndicator(
                                                                      dimension:
                                                                          30,
                                                                    ),
                                                              ),
                                                            ],
                                                          )
                                                          : const Icon(
                                                            Icons.download,
                                                          ),
                                                );
                                              },
                                            ),

                                            // if album is added to library
                                            //   IconButton(
                                            //       onPressed: () {
                                            //         albumController
                                            //             .syncPlaylistSongs();
                                            //       },
                                            //       icon: const Icon(
                                            //           Icons.cloud_sync)),
                                            AwaitableIconButton(
                                              tooltip: "shareAlbum".tr,
                                              visualDensity:
                                                  const VisualDensity(
                                                    vertical: -3,
                                                  ),
                                              splashRadius: 10,
                                              onPressed: () async {
                                                await AppPlatformService.shareText(
                                                  "https://youtube.com/playlist?list=${albumController.album.value.audioPlaylistId}",
                                                );
                                              },
                                              icon: const Icon(
                                                Icons.share,
                                                size: 20,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  } else if (index == 1) {
                                    return buildTitleSubTitle(
                                      context,
                                      albumController,
                                    );
                                  } else if (index == 2) {
                                    return SizedBox(
                                      height:
                                          albumController.isSearchingOn.value
                                              ? 60
                                              : 40,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          left: 15.0,
                                          right: 10,
                                        ),
                                        child: SortWidget(
                                          tag:
                                              albumController
                                                  .album
                                                  .value
                                                  .browseId,
                                          screenController: albumController,
                                          isSearchFeatureRequired: true,
                                          itemCountTitle:
                                              "${albumController.songList.length}",
                                          itemIcon: Icons.music_note,
                                          titleLeftPadding: 9,
                                          requiredSortTypes: buildSortTypeSet(
                                            false,
                                            true,
                                          ),
                                          onSort: albumController.onSort,
                                          onSearch: albumController.onSearch,
                                          onSearchClose:
                                              albumController.onSearchClose,
                                          onSearchStart:
                                              albumController.onSearchStart,
                                          startAdditionalOperation:
                                              albumController
                                                  .startAdditionalOperation,
                                          selectAll: albumController.selectAll,
                                          performAdditionalOperation:
                                              albumController
                                                  .performAdditionalOperation,
                                          cancelAdditionalOperation:
                                              albumController
                                                  .cancelAdditionalOperation,
                                        ),
                                      ),
                                    );
                                  } else if (albumController
                                              .isContentFetched
                                              .value ==
                                          false ||
                                      albumController.songList.isEmpty) {
                                    return SizedBox(
                                      height: 300,
                                      child: Center(
                                        child:
                                            albumController
                                                        .isContentFetched
                                                        .value ==
                                                    false
                                                ? const LoadingIndicator()
                                                : Text(
                                                  "emptyPlaylist".tr,
                                                  style:
                                                      Theme.of(
                                                        context,
                                                      ).textTheme.titleSmall,
                                                ),
                                      ),
                                    );
                                  }

                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      left: 20.0,
                                      right: 5,
                                    ),
                                    child: SongListTile(
                                      onTap: () async {
                                        await playerController.playPlayListSong(
                                          List<MediaItem>.from(
                                            albumController.songList,
                                          ),
                                          index - 3,
                                          playFrom: PlayingFrom(
                                            name:
                                                albumController
                                                    .album
                                                    .value
                                                    .title,
                                            type: PlayingFromType.ALBUM,
                                          ),
                                        );
                                      },
                                      song: albumController.songList[index - 3],
                                      isPlaylistOrAlbum: true,
                                      thumbReplacementWithIndex: true,
                                      index: index - 2,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
        ),
      ),
    );
  }

  Widget buildTitleSubTitle(
    BuildContext context,
    AlbumScreenController albumController,
  ) {
    final title = albumController.album.value.title;
    final description = albumController.album.value.description;
    final artists =
        albumController.album.value.artists?.map((e) => e['name']).join(", ") ??
        "";
    return ClipRect(
      child: SizeTransition(
        sizeFactor: albumController.animationController,
        alignment: Alignment.topCenter,
        child: ScaleTransition(
          scale: albumController.scaleAnimation,
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 25.0, bottom: 10, right: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Marquee(
                  delay: const Duration(milliseconds: 300),
                  duration: const Duration(seconds: 5),
                  id: title.hashCode.toString(),
                  child: Text(
                    title.length > 50 ? title.substring(0, 50) : title,
                    maxLines: 1,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge!.copyWith(fontSize: 30),
                  ),
                ),
                Text(
                  description ?? "",
                  maxLines: 1,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Marquee(
                    delay: const Duration(milliseconds: 300),
                    duration: const Duration(seconds: 5),
                    id: artists.hashCode.toString(),
                    child: Text(
                      artists,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future openBottomSheet(BuildContext context, MediaItem song) {
    return showModalBottomSheet(
      constraints: const BoxConstraints(maxWidth: 500),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10.0)),
      ),
      isScrollControlled: true,
      context: context,
      barrierColor: Colors.transparent.withAlpha(100),
      builder: (context) => SongInfoBottomSheet(song),
    );
  }
}
