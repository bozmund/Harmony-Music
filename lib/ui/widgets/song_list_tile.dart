import 'dart:async';

import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:get/get.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '../../models/playlist.dart';
import '../player/player_controller.dart';
import '../screens/Settings/settings_screen_controller.dart';
import 'add_to_playlist.dart';
import 'image_widget.dart';
import 'snackbar.dart';
import 'song_info_bottom_sheet.dart';

class SongListTile extends StatelessWidget with RemoveSongFromPlaylistMixin {
  const SongListTile({
    super.key,
    this.onTap,
    required this.song,
    this.playlist,
    this.isPlaylistOrAlbum = false,
    this.thumbReplacementWithIndex = false,
    this.index,
  });

  final Playlist? playlist;
  final MediaItem song;
  final VoidCallback? onTap;
  final bool isPlaylistOrAlbum;

  /// Valid for Album songs
  final bool thumbReplacementWithIndex;
  final int? index;

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    return Listener(
      onPointerDown: (PointerDownEvent event) async {
        if (event.buttons == kSecondaryMouseButton) {
          //show song info bottom sheet
          await showModalBottomSheet(
            constraints: const BoxConstraints(maxWidth: 500),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(10.0)),
            ),
            isScrollControlled: true,
            context: playerController.homeScaffoldKey.currentState!.context,
            barrierColor: Colors.transparent.withAlpha(100),
            builder: (context) => SongInfoBottomSheet(song, playlist: playlist),
          ).whenComplete(() => Get.delete<SongInfoController>());
        }
      },
      child: Slidable(
        enabled:
            Get.find<SettingsScreenController>().slidableActionEnabled.isTrue,
        startActionPane: ActionPane(
          motion: const DrawerMotion(),
          children: [
            SlidableAction(
              onPressed: (context) async {
                await showDialog(
                  context: context,
                  builder: (context) => AddToPlaylist([song]),
                ).whenComplete(() => Get.delete<AddToPlaylistController>());
              },
              backgroundColor: Theme.of(context).colorScheme.secondary,
              foregroundColor: Theme.of(context).textTheme.titleMedium!.color,
              icon: Icons.playlist_add,
              //label: 'Add to playlist',
            ),
            if (playlist != null && !playlist!.isCloudPlaylist)
              SlidableAction(
                onPressed: (context) async {
                  await removeSongFromPlaylist(song, playlist!);
                },
                backgroundColor: Theme.of(context).colorScheme.secondary,
                foregroundColor: Theme.of(context).textTheme.titleMedium!.color,
                icon: Icons.delete,
                //label: 'delete',
              ),
          ],
        ),
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          children: [
            SlidableAction(
              onPressed: (context) {
                unawaited(
                  playerController.enqueueSong(song).whenComplete(() {
                    ScaffoldMessenger.of(context).showSnackBar(
                      snackbar(
                        context,
                        "songEnqueueAlert".tr,
                        size: SanckBarSize.MEDIUM,
                      ),
                    );
                  }),
                );
              },
              backgroundColor: Theme.of(context).colorScheme.secondary,
              foregroundColor: Theme.of(context).textTheme.titleMedium!.color,
              icon: Icons.merge,
              //label: 'Enqueue',
            ),
            SlidableAction(
              onPressed: (context) {
                unawaited(
                  playerController.playNext(song).whenComplete(() {
                    ScaffoldMessenger.of(context).showSnackBar(
                      snackbar(
                        context,
                        "${"playNextMsg".tr} ${song.title}",
                        size: SanckBarSize.BIG,
                      ),
                    );
                  }),
                );
              },
              backgroundColor: Theme.of(context).colorScheme.secondary,
              foregroundColor: Theme.of(context).textTheme.titleMedium!.color,
              icon: Icons.next_plan_outlined,
              //label: 'Play Next',
            ),
          ],
        ),
        child: ListTile(
          onTap: onTap,
          onLongPress: () async {
            await showModalBottomSheet(
              constraints: const BoxConstraints(maxWidth: 500),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(10.0)),
              ),
              isScrollControlled: true,
              context: playerController.homeScaffoldKey.currentState!.context,
              //constraints: BoxConstraints(maxHeight:Get.height),
              barrierColor: Colors.transparent.withAlpha(100),
              builder: (context) =>
                  SongInfoBottomSheet(song, playlist: playlist),
            ).whenComplete(() => Get.delete<SongInfoController>());
          },
          contentPadding: const EdgeInsets.only(top: 0, left: 5, right: 30),
          leading: thumbReplacementWithIndex
              ? SizedBox(
                  width: 27.5,
                  height: 55,
                  child: Center(
                    child: Text(
                      "$index.",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                )
              : ImageWidget(size: 55, song: song),
          title: Marquee(
            delay: const Duration(milliseconds: 300),
            duration: const Duration(seconds: 5),
            id: song.title.hashCode.toString(),
            child: Text(
              song.title.length > 50 ? song.title.substring(0, 50) : song.title,
              maxLines: 1,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          subtitle: Text(
            "${song.artist}",
            maxLines: 1,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          trailing: SizedBox(
            width: Get.size.width > 800 ? 80 : 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isPlaylistOrAlbum)
                      Obx(
                        () => playerController.currentSong.value?.id == song.id
                            ? const Icon(Icons.equalizer)
                            : const SizedBox.shrink(),
                      ),
                    Text(
                      song.extras!['length'] ?? "",
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
                if (GetPlatform.isDesktop)
                  IconButton(
                    splashRadius: 20,
                    onPressed: () async {
                      await showModalBottomSheet(
                        constraints: const BoxConstraints(maxWidth: 500),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(10.0),
                          ),
                        ),
                        isScrollControlled: true,
                        context: playerController
                            .homeScaffoldKey
                            .currentState!
                            .context,
                        //constraints: BoxConstraints(maxHeight:Get.height),
                        barrierColor: Colors.transparent.withAlpha(100),
                        builder: (context) =>
                            SongInfoBottomSheet(song, playlist: playlist),
                      ).whenComplete(() => Get.delete<SongInfoController>());
                    },
                    icon: const Icon(Icons.more_vert),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
