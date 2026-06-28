import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../services/constant.dart';
import '../../services/downloader.dart';
import '../screens/Playlist/playlist_screen_controller.dart';
import '../screens/Settings/settings_screen_controller.dart';
import '/utils/helper.dart';
import '../../services/app_platform_service.dart';
import '/services/piped_service.dart';
import '/ui/widgets/sleep_timer_bottom_sheet.dart';
import '/ui/player/player_controller.dart';
import '../screens/Library/library_controller.dart';
import '/ui/widgets/add_to_playlist.dart';
import '/ui/widgets/snackbar.dart';
import '../../models/media_Item_builder.dart';
import '../../models/playlist.dart';
import '../navigator.dart';
import 'song_download_btn.dart';
import 'image_widget.dart';
import 'song_info_dialog.dart';

class SongInfoBottomSheet extends StatelessWidget {
  const SongInfoBottomSheet(
    this.song, {
    super.key,
    this.playlist,
    this.calledFromPlayer = false,
    this.calledFromQueue = false,
  });
  final MediaItem song;
  final Playlist? playlist;
  final bool calledFromPlayer;
  final bool calledFromQueue;

  @override
  Widget build(BuildContext context) {
    final songInfoController = Get.put(
      SongInfoController(song, calledFromPlayer),
    );
    final playerController = Get.find<PlayerController>();
    return Padding(
      padding: EdgeInsets.only(bottom: Get.mediaQuery.padding.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: const EdgeInsets.only(
                left: 15,
                top: 7,
                right: 10,
                bottom: 0,
              ),
              leading: ImageWidget(song: song, size: 50),
              title: Text(song.title, maxLines: 1),
              subtitle: Text(song.artist!),
              trailing: SizedBox(
                width: 110,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    calledFromPlayer
                        ? IconButton(
                            onPressed: () => showDialog(
                              context: context,
                              builder: (context) => SongInfoDialog(song: song),
                            ),
                            icon: Icon(
                              Icons.info,
                              color: Theme.of(
                                context,
                              ).textTheme.titleMedium!.color,
                            ),
                          )
                        : IconButton(
                            onPressed: songInfoController.toggleFav,
                            icon: Obx(
                              () => Icon(
                                songInfoController.isCurrentSongFav.isFalse
                                    ? Icons.favorite_border
                                    : Icons.favorite,
                                color: Theme.of(
                                  context,
                                ).textTheme.titleMedium!.color,
                              ),
                            ),
                          ),
                    SongDownloadButton(
                      song_: song,
                      showDebugStatus: false,
                      isDownloadingDoneCallback:
                          songInfoController.setDownloadStatus,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(),
            ListTile(
              visualDensity: const VisualDensity(vertical: -1),
              leading: const Icon(Icons.sensors),
              title: Text("startRadio".tr),
              onTap: () async {
                Navigator.of(context).pop();
                await playerController.startRadio(song);
              },
            ),
            (calledFromPlayer || calledFromQueue)
                ? const SizedBox.shrink()
                : ListTile(
                    visualDensity: const VisualDensity(vertical: -1),
                    leading: const Icon(Icons.queue_play_next),
                    title: Text("playNext".tr),
                    onTap: () {
                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.of(context).pop();
                      unawaited(
                        playerController.playNext(song).whenComplete(() {
                          final snackbarContext = Get.context;
                          if (snackbarContext == null) return;
                          messenger.showSnackBar(
                            snackbar(
                              snackbarContext,
                              "${"playNextMsg".tr} ${song.title}",
                              size: SanckBarSize.BIG,
                            ),
                          );
                        }),
                      );
                    },
                  ),
            ListTile(
              visualDensity: const VisualDensity(vertical: -1),
              leading: const Icon(Icons.add_circle_outline),
              title: Text("addToPlaylist".tr),
              onTap: () async {
                Navigator.of(context).pop();
                await showDialog(
                  context: context,
                  builder: (context) => AddToPlaylist([song]),
                ).whenComplete(() => Get.delete<AddToPlaylistController>());
              },
            ),
            (calledFromPlayer || calledFromQueue)
                ? const SizedBox.shrink()
                : ListTile(
                    visualDensity: const VisualDensity(vertical: -1),
                    leading: const Icon(Icons.merge),
                    title: Text("enqueueSong".tr),
                    onTap: () {
                      final messenger = ScaffoldMessenger.of(context);
                      unawaited(
                        playerController.enqueueSong(song).whenComplete(() {
                          final snackbarContext = Get.context;
                          if (snackbarContext == null) return;
                          messenger.showSnackBar(
                            snackbar(
                              snackbarContext,
                              "songEnqueueAlert".tr,
                              size: SanckBarSize.MEDIUM,
                            ),
                          );
                        }),
                      );
                      Navigator.of(context).pop();
                    },
                  ),
            song.extras!['album'] != null
                ? ListTile(
                    visualDensity: const VisualDensity(vertical: -1),
                    leading: const Icon(Icons.album),
                    title: Text("goToAlbum".tr),
                    onTap: () async {
                      Navigator.of(context).pop();
                      if (calledFromPlayer) {
                        await playerController.playerPanelController.close();
                      }
                      if (calledFromQueue) {
                        await playerController.playerPanelController.close();
                      }
                      await Get.toNamed(
                        ScreenNavigationSetup.albumScreen,
                        id: ScreenNavigationSetup.id,
                        arguments: (null, song.extras!['album']['id']),
                      );
                    },
                  )
                : const SizedBox.shrink(),
            ...artistWidgetList(song, context),
            (playlist != null &&
                        !playlist!.isCloudPlaylist &&
                        !(playlist!.playlistId == "LIBRP")) ||
                    (playlist != null && playlist!.isPipedPlaylist)
                ? ListTile(
                    visualDensity: const VisualDensity(vertical: -1),
                    leading: const Icon(Icons.delete),
                    title: playlist!.title == "Library Songs"
                        ? Text("removeFromLib".tr)
                        : Text("removeFromPlaylist".tr),
                    onTap: () async {
                      Navigator.of(context).pop();
                      await songInfoController
                          .removeSongFromPlaylist(song, playlist!)
                          .whenComplete(
                            () =>
                                ScaffoldMessenger.of(Get.context!).showSnackBar(
                                  snackbar(
                                    Get.context!,
                                    "Removed from ${playlist!.title}",
                                    size: SanckBarSize.MEDIUM,
                                  ),
                                ),
                          );
                    },
                  )
                : const SizedBox.shrink(),
            calledFromQueue
                ? ListTile(
                    visualDensity: const VisualDensity(vertical: -1),
                    leading: const Icon(Icons.delete),
                    title: Text("removeFromQueue".tr),
                    onTap: () {
                      Navigator.of(context).pop();
                      if (playerController.currentSong.value!.id == song.id) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          snackbar(
                            context,
                            "songRemovedFromQueueCurrSong".tr,
                            size: SanckBarSize.BIG,
                          ),
                        );
                      } else {
                        final messenger = ScaffoldMessenger.of(context);
                        unawaited(
                          playerController.removeFromQueue(song).whenComplete(
                            () {
                              final snackbarContext = Get.context;
                              if (snackbarContext == null) return;
                              messenger.showSnackBar(
                                snackbar(
                                  snackbarContext,
                                  "songRemovedFromQueue".tr,
                                  size: SanckBarSize.MEDIUM,
                                ),
                              );
                            },
                          ),
                        );
                      }
                    },
                  )
                : const SizedBox.shrink(),
            Obx(
              () =>
                  (songInfoController.isDownloaded.isTrue &&
                      (playlist?.playlistId != BoxNames.songDownloads &&
                          playlist?.playlistId != BoxNames.songsCache))
                  ? ListTile(
                      contentPadding: const EdgeInsets.only(left: 15),
                      visualDensity: const VisualDensity(vertical: -1),
                      leading: const Icon(Icons.delete),
                      title: Text("deleteDownloadData".tr),
                      onTap: () async {
                        Navigator.of(context).pop();
                        final box = Hive.box(BoxNames.songDownloads);
                        await Get.find<LibrarySongsController>()
                            .removeSong(
                              song,
                              true,
                              url: box.get(song.id)['url'],
                            )
                            .then((value) async {
                              await box.delete(song.id).then((value) {
                                if (playlist != null) {
                                  Get.find<PlaylistScreenController>(
                                    tag: Key(
                                      playlist!.playlistId,
                                    ).hashCode.toString(),
                                  ).checkDownloadStatus();
                                }
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    snackbar(
                                      context,
                                      "deleteDownloadedDataAlert".tr,
                                      size: SanckBarSize.BIG,
                                    ),
                                  );
                                }
                              });
                            });
                      },
                    )
                  : const SizedBox.shrink(),
            ),
            ListTile(
              leading: const Icon(Icons.open_with),
              title: Text("openIn".tr),
              trailing: SizedBox(
                width: 200,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      splashRadius: 10,
                      onPressed: () async {
                        await AppPlatformService.openUrl(
                          "https://youtube.com/watch?v=${song.id}",
                        );
                      },
                      icon: const Icon(Icons.smart_display),
                    ),
                    IconButton(
                      splashRadius: 10,
                      onPressed: () async {
                        await AppPlatformService.openUrl(
                          "https://music.youtube.com/watch?v=${song.id}",
                        );
                      },
                      icon: const Icon(Icons.play_circle),
                    ),
                  ],
                ),
              ),
            ),
            if (calledFromPlayer)
              ListTile(
                contentPadding: const EdgeInsets.only(left: 15),
                visualDensity: const VisualDensity(vertical: -1),
                leading: const Icon(Icons.timer),
                title: Text("sleepTimer".tr),
                onTap: () async {
                  Navigator.of(context).pop();
                  await showModalBottomSheet(
                    constraints: const BoxConstraints(maxWidth: 500),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(10.0),
                      ),
                    ),
                    isScrollControlled: true,
                    context:
                        playerController.homeScaffoldKey.currentState!.context,
                    barrierColor: Colors.transparent.withAlpha(100),
                    builder: (context) => const SleepTimerBottomSheet(),
                  );
                },
              ),
            ListTile(
              contentPadding: const EdgeInsets.only(left: 15),
              visualDensity: const VisualDensity(vertical: -1),
              leading: const Icon(Icons.share),
              title: Text("shareSong".tr),
              onTap: () => AppPlatformService.shareText(
                "https://youtube.com/watch?v=${song.id}",
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> artistWidgetList(MediaItem song, BuildContext context) {
    final artistList = [];
    final artists = song.extras!['artists'];
    if (artists != null) {
      for (dynamic each in artists) {
        if (each.containsKey("id") && each['id'] != null) artistList.add(each);
      }
    }
    return artistList.isNotEmpty
        ? artistList
              .map(
                (e) => ListTile(
                  onTap: () async {
                    Navigator.of(context).pop();
                    if (calledFromPlayer) {
                      await Get.find<PlayerController>().playerPanelController
                          .close();
                    }
                    if (calledFromQueue) {
                      final playerController = Get.find<PlayerController>();
                      await playerController.playerPanelController.close();
                    }
                    await Get.toNamed(
                      ScreenNavigationSetup.artistScreen,
                      id: ScreenNavigationSetup.id,
                      preventDuplicates: true,
                      arguments: [true, e['id']],
                    );
                  },
                  tileColor: Colors.transparent,
                  leading: const Icon(Icons.person),
                  title: Text("${"viewArtist".tr} (${e['name']})"),
                ),
              )
              .toList()
        : [const SizedBox.shrink()];
  }
}

class SongInfoController extends GetxController
    with RemoveSongFromPlaylistMixin {
  final isCurrentSongFav = false.obs;
  final MediaItem song;
  final bool calledFromPlayer;
  List artistList = [].obs;
  final isDownloaded = false.obs;
  SongInfoController(this.song, this.calledFromPlayer);
  Future<void> _setInitStatus(MediaItem song) async {
    isDownloaded.value = Hive.box(BoxNames.songDownloads).containsKey(song.id);
    isCurrentSongFav.value = (await Hive.openBox(
      BoxNames.libFav,
    )).containsKey(song.id);
    final artists = song.extras!['artists'];
    if (artists != null) {
      for (dynamic each in artists) {
        if (each.containsKey("id") && each['id'] != null) artistList.add(each);
      }
    }
  }

  @override
  Future<void> onInit() async {
    super.onInit();
    await _setInitStatus(song);
  }

  void setDownloadStatus(bool isDownloaded_) {
    if (isDownloaded_) {
      Future.delayed(
        const Duration(milliseconds: 100),
        () => isDownloaded.value = isDownloaded_,
      );
    }
  }

  Future<void> toggleFav() async {
    if (calledFromPlayer) {
      final playerController = Get.find<PlayerController>();
      if (playerController.currentSong.value == song) {
        await playerController.toggleFavourite();
        isCurrentSongFav.value = !isCurrentSongFav.value;
        return;
      }
    }
    final box = await Hive.openBox(BoxNames.libFav);
    isCurrentSongFav.isFalse
        ? await box.put(song.id, MediaItemBuilder.toJson(song))
        : await box.delete(song.id);
    try {
      final likedNotDownloadedController = Get.find<PlaylistScreenController>(
        tag: const Key(BoxNames.libFavNotDownloaded).hashCode.toString(),
      );
      if (isCurrentSongFav.isFalse &&
          !Hive.box(BoxNames.songDownloads).containsKey(song.id)) {
        await likedNotDownloadedController.addNRemoveItemsInList(
          song,
          action: 'add',
          index: 0,
        );
      } else {
        await likedNotDownloadedController.addNRemoveItemsInList(
          song,
          action: 'remove',
        );
      }
    } catch (e) {
      printERROR(e, tag: LogTags.library);
    }
    isCurrentSongFav.value = !isCurrentSongFav.value;
    if (Get.find<SettingsScreenController>()
            .autoDownloadFavoriteSongEnabled
            .isTrue &&
        isCurrentSongFav.isTrue) {
      await Get.find<Downloader>().download(song);
    }
  }
}

mixin RemoveSongFromPlaylistMixin {
  Future<void> removeSongFromPlaylist(MediaItem item, Playlist playlist) async {
    if (playlist.playlistId == BoxNames.libFavNotDownloaded) {
      final box = await Hive.openBox(BoxNames.libFav);
      await box.delete(item.id);
      try {
        await Get.find<PlaylistScreenController>(
          tag: Key(playlist.playlistId).hashCode.toString(),
        ).addNRemoveItemsInList(item, action: 'remove');
      } catch (e) {
        printERROR(e, tag: LogTags.library);
      }
      return;
    }
    if (playlist.playlistId == BoxNames.libImportDuplicates ||
        playlist.playlistId == BoxNames.libImportReview) {
      final box = await Hive.openBox(playlist.playlistId);
      await box.delete(item.id);
      await box.close();
      try {
        await Get.find<PlaylistScreenController>(
          tag: Key(playlist.playlistId).hashCode.toString(),
        ).addNRemoveItemsInList(item, action: 'remove');
      } catch (e) {
        printERROR(e, tag: LogTags.library);
      }
      return;
    }

    final box = await Hive.openBox(playlist.playlistId);
    //Library songs case
    if (playlist.playlistId == BoxNames.songsCache) {
      if (!box.containsKey(item.id)) {
        await Hive.box(BoxNames.songDownloads).delete(item.id);
        await Get.find<LibrarySongsController>().removeSong(item, true);
      } else {
        await Get.find<LibrarySongsController>().removeSong(item, false);
        await box.delete(item.id);
      }
    } else if (playlist.playlistId == BoxNames.songDownloads) {
      await box.delete(item.id);
      await Get.find<LibrarySongsController>().removeSong(item, true);
    } else if (!playlist.isPipedPlaylist) {
      //Other playlist song case
      final index = box.values.toList().indexWhere(
        (ele) => ele['videoId'] == item.id,
      );
      if (index != -1) {
        await box.deleteAt(index);
        _markAddToPlaylistMembershipRemoved(item, playlist);
      } else {
        printWarning(
          "Tried to remove missing song ${item.id} from playlist ${playlist.playlistId}",
          tag: LogTags.library,
        );
      }
    }

    // this try catch block is to handle the case when song is removed from lib-songs sections
    try {
      final playlistController = Get.find<PlaylistScreenController>(
        tag: Key(playlist.playlistId).hashCode.toString(),
      );
      if (playlist.isPipedPlaylist) {
        final res = await Get.find<PipedServices>().getPlaylistSongs(
          playlist.playlistId,
        );
        final songIndex = res.indexWhere((element) => element.id == item.id);
        if (songIndex != -1) {
          final res = await Get.find<PipedServices>().removeFromPlaylist(
            playlist.playlistId,
            songIndex,
          );
          if (res.code == 1) {
            await playlistController.addNRemoveItemsInList(
              item,
              action: 'remove',
            );
            _markAddToPlaylistMembershipRemoved(item, playlist);
          }
        }
        return;
      }

      try {
        await playlistController.addNRemoveItemsInList(item, action: 'remove');
      } catch (e) {
        printERROR(e, tag: LogTags.library);
      }
    } catch (e) {
      printERROR("Some Error in removeSongFromPlaylist (might irrelevant): $e");
    }

    if (playlist.playlistId == BoxNames.songDownloads ||
        playlist.playlistId == BoxNames.songsCache) {
      return;
    }
    await box.close();
  }

  void _markAddToPlaylistMembershipRemoved(MediaItem item, Playlist playlist) {
    if (!Get.isRegistered<AddToPlaylistController>()) return;
    Get.find<AddToPlaylistController>().markSongsRemovedFromPlaylist(
      playlist.playlistId,
      [item],
    );
  }
}
