import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/utils/get_localization.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '../../../app/providers/controller_providers.dart';
import '../../../app/providers/repository_providers.dart';
import '../../../app/providers/service_providers.dart';
import '/models/playing_from.dart';
import '/models/thumbnail.dart';
import '../../../services/app_platform_service.dart';
import '/ui/widgets/playlist_album_scroll_behaviour.dart';
import '../../../services/constant.dart';
import '../../navigator.dart';
import '../../widgets/awaitable_button.dart';
import '../../widgets/create_playlist_dialog.dart';
import '../../widgets/loader.dart';
import '../../widgets/playlist_export_dialog.dart';
import '../../widgets/snackbar.dart';
import '../../widgets/song_list_tile.dart';
import '../../widgets/song_info_bottom_sheet.dart';
import '../../widgets/sort_widget.dart';
import '../Library/library_controller.dart';
import 'playlist_screen_controller.dart';

class PlaylistScreen extends ConsumerStatefulWidget {
  const PlaylistScreen({super.key});

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen>
    with SingleTickerProviderStateMixin {
  late final String tag;
  PlaylistScreenController? _playlistController;

  @override
  void initState() {
    super.initState();
    tag = widget.key.hashCode.toString();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_playlistController != null) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final controller = PlaylistScreenController(
      musicServices: container.read(musicServiceContractProvider),
      playlistRepository: container.read(playlistRepositoryProvider),
      libraryRepository: container.read(libraryRepositoryProvider),
      homeScreenController: container.read(homeScreenControllerProvider),
      settingsScreenController: container.read(
        settingsScreenControllerProvider,
      ),
      pipedServices: container.read(pipedServicesProvider),
    );
    PlaylistScreenControllerRegistry.register(tag, controller);
    final routeArgs = ModalRoute.of(context)?.settings.arguments as List?;
    if (routeArgs == null) {
      throw StateError('PlaylistScreen requires list route arguments');
    }
    controller.initialize(args: routeArgs, vsync: this);
    _playlistController = controller;
  }

