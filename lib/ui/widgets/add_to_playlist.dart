import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '../../services/piped_service.dart';
import '../../utils/helper.dart';
import '/models/media_Item_builder.dart';
import '/ui/widgets/create_playlist_dialog.dart';
import '../../models/playlist.dart';
import 'common_dialog_widget.dart';
import 'snackbar.dart';

enum PlaylistAddStatus { added, skipped, failed }

class AddToPlaylist extends StatelessWidget {
  const AddToPlaylist(this.songItems, {super.key});
  final List<MediaItem> songItems;

  @override
  Widget build(BuildContext context) {
    final addToPlaylistController = Get.put(AddToPlaylistController());
    final isPipedLinked = Get.find<PipedServices>().isLoggedIn;
    return CommonDialog(
      child: Container(
        height: isPipedLinked ? 400 : 350,
        padding: const EdgeInsets.only(
          top: 20,
          bottom: 30,
          left: 20,
          right: 20,
        ),
        child: Stack(
          children: [
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.only(bottom: 10.0, top: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Marquee(
                            id: "createNewPlaylistx",
                            delay: const Duration(milliseconds: 300),
                            child: Text(
                              "CreateNewPlaylist".tr,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        tooltip: "CreateNewPlaylist".tr,
                        icon: const Icon(Icons.playlist_add),
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await showDialog(
                            context: context,
                            builder: (context) => CreateNRenamePlaylistPopup(
                              isCreateNAdd: true,
                              songItems: songItems,
                            ),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: "close".tr,
                        icon: const Icon(Icons.done),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                if (isPipedLinked)
                  Obx(
                    () => RadioGroup<String>(
                      groupValue: addToPlaylistController.playlistType.value,
                      onChanged: (value) {
                        if (value == null) return;
                        unawaited(
                          addToPlaylistController.changePlaylistType(value),
                        );
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Radio<String>(value: 'piped'),
                              Text('Piped'.tr),
                            ],
                          ),
                          const SizedBox(width: 15),
                          Row(
                            children: [
                              const Radio<String>(value: 'local'),
                              Text('local'.tr),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColorLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    //color: Colors.green,
                    child: Obx(
                      () => addToPlaylistController.playlists.isNotEmpty
                          ? ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount:
                                  addToPlaylistController.playlists.length,
                              itemBuilder: (context, index) {
                                final playlist =
                                    addToPlaylistController.playlists[index];
                                return Obx(() {
                                  if (addToPlaylistController
                                              .playlistType
                                              .value ==
                                          "piped" &&
                                      !addToPlaylistController
                                          .isPlaylistMembershipLoaded(
                                            playlist.playlistId,
                                          )) {
                                    unawaited(
                                      addToPlaylistController
                                          .ensurePlaylistMembershipLoaded(
                                            playlist.playlistId,
                                          ),
                                    );
                                  }
                                  final isMembershipLoading =
                                      addToPlaylistController
                                          .isPlaylistMembershipLoading(
                                            playlist.playlistId,
                                          );
                                  final isDisabled = addToPlaylistController
                                      .isPlaylistDisabled(
                                        playlist.playlistId,
                                        songItems,
                                      );
                                  final isAdding = addToPlaylistController
                                      .isPlaylistAdding(playlist.playlistId);
                                  return Opacity(
                                    opacity: isDisabled ? 0.55 : 1,
                                    child: ListTile(
                                      enabled:
                                          !isDisabled &&
                                          !isAdding &&
                                          !isMembershipLoading,
                                      leading: isAdding || isMembershipLoading
                                          ? const SizedBox.square(
                                              dimension: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Icon(
                                              isDisabled
                                                  ? Icons.check_circle
                                                  : Icons.add_circle_outline,
                                            ),
                                      title: Text(playlist.title),
                                      onTap:
                                          isDisabled ||
                                              isAdding ||
                                              isMembershipLoading
                                          ? null
                                          : () async {
                                              final result =
                                                  await addToPlaylistController
                                                      .addSongsToPlaylist(
                                                        songItems,
                                                        playlist.playlistId,
                                                      );
                                              if (!context.mounted) return;
                                              final message =
                                                  result ==
                                                      PlaylistAddStatus.added
                                                  ? "songAddedToPlaylistAlert"
                                                        .tr
                                                  : result ==
                                                        PlaylistAddStatus
                                                            .skipped
                                                  ? "songAlreadyExists".tr
                                                  : "errorOccurredAlert".tr;
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                snackbar(
                                                  context,
                                                  message,
                                                  size: SanckBarSize.MEDIUM,
                                                ),
                                              );
                                            },
                                    ),
                                  );
                                });
                              },
                            )
                          : Center(child: Text("noLibPlaylist".tr)),
                    ),
                  ),
                ),
              ],
            ),
            Obx(
              () =>
                  (addToPlaylistController.additionInProgress.isTrue &&
                      isPipedLinked)
                  ? const Positioned(
                      top: 60,
                      right: 8,
                      child: SizedBox(
                        height: 15,
                        width: 15,
                        child: CircularProgressIndicator(
                          backgroundColor: Colors.transparent,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class AddToPlaylistController extends GetxController {
  final RxList<Playlist> playlists = RxList();
  final playlistType = "local".obs;
  final additionInProgress = false.obs;
  final playlistSongIds = <String, Set<String>>{}.obs;
  final addingPlaylistIds = <String>{}.obs;
  final loadingMembershipPlaylistIds = <String>{}.obs;
  List<Playlist> localPlaylists = [];
  List<Playlist> pipedPlaylists = [];
  AddToPlaylistController();
  @override
  Future<void> onInit() async {
    super.onInit();
    await _getAllPlaylist();
  }

  Future<void> _getAllPlaylist() async {
    final playlistsBox = await Hive.openBox("LibraryPlaylists");
    playlists.value = playlistsBox.values
        .map((e) {
          if (!e["isCloudPlaylist"]) return Playlist.fromJson(e);
        })
        .whereType<Playlist>()
        .toList();
    localPlaylists = playlists.toList();
    await _loadLocalPlaylistMembership(localPlaylists);
    final res = await Get.find<PipedServices>().getAllPlaylists();
    if (res.code == 1) {
      pipedPlaylists = res.response
          .map(
            (item) => Playlist(
              title: item['name'],
              playlistId: item['id'],
              description: "Piped Playlist",
              thumbnailUrl: item['thumbnail'],
              isPipedPlaylist: true,
            ),
          )
          .whereType<Playlist>()
          .toList();
    }
  }

  Future<void> changePlaylistType(String val) async {
    playlistType.value = val;
    playlists.value = val == "piped" ? pipedPlaylists : localPlaylists;
  }

  bool isPlaylistAdding(String playlistId) {
    return addingPlaylistIds.contains(playlistId);
  }

  bool isPlaylistMembershipLoading(String playlistId) {
    return loadingMembershipPlaylistIds.contains(playlistId);
  }

  bool isPlaylistMembershipLoaded(String playlistId) {
    return playlistSongIds.containsKey(playlistId);
  }

  bool isPlaylistDisabled(String playlistId, List<MediaItem> songs) {
    return missingSongsForPlaylist(songs, playlistId).isEmpty;
  }

  List<MediaItem> missingSongsForPlaylist(
    List<MediaItem> songs,
    String playlistId,
  ) {
    final existingIds = playlistSongIds[playlistId] ?? <String>{};
    return songs.where((song) => !existingIds.contains(song.id)).toList();
  }

  void updatePlaylistMembership(String playlistId, Iterable<String> songIds) {
    playlistSongIds[playlistId] = songIds.toSet();
  }

  void markSongsAddedToPlaylist(String playlistId, Iterable<MediaItem> songs) {
    final ids = {...playlistSongIds[playlistId] ?? <String>{}};
    ids.addAll(songs.map((song) => song.id));
    playlistSongIds[playlistId] = ids;
  }

  Future<PlaylistAddStatus> addSongsToPlaylist(
    List<MediaItem> songs,
    String playlistId,
  ) async {
    await ensurePlaylistMembershipLoaded(playlistId);
    final missingSongs = missingSongsForPlaylist(songs, playlistId);
    if (missingSongs.isEmpty) {
      return PlaylistAddStatus.skipped;
    }

    additionInProgress.value = true;
    addingPlaylistIds.add(playlistId);
    try {
      if (playlistType.value == "local") {
        final actuallyAddedSongs = await _addLocalMissingSongs(
          playlistId,
          missingSongs,
        );
        if (actuallyAddedSongs.isEmpty) return PlaylistAddStatus.skipped;
        markSongsAddedToPlaylist(playlistId, actuallyAddedSongs);
        return PlaylistAddStatus.added;
      } else {
        final videosId = missingSongs.map((e) => e.id).toList();
        final res = await Get.find<PipedServices>().addToPlaylist(
          playlistId,
          videosId,
        );
        if (res.code != 1) {
          return PlaylistAddStatus.failed;
        }
        markSongsAddedToPlaylist(playlistId, missingSongs);
        return PlaylistAddStatus.added;
      }
    } catch (e) {
      printWarning(
        "Failed to add songs to playlist $playlistId: $e",
        tag: "AddToPlaylist",
      );
      return PlaylistAddStatus.failed;
    } finally {
      addingPlaylistIds.remove(playlistId);
      additionInProgress.value = addingPlaylistIds.isNotEmpty;
    }
  }

  Future<List<MediaItem>> _addLocalMissingSongs(
    String playlistId,
    List<MediaItem> missingSongs,
  ) async {
    final actuallyAddedSongs = <MediaItem>[];
    final wasOpen = Hive.isBoxOpen(playlistId);
    final playlistBox = await Hive.openBox(playlistId);
    try {
      final existingIds = playlistBox.values
          .map(_songIdFromPlaylistEntry)
          .whereType<String>()
          .toSet();
      for (MediaItem element in missingSongs) {
        if (existingIds.add(element.id)) {
          await playlistBox.add(MediaItemBuilder.toJson(element));
          actuallyAddedSongs.add(element);
        }
      }
    } finally {
      if (!wasOpen) {
        await playlistBox.close();
      }
    }
    return actuallyAddedSongs;
  }

  Future<void> ensurePlaylistMembershipLoaded(String playlistId) async {
    if (playlistSongIds.containsKey(playlistId) ||
        loadingMembershipPlaylistIds.contains(playlistId)) {
      return;
    }
    if (playlistType.value == "local") {
      updatePlaylistMembership(
        playlistId,
        await _readLocalPlaylistSongIds(playlistId),
      );
      return;
    }

    loadingMembershipPlaylistIds.add(playlistId);
    try {
      final songs = await Get.find<PipedServices>().getPlaylistSongs(
        playlistId,
      );
      updatePlaylistMembership(playlistId, songs.map((song) => song.id));
    } catch (e) {
      printWarning(
        "Failed to load playlist membership for $playlistId: $e",
        tag: "AddToPlaylist",
      );
      updatePlaylistMembership(playlistId, const <String>[]);
    } finally {
      loadingMembershipPlaylistIds.remove(playlistId);
    }
  }

  Future<void> _loadLocalPlaylistMembership(List<Playlist> playlists) async {
    for (final playlist in playlists) {
      updatePlaylistMembership(
        playlist.playlistId,
        await _readLocalPlaylistSongIds(playlist.playlistId),
      );
    }
  }

  Future<Set<String>> _readLocalPlaylistSongIds(String playlistId) async {
    final wasOpen = Hive.isBoxOpen(playlistId);
    final playlistBox = await Hive.openBox(playlistId);
    final ids = playlistBox.values
        .map(_songIdFromPlaylistEntry)
        .whereType<String>()
        .toSet();
    if (!wasOpen) {
      await playlistBox.close();
    }
    return ids;
  }

  String? _songIdFromPlaylistEntry(dynamic item) {
    if (item is Map) {
      final id = item['videoId'];
      if (id is String) return id;
    }
    return null;
  }

  // Future<bool> addSongToPlaylist(
  //     MediaItem song, String playlistId, BuildContext context) async {
  //   if (playlistType.value == "local") {
  //     final playlistBox = await Hive.openBox(playlistId);
  //     if (!playlistBox.containsKey(song.id)) {
  //       playlistBox.put(song.id, MediaItemBuilder.toJson(song));
  //       playlistBox.close();
  //       return true;
  //     } else {
  //       playlistBox.close();
  //       return false;
  //     }
  //   } else {
  //     additionInProgress.value = true;

  //     final res =
  //         await Get.find<PipedServices>().addToPlaylist(playlistId, song.id);
  //     additionInProgress.value = false;
  //     return (res.code == 1);
  //   }
  // }
}
