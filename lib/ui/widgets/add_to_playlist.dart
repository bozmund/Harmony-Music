import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '../../services/piped_service.dart';
import '/models/media_Item_builder.dart';
import '/ui/widgets/create_playlist_dialog.dart';
import '../../models/playlist.dart';
import 'common_dialog_widget.dart';
import 'snackbar.dart';

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
        padding:
            const EdgeInsets.only(top: 20, bottom: 30, left: 20, right: 20),
        child: Stack(
          children: [
            Column(children: [
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
                    const SizedBox(
                      width: 10,
                    ),
                    InkWell(
                      child: const Icon(Icons.playlist_add),
                      onTap: () async {
                        Navigator.of(context).pop();
                        await showDialog(
                          context: context,
                          builder: (context) => CreateNRenamePlaylistPopup(
                              isCreateNAdd: true, songItems: songItems),
                        );
                      },
                    )
                  ],
                ),
              ),
              if (isPipedLinked)
                Obx(
                      () =>
                      RadioGroup<String>(
                        groupValue: addToPlaylistController.playlistType.value,
                        onChanged: (value) {
                          if (value == null) return;
                          addToPlaylistController.changePlaylistType(value);
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
              Container(
                decoration: BoxDecoration(
                    color: Theme.of(context).primaryColorLight,
                    borderRadius: BorderRadius.circular(10)),
                height: 250,
                //color: Colors.green,
                child: Obx(
                  () => addToPlaylistController.playlists.isNotEmpty
                      ? ListView.builder(
                          itemCount: addToPlaylistController.playlists.length,
                          itemBuilder: (context, index) => ListTile(
                            leading: const Icon(Icons.add_circle_outline),
                            title: Text(
                              addToPlaylistController.playlists[index].title,
                            ),
                            onTap: () async {
                              await addToPlaylistController
                                  .addSongsToPlaylist(
                                      songItems,
                                      addToPlaylistController.playlists[index]
                                          .playlistId,
                                      context)
                                  .then((value) {
                                if (!context.mounted) return;
                                if (value) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      snackbar(context,
                                          "songAddedToPlaylistAlert".tr,
                                          size: SanckBarSize.MEDIUM));
                                  Navigator.of(context).pop();
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      snackbar(context, "songAlreadyExists".tr,
                                          size: SanckBarSize.MEDIUM));
                                  Navigator.of(context).pop();
                                }
                              });
                            },
                          ),
                        )
                      : Center(
                          child: Text("noLibPlaylist".tr),
                        ),
                ),
              )
            ]),
            Obx(() => (addToPlaylistController.additionInProgress.isTrue &&
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
                        )),
                  )
                : const SizedBox.shrink()),
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
    final res = await Get.find<PipedServices>().getAllPlaylists();
    if (res.code == 1) {
      pipedPlaylists = res.response
          .map((item) => Playlist(
                title: item['name'],
                playlistId: item['id'],
                description: "Piped Playlist",
                thumbnailUrl: item['thumbnail'],
                isPipedPlaylist: true,
              ))
          .whereType<Playlist>()
          .toList();
    }
  }

  void changePlaylistType(String val) {
    playlistType.value = val;
    playlists.value = val == "piped" ? pipedPlaylists : localPlaylists;
  }

  Future<bool> addSongsToPlaylist(
      List<MediaItem> songs, String playlistId, BuildContext context) async {
    additionInProgress.value = true;
    if (playlistType.value == "local") {
      final playlistBox = await Hive.openBox(playlistId);
      final playlistSongIds = playlistBox.values.map((item) => item['videoId']);
      for (MediaItem element in songs) {
        if (!playlistSongIds.contains(element.id)) {
          await playlistBox.add(MediaItemBuilder.toJson(element));
        }
      }
      await playlistBox.close();
      additionInProgress.value = false;
      return true;
    } else {
      final videosId = songs.map((e) => e.id).toList();
      final res =
          await Get.find<PipedServices>().addToPlaylist(playlistId, videosId);
      additionInProgress.value = false;
      return (res.code == 1);
    }
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
