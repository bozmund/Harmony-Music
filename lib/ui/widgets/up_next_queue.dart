import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/utils/get_localization.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '../../app/providers/controller_providers.dart';
import '../../models/media_Item_builder.dart';
import '../../utils/runtime_platform.dart';
import '../../utils/insets.dart';
import 'image_widget.dart';
import 'snackbar.dart';
import 'song_info_bottom_sheet.dart';

class UpNextQueue extends ConsumerWidget {
  const UpNextQueue({
    super.key,
    this.onReorderEnd,
    this.onReorderStart,
    this.isQueueInSlidePanel = true,
  });
  final void Function(int)? onReorderStart;
  final void Function(int)? onReorderEnd;
  final bool isQueueInSlidePanel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerController = ref.read(playerControllerProvider);
    final bottomPadding = bottomNavInset(context);
    return Container(
      color: Theme.of(context).bottomSheetTheme.backgroundColor,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          playerController.currentQueue,
          playerController.currentSongIndex,
          playerController.isShuffleModeEnabled,
        ]),
        builder: (context, _) {
          final displayQueue = playerController.displayQueue;
          return ReorderableListView.builder(
            footer: SizedBox(height: bottomPadding),
            scrollController: isQueueInSlidePanel
                ? playerController.scrollController
                : null,
            onReorderItem: (int oldIndex, int newIndex) {
              if (playerController.isShuffleModeEnabled.value) {
                ScaffoldMessenger.of(context).showSnackBar(
                  snackbar(
                    context,
                    "queueRearrangingDeniedMessage".tr,
                    size: SanckBarSize.BIG,
                  ),
                );
                return;
              }
              unawaited(playerController.onDisplayReorder(oldIndex, newIndex));
            },
            onReorderStart: onReorderStart,
            onReorderEnd: onReorderEnd,
            itemCount: displayQueue.length,
            padding: EdgeInsets.only(
              top: isQueueInSlidePanel ? 55 : 0,
              bottom: isQueueInSlidePanel ? 80 : 0,
            ),
            physics: const AlwaysScrollableScrollPhysics(),
            itemBuilder: (context, index) {
              final homeScaffoldContext =
                  playerController.homeScaffoldKey.currentContext!;
              final song = displayQueue[index];
              final realIndex = playerController.realQueueIndexForDisplayIndex(
                index,
              );
              final isCurrentSong =
                  playerController.currentSongIndex.value == realIndex;
              return Material(
                key: Key('queue-row-${song.id}-$realIndex'),
                child: Dismissible(
                  key: Key('queue-dismiss-${song.id}-$realIndex'),
                  direction: DismissDirection.horizontal,
                  confirmDismiss: (direction) async =>
                      playerController.currentSongIndex.value != realIndex,
                  onDismissed: (direction) {
                    unawaited(playerController.removeFromQueue(song));
                  },
                  child: ListTile(
                    onTap: () => playerController.requestSeekByIndex(realIndex),
                    onLongPress: () async {
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
                        barrierColor: Colors.transparent.withAlpha(100),
                        builder: (context) =>
                            SongInfoBottomSheet(song, calledFromQueue: true),
                      );
                    },
                    contentPadding: EdgeInsets.only(
                      top: 0,
                      left: RuntimePlatform.isAndroid ? 30 : 0,
                      right: 25,
                    ),
                    tileColor: isCurrentSong
                        ? Theme.of(homeScaffoldContext).colorScheme.secondary
                        : Theme.of(
                            homeScaffoldContext,
                          ).bottomSheetTheme.backgroundColor,
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (RuntimePlatform.isDesktop)
                          IconButton(
                            onPressed: () {
                              if (isCurrentSong) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  snackbar(
                                    context,
                                    "songRemovedFromQueueCurrSong".tr,
                                    size: SanckBarSize.BIG,
                                  ),
                                );
                              } else {
                                unawaited(
                                  playerController.removeFromQueue(song),
                                );
                              }
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ImageWidget(size: 50, song: song),
                      ],
                    ),
                    title: Marquee(
                      delay: const Duration(milliseconds: 300),
                      duration: const Duration(seconds: 5),
                      id: "queue${song.title.hashCode}",
                      child: Text(
                        song.title,
                        maxLines: 1,
                        style: Theme.of(
                          homeScaffoldContext,
                        ).textTheme.titleMedium,
                      ),
                    ),
                    subtitle: Text(
                      "${song.artist}",
                      maxLines: 1,
                      style: isCurrentSong
                          ? Theme.of(
                              homeScaffoldContext,
                            ).textTheme.titleSmall!.copyWith(
                              color: Theme.of(homeScaffoldContext)
                                  .textTheme
                                  .titleMedium!
                                  .color!
                                  .withValues(alpha: 0.35),
                            )
                          : Theme.of(homeScaffoldContext).textTheme.titleSmall,
                    ),
                    trailing: ReorderableDragStartListener(
                      enabled: !RuntimePlatform.isDesktop,
                      index: index,
                      child: Container(
                        padding: EdgeInsets.only(
                          right: RuntimePlatform.isDesktop ? 20 : 5,
                          left: 20,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            if (!RuntimePlatform.isDesktop)
                              const Icon(Icons.drag_handle),
                            isCurrentSong
                                ? const Icon(
                                    Icons.equalizer,
                                    color: Colors.white,
                                  )
                                : Text(
                                    MediaItemBuilder.displayDuration(song),
                                    style: Theme.of(
                                      homeScaffoldContext,
                                    ).textTheme.titleSmall,
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