  @override
  void dispose() {
    final controller = _playlistController;
    if (controller != null) {
      PlaylistScreenControllerRegistry.unregister(tag, controller);
      controller.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playlistController = _playlistController!;
    final size = MediaQuery.of(context).size;
    final playerController = ref.read(playerControllerProvider);
    final downloader = ref.watch(downloaderProvider);
    final landscape = size.width > size.height;
    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification scrollInfo) {
          final scrollOffset = scrollInfo.metrics.pixels;

          if (landscape) {
            playlistController.scrollOffset.value = 0;
          } else {
            playlistController.scrollOffset.value = scrollOffset;
          }
          if (scrollOffset > 270 || (landscape && scrollOffset > 215)) {
            playlistController.appBarTitleVisible.value = true;
          } else {
            playlistController.appBarTitleVisible.value = false;
          }
          return true;
        },
        child: AnimatedBuilder(
          animation: Listenable.merge([playlistController, downloader]),
          builder:
              (context, _) => Stack(
                children: [
                  // The artwork depends on scrollOffset, which updates every
                  // scroll frame — give it its own listener instead of putting
                  // scrollOffset in the screen-wide merge (that would rebuild the
                  // entire Stack, song list included, per frame).
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      playlistController.scrollOffset,
                      playlistController.isSearchingOn,
                      playlistController.isContentFetched,
                    ]),
                    builder:
                        (context, _) =>
                            playlistController.isContentFetched.value
                                ? Positioned(
                                  top:
                                      landscape
                                          ? 0
                                          : -.25 *
                                              playlistController
                                                  .scrollOffset
                                                  .value,
                                  right: landscape ? 0 : null,
                                  child: Builder(
                                    builder: (context) {
                                      final opacityValue =
                                          1 -
                                          playlistController
                                                  .scrollOffset
                                                  .value /
                                              (size.width - 100);
                                      return Opacity(
                                        opacity:
                                            opacityValue < 0 ||
                                                    playlistController
                                                            .isSearchingOn
                                                            .value &&
                                                        !landscape
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
                                                  playlistController
                                                      .playlist
                                                      .value
                                                      .thumbnailUrl,
                                                ).extraHigh,
                                            fit:
                                                landscape
                                                    ? BoxFit.fitHeight
                                                    : BoxFit.cover,
                                            width:
                                                landscape ? null : size.width,
                                            height:
                                                landscape
                                                    ? size.height
                                                    : size.width,
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
                                  animation:
                                      playlistController.appBarTitleVisible,
                                  builder:
                                      (context, _) => Marquee(
                                        delay: const Duration(
                                          milliseconds: 300,
                                        ),
                                        duration: const Duration(seconds: 5),
                                        id:
                                            "${playlistController.playlist.value.title.hashCode.toString()}_appbar",
                                        child: Text(
                                          playlistController
                                                  .appBarTitleVisible
                                                  .value
                                              ? playlistController
                                                  .playlist
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
                              if (!playlistController
                                      .playlist
                                      .value
                                      .isCloudPlaylist &&
                                  playlistController.isDefaultPlaylist.value ==
                                      false)
                                SizedBox(
                                  width: 50,
                                  child: AwaitableIconButton(
                                    onPressed: () async {
                                      await showModalBottomSheet(
                                        constraints: const BoxConstraints(
                                          maxWidth: 500,
                                        ),
                                        shape: const RoundedRectangleBorder(
                                          borderRadius: BorderRadius.vertical(
                                            top: Radius.circular(10.0),
                                          ),
                                        ),
                                        context:
                                            playerController
                                                .homeScaffoldKey
                                                .currentState!
                                                .context,
                                        barrierColor: Colors.transparent
                                            .withAlpha(100),
                                        builder:
                                            (context) => SizedBox(
                                              height: 140,
                                              child: Column(
                                                children: [
                                                  ListTile(
                                                    leading: const Icon(
                                                      Icons.edit,
                                                    ),
                                                    title: Text(
                                                      "renamePlaylist".tr,
                                                    ),
                                                    onTap: () async {
                                                      Navigator.of(
                                                        context,
                                                      ).pop();
                                                      await showDialog(
                                                        context: context,
                                                        builder:
                                                            (
                                                              context,
                                                            ) => CreateNRenamePlaylistPopup(
                                                              renamePlaylist:
                                                                  true,
                                                              playlist:
                                                                  playlistController
                                                                      .playlist
                                                                      .value,
                                                            ),
                                                      );
                                                    },
                                                  ),
                                                  ListTile(
                                                    leading: const Icon(
                                                      Icons.delete,
                                                    ),
                                                    title: Text(
                                                      "removePlaylist".tr,
                                                    ),
                                                    onTap: () async {
                                                      Navigator.of(
                                                        context,
                                                      ).pop();
                                                      await playlistController
                                                          .addNRemoveFromLibrary(
                                                            playlistController
                                                                .playlist
                                                                .value,
                                                            add: false,
                                                          )
                                                          .then((value) {
                                                            ScreenNavigationSetup
                                                                .navigatorKey
                                                                .currentState
                                                                ?.pop();
                                                            if (!context
                                                                .mounted)
                                                              return;
                                                            ScaffoldMessenger.of(
                                                              context,
                                                            ).showSnackBar(
                                                              snackbar(
                                                                context,
                                                                value
                                                                    ? "playlistRemovedAlert"
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
                                                  ),
                                                ],
                                              ),
                                            ),
                                      );
                                    },
                                    icon: const Icon(Icons.more_vert),
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
                                addRepaintBoundaries: false,
                                padding: EdgeInsets.only(
                                  top:
                                      playlistController.isSearchingOn.value
                                          ? 0
                                          : landscape
                                          ? 150
                                          : 200,
                                  bottom: 200,
                                ),
                                itemCount:
                                    playlistController.songList.isEmpty ||
                                            playlistController
                                                    .isContentFetched
                                                    .value ==
                                                false
                                        ? 4
                                        : playlistController.songList.length +
                                            3,
                                itemBuilder: (_, index) {
                                  if (index == 0) {
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        left: 15.0,
                                      ),
                                      child: SizedBox(
                                        height: 40,
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: [
                                              // Bookmark button
                                              (playlistController
                                                          .playlist
                                                          .value
                                                          .isPipedPlaylist ||
                                                      !playlistController
                                                          .playlist
                                                          .value
                                                          .isCloudPlaylist)
                                                  ? const SizedBox.shrink()
                                                  : AwaitableIconButton(
                                                    tooltip:
                                                        playlistController
                                                                    .isAddedToLibrary
                                                                    .value ==
                                                                false
                                                            ? "addToLibrary".tr
                                                            : "removeFromLibrary"
                                                                .tr,
                                                    splashRadius: 10,
                                                    onPressed: () async {
                                                      final add =
                                                          playlistController
                                                              .isAddedToLibrary
                                                              .value ==
                                                          false;
                                                      await playlistController
                                                          .addNRemoveFromLibrary(
                                                            playlistController
                                                                .playlist
                                                                .value,
                                                            add: add,
                                                          )
                                                          .then((value) {
                                                            if (!context
                                                                .mounted) {
                                                              return;
                                                            }

                                                            ScaffoldMessenger.of(
                                                              context,
                                                            ).showSnackBar(
                                                              snackbar(
                                                                context,
                                                                value
                                                                    ? add
                                                                        ? "playlistBookmarkAddAlert"
                                                                            .tr
                                                                        : "listBookmarkRemoveAlert"
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
                                                      playlistController
                                                                  .isAddedToLibrary
                                                                  .value ==
                                                              false
                                                          ? Icons.bookmark_add
                                                          : Icons
                                                              .bookmark_added,
                                                    ),
                                                  ),
                                              // Play button
                                              AwaitableIconButton(
                                                tooltip: "play".tr,
                                                onPressed: () async {
                                                  await playerController
                                                      .playPlayListSong(
                                                        List<MediaItem>.from(
                                                          playlistController
                                                              .songList,
                                                        ),
                                                        0,
                                                        playFrom: PlayingFrom(
                                                          name:
                                                              playlistController
                                                                  .playlist
                                                                  .value
                                                                  .title,
                                                          type:
                                                              PlayingFromType
                                                                  .PLAYLIST,
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
                                                tooltip: "enqueueSongs".tr,
                                                onPressed: () async {
                                                  await playerController
                                                      .enqueueSongList(
                                                        playlistController
                                                            .songList
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

                                              // Shuffle button
                                              AwaitableIconButton(
                                                tooltip: "shuffle".tr,
                                                onPressed: () async {
                                                  final songsToPlay =
                                                      List<MediaItem>.from(
                                                        playlistController
                                                            .songList,
                                                      );
                                                  songsToPlay.shuffle();
                                                  await playerController
                                                      .playPlayListSong(
                                                        songsToPlay,
                                                        0,
                                                        playFrom: PlayingFrom(
                                                          name:
                                                              playlistController
                                                                  .playlist
                                                                  .value
                                                                  .title,
                                                          type:
                                                              PlayingFromType
                                                                  .PLAYLIST,
                                                        ),
                                                      );
                                                },
                                                icon: Icon(
                                                  Icons.shuffle,
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
                                                      playlistController
                                                          .playlist
                                                          .value
                                                          .playlistId;
                                                  return IconButton(
                                                    tooltip:
                                                        "downloadPlaylist".tr,
                                                    onPressed: () async {
                                                      if (playlistController
                                                          .isDownloaded
                                                          .value) {
                                                        return;
                                                      }
                                                      await downloader
                                                          .downloadPlaylist(
                                                            id,
                                                            playlistController
                                                                .songList
                                                                .toList(),
                                                          );
                                                    },
                                                    icon:
                                                        playlistController
                                                                .isDownloaded
                                                                .value
                                                            ? const Icon(
                                                              Icons
                                                                  .download_done,
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
                                                                    "${downloader.playlistDownloadingProgress.value}/${playlistController.songList.length}",
                                                                    style: Theme.of(
                                                                      context,
                                                                    ).textTheme.titleMedium!.copyWith(
                                                                      fontSize:
                                                                          10,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
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

                                              if (playlistController
                                                  .isAddedToLibrary
                                                  .value)
                                                AwaitableIconButton(
                                                  tooltip:
                                                      "syncPlaylistSongs".tr,
                                                  onPressed: () async {
                                                    await playlistController
                                                        .syncPlaylistSongs();
                                                  },
                                                  icon: const Icon(
                                                    Icons.cloud_sync,
                                                  ),
                                                ),
                                              if (playlistController
                                                  .playlist
                                                  .value
                                                  .isPipedPlaylist)
                                                AwaitableIconButton(
                                                  tooltip:
                                                      "blacklistPipedPlaylist"
                                                          .tr,
                                                  icon: const Icon(
                                                    Icons.block,
                                                    size: 20,
                                                  ),
                                                  splashRadius: 10,
                                                  onPressed: () async {
                                                    ScreenNavigationSetup
                                                        .navigatorKey
                                                        .currentState
                                                        ?.pop();
                                                    await LibraryPlaylistsControllerRegistry
                                                        .current
                                                        ?.blacklistPipedPlaylist(
                                                          playlistController
                                                              .playlist
                                                              .value,
                                                        );
                                                    if (!context.mounted)
                                                      return;
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      snackbar(
                                                        context,
                                                        "playlistBlacklistAlert"
                                                            .tr,
                                                        size:
                                                            SanckBarSize.MEDIUM,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              if (playlistController
                                                  .playlist
                                                  .value
                                                  .isCloudPlaylist)
                                                AwaitableIconButton(
                                                  tooltip: "sharePlaylist".tr,
                                                  visualDensity:
                                                      const VisualDensity(
                                                        vertical: -3,
                                                      ),
                                                  splashRadius: 10,
                                                  onPressed: () async {
                                                    final content =
                                                        playlistController
                                                            .playlist
                                                            .value;
                                                    if (content
                                                        .isPipedPlaylist) {
                                                      await AppPlatformService.shareText(
                                                        "https://piped.video/playlist?list=${content.playlistId}",
                                                      );
                                                    } else {
                                                      final isPlaylistIdPrefixAvailable =
                                                          content.playlistId
                                                              .substring(
                                                                0,
                                                                2,
                                                              ) ==
                                                          "VL";
                                                      String url =
                                                          "https://youtube.com/playlist?list=";

                                                      url =
                                                          isPlaylistIdPrefixAvailable
                                                              ? url +
                                                                  content
                                                                      .playlistId
                                                                      .substring(
                                                                        2,
                                                                      )
                                                              : url +
                                                                  content
                                                                      .playlistId;
                                                      await AppPlatformService.shareText(
                                                        url,
                                                      );
                                                    }
                                                  },
                                                  icon: const Icon(
                                                    Icons.share,
                                                    size: 20,
                                                  ),
                                                ),
                                              // Export button - opens export dialog
                                              AwaitableIconButton(
                                                onPressed: () async {
                                                  await showDialog(
                                                    context: context,
                                                    builder:
                                                        (
                                                          dialogContext,
                                                        ) => PlaylistExportDialog(
                                                          controller:
                                                              playlistController,
                                                          parentContext:
                                                              context,
                                                        ),
                                                  );
                                                },
                                                icon: const Icon(
                                                  Icons.file_upload,
                                                ),
                                                tooltip: "exportPlaylist".tr,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  } else if (index == 1) {
                                    final title =
                                        playlistController.playlist.value.title;
                                    final description =
                                        playlistController
                                            .playlist
                                            .value
                                            .description;

                                    return ClipRect(
                                      child: SizeTransition(
                                        sizeFactor:
                                            playlistController
                                                .animationController,
                                        alignment: Alignment.topCenter,
                                        child: ScaleTransition(
                                          scale:
                                              playlistController.scaleAnimation,
                                          alignment: Alignment.topLeft,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              left: 25.0,
                                              bottom: 10,
                                              right: 30,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Marquee(
                                                  delay: const Duration(
                                                    milliseconds: 300,
                                                  ),
                                                  duration: const Duration(
                                                    seconds: 5,
                                                  ),
                                                  id: title.hashCode.toString(),
                                                  child: Text(
                                                    title.length > 50
                                                        ? title.substring(0, 50)
                                                        : title,
                                                    maxLines: 1,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleLarge!
                                                        .copyWith(fontSize: 30),
                                                  ),
                                                ),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 8.0,
                                                      ),
                                                  child: Marquee(
                                                    delay: const Duration(
                                                      milliseconds: 300,
                                                    ),
                                                    duration: const Duration(
                                                      seconds: 5,
                                                    ),
                                                    id:
                                                        description.hashCode
                                                            .toString(),
                                                    child: Text(
                                                      description ??
                                                          "playlist".tr,
                                                      maxLines: 1,
                                                      style:
                                                          Theme.of(context)
                                                              .textTheme
                                                              .titleSmall,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  } else if (index == 2) {
                                    return SizedBox(
                                      height:
                                          playlistController.isSearchingOn.value
                                              ? 60
                                              : 40,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          left: 15.0,
                                          right: 10,
                                        ),
                                        child: SortWidget(
                                          tag:
                                              playlistController
                                                  .playlist
                                                  .value
                                                  .playlistId,
                                          screenController: playlistController,
                                          isSearchFeatureRequired: true,
                                          isPlaylistRearrangeFeatureRequired:
                                              !playlistController
                                                  .playlist
                                                  .value
                                                  .isCloudPlaylist &&
                                              playlistController
                                                      .playlist
                                                      .value
                                                      .playlistId !=
                                                  BoxNames.libRP &&
                                              playlistController
                                                      .playlist
                                                      .value
                                                      .playlistId !=
                                                  BoxNames.songDownloads &&
                                              playlistController
                                                      .playlist
                                                      .value
                                                      .playlistId !=
                                                  BoxNames.songsCache,
                                          isSongDeletionFeatureRequired:
                                              !playlistController
                                                  .playlist
                                                  .value
                                                  .isCloudPlaylist,
                                          itemCountTitle:
                                              "${playlistController.songList.length}",
                                          itemIcon: Icons.music_note,
                                          titleLeftPadding: 9,
                                          requiredSortTypes: buildSortTypeSet(
                                            false,
                                            true,
                                          ),
                                          onSort: playlistController.onSort,
                                          onSearch: playlistController.onSearch,
                                          onSearchClose:
                                              playlistController.onSearchClose,
                                          onSearchStart:
                                              playlistController.onSearchStart,
                                          startAdditionalOperation:
                                              playlistController
                                                  .startAdditionalOperation,
                                          selectAll:
                                              playlistController.selectAll,
                                          performAdditionalOperation:
                                              playlistController
                                                  .performAdditionalOperation,
                                          cancelAdditionalOperation:
                                              playlistController
                                                  .cancelAdditionalOperation,
                                        ),
                                      ),
                                    );
                                  } else if (playlistController
                                              .isContentFetched
                                              .value ==
                                          false ||
                                      playlistController.songList.isEmpty) {
                                    return SizedBox(
                                      height: 300,
                                      child: Center(
                                        child:
                                            playlistController
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
                                            playlistController.songList,
                                          ),
                                          index - 3,
                                          playFrom: PlayingFrom(
                                            name:
                                                playlistController
                                                    .playlist
                                                    .value
                                                    .title,
                                            type: PlayingFromType.PLAYLIST,
                                          ),
                                        );
                                      },
                                      song:
                                          playlistController.songList[index -
                                              3],
                                      isPlaylistOrAlbum: true,
                                      playlist:
                                          playlistController.playlist.value,
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
