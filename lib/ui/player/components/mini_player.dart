import 'dart:async';

import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '../../../app/providers/controller_providers.dart';
import '/ui/widgets/lyrics_dialog.dart';
import '/ui/widgets/song_info_dialog.dart';
import '../../widgets/add_to_playlist_btn.dart';
import '../../widgets/toggle_icon_button.dart';
import '../../widgets/awaitable_button.dart';
import '../../widgets/sleep_timer_bottom_sheet.dart';
import '../../widgets/song_download_btn.dart';
import '../../widgets/image_widget.dart';
import '../../widgets/mini_player_progress_bar.dart';
import 'animated_play_button.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerController = ref.read(playerControllerProvider);
    final settingsController = ref.read(settingsScreenControllerProvider);
    final size = MediaQuery.of(context).size;
    final isWideScreen = size.width > 800;
    final bottomNavEnabled = settingsController.isBottomNavBarEnabled.value;
    return AnimatedBuilder(
      animation: Listenable.merge([
        playerController.currentSong,
        playerController.playerPanelTopVisible,
        playerController.playerPaneOpacity,
        settingsController.isBottomNavBarEnabled,
      ]),
      builder: (context, _) {
        return Visibility(
          visible:
              playerController.playerPanelTopVisible.value &&
              playerController.currentSong.value != null,
          child: AnimatedOpacity(
            opacity: playerController.playerPaneOpacity.value,
            duration: Duration.zero,
            child: Container(
              height: height,
              width: size.width,
              color: Theme.of(context).bottomSheetTheme.backgroundColor,
              child: Center(
                child: Column(
                  children: [
                    !isWideScreen || bottomNavEnabled
                        ? Container(
                            height: 3,
                            color: Theme.of(
                              context,
                            ).progressIndicatorTheme.color,
                            child: AnimatedBuilder(
                              animation: playerController.progressBarStatus,
                              builder: (context, _) => MiniPlayerProgressBar(
                                progressBarStatus:
                                    playerController.progressBarStatus.value,
                                progressBarColor:
                                    Theme.of(
                                      context,
                                    ).progressIndicatorTheme.linearTrackColor ??
                                    Colors.white,
                              ),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.only(
                              left: 15.0,
                              top: 8,
                              right: 15,
                              bottom: 0,
                            ),
                            child: AnimatedBuilder(
                              animation: playerController.progressBarStatus,
                              builder: (context, _) => ProgressBar(
                                timeLabelLocation: TimeLabelLocation.sides,
                                thumbRadius: 7,
                                barHeight: 4,
                                thumbGlowRadius: 15,
                                baseBarColor: Theme.of(
                                  context,
                                ).sliderTheme.inactiveTrackColor,
                                bufferedBarColor: Theme.of(
                                  context,
                                ).sliderTheme.valueIndicatorColor,
                                progressBarColor: Theme.of(
                                  context,
                                ).sliderTheme.activeTrackColor,
                                thumbColor: Theme.of(
                                  context,
                                ).sliderTheme.thumbColor,
                                timeLabelTextStyle: Theme.of(
                                  context,
                                ).textTheme.titleMedium,
                                progress: playerController
                                    .progressBarStatus
                                    .value
                                    .current,
                                total: playerController
                                    .progressBarStatus
                                    .value
                                    .total,
                                buffered: playerController
                                    .progressBarStatus
                                    .value
                                    .buffered,
                                onSeek: playerController.requestSeek,
                              ),
                            ),
                          ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 17.0,
                        vertical: 7,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              playerController.currentSong.value != null
                                  ? ImageWidget(
                                      size: 50,
                                      song: playerController.currentSong.value!,
                                    )
                                  : const SizedBox(height: 50, width: 50),
                            ],
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onHorizontalDragEnd: (DragEndDetails details) {
                                if (details.primaryVelocity! < 0) {
                                  playerController.requestNext();
                                } else if (details.primaryVelocity! > 0) {
                                  playerController.requestPrev();
                                }
                              },
                              onTap: () async {
                                await playerController.playerPanelController
                                    .open();
                              },
                              child: ColoredBox(
                                color: Colors.transparent,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      height: 20,
                                      child: Text(
                                        playerController.currentSong.value !=
                                                null
                                            ? playerController
                                                  .currentSong
                                                  .value!
                                                  .title
                                            : "",
                                        maxLines: 1,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                    ),
                                    SizedBox(
                                      height: 20,
                                      child: Marquee(
                                        id: "${playerController.currentSong.value}_mini",
                                        delay: const Duration(
                                          milliseconds: 300,
                                        ),
                                        duration: const Duration(seconds: 5),
                                        child: Text(
                                          playerController.currentSong.value !=
                                                  null
                                              ? playerController
                                                    .currentSong
                                                    .value!
                                                    .artist!
                                              : "",
                                          maxLines: 1,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleSmall,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          //player control
                          SizedBox(
                            width: isWideScreen && !bottomNavEnabled ? 450 : 90,
                            child: AnimatedBuilder(
                              animation: Listenable.merge([
                                playerController.currentSong,
                                playerController.currentQueue,
                                playerController.isCurrentSongFav,
                                playerController.isShuffleModeEnabled,
                                playerController.isLoopModeEnabled,
                                playerController.isQueueLoopModeEnabled,
                              ]),
                              builder: (context, _) => Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  if (isWideScreen && !bottomNavEnabled)
                                    Row(
                                      children: [
                                        IconButton(
                                          iconSize: 20,
                                          onPressed:
                                              playerController.toggleFavourite,
                                          icon: Icon(
                                            !playerController
                                                    .isCurrentSongFav
                                                    .value
                                                ? Icons.favorite_border
                                                : Icons.favorite,
                                            color: Theme.of(
                                              context,
                                            ).textTheme.titleMedium!.color,
                                          ),
                                        ),
                                        ToggleIconButton(
                                          size: 20,
                                          isActive: playerController
                                              .isShuffleModeEnabled
                                              .value,
                                          activeIcon: Icons.shuffle,
                                          inactiveIcon: Icons.shuffle,
                                          onPressed: () {
                                            unawaited(
                                              playerController
                                                  .toggleShuffleMode(),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  if (isWideScreen && !bottomNavEnabled)
                                    SizedBox(
                                      width: 40,
                                      child: InkWell(
                                        onTap:
                                            (playerController
                                                    .currentQueue
                                                    .isEmpty ||
                                                // On the first song, prev is
                                                // still valid when shuffle or
                                                // queue-loop is on (it wraps
                                                // to the end of the queue).
                                                (!(playerController
                                                            .isShuffleModeEnabled
                                                            .value ||
                                                        playerController
                                                            .isQueueLoopModeEnabled
                                                            .value) &&
                                                    playerController
                                                            .currentQueue
                                                            .first
                                                            .id ==
                                                        playerController
                                                            .currentSong
                                                            .value
                                                            ?.id))
                                            ? null
                                            : playerController.requestPrev,
                                        child: Icon(
                                          Icons.skip_previous,
                                          color: Theme.of(
                                            context,
                                          ).textTheme.titleMedium!.color,
                                          size: 35,
                                        ),
                                      ),
                                    ),
                                  isWideScreen && !bottomNavEnabled
                                      ? Container(
                                          decoration: BoxDecoration(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.secondary,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          width: 58,
                                          height: 58,
                                          child: Center(
                                            child: AnimatedPlayButton(
                                              iconSize: isWideScreen ? 43 : 35,
                                            ),
                                          ),
                                        )
                                      : SizedBox.square(
                                          dimension: 50,
                                          child: Center(
                                            child: AnimatedPlayButton(
                                              iconSize: isWideScreen ? 43 : 35,
                                            ),
                                          ),
                                        ),
                                  SizedBox(
                                    width: 40,
                                    child: Builder(
                                      builder: (context) {
                                        final isLastSong =
                                            playerController
                                                .currentQueue
                                                .isEmpty ||
                                            (!(playerController
                                                        .isShuffleModeEnabled
                                                        .value ||
                                                    playerController
                                                        .isQueueLoopModeEnabled
                                                        .value) &&
                                                (playerController
                                                        .currentQueue
                                                        .last
                                                        .id ==
                                                    playerController
                                                        .currentSong
                                                        .value
                                                        ?.id));
                                        return InkWell(
                                          onTap: isLastSong
                                              ? null
                                              : playerController.requestNext,
                                          child: Icon(
                                            Icons.skip_next,
                                            color: isLastSong
                                                ? Theme.of(context)
                                                      .textTheme
                                                      .titleLarge!
                                                      .color!
                                                      .withValues(alpha: 0.2)
                                                : Theme.of(context)
                                                      .textTheme
                                                      .titleMedium!
                                                      .color,
                                            size: 35,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  if (isWideScreen && !bottomNavEnabled)
                                    Row(
                                      children: [
                                        IconButton(
                                          iconSize: 20,
                                          onPressed: () {
                                            unawaited(
                                              playerController.toggleLoopMode(),
                                            );
                                          },
                                          icon: Icon(
                                            Icons.all_inclusive,
                                            color:
                                                playerController
                                                    .isLoopModeEnabled
                                                    .value
                                                ? Theme.of(
                                                    context,
                                                  ).textTheme.titleLarge!.color
                                                : Theme.of(context)
                                                      .textTheme
                                                      .titleLarge!
                                                      .color!
                                                      .withValues(alpha: 0.2),
                                          ),
                                        ),
                                        AwaitableIconButton(
                                          iconSize: 20,
                                          onPressed: () async {
                                            await playerController.showLyrics();
                                            await showDialog(
                                              builder: (context) =>
                                                  const LyricsDialog(),
                                              context: context,
                                            ).whenComplete(() {
                                              playerController
                                                      .isDesktopLyricsDialogOpen =
                                                  false;
                                              playerController
                                                      .showLyricsFlag
                                                      .value =
                                                  false;
                                            });
                                            playerController
                                                    .isDesktopLyricsDialogOpen =
                                                true;
                                          },
                                          icon: Icon(
                                            Icons.lyrics_outlined,
                                            color: Theme.of(
                                              context,
                                            ).textTheme.titleLarge!.color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (isWideScreen && !bottomNavEnabled)
                                    const SizedBox(width: 20),
                                ],
                              ),
                            ),
                          ),
                          if (isWideScreen && !bottomNavEnabled)
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: size.width < 1004 ? 0 : 30.0,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.only(
                                        right: 20,
                                        left: 10,
                                      ),
                                      height: 20,
                                      width: (size.width > 860) ? 220 : 180,
                                      child: Builder(
                                        builder: (context) {
                                          final volume =
                                              playerController.volume.value;
                                          return Row(
                                            children: [
                                              SizedBox(
                                                width: 20,
                                                child: InkWell(
                                                  onTap: playerController.mute,
                                                  child: Icon(
                                                    volume == 0
                                                        ? Icons.volume_off
                                                        : volume > 0 &&
                                                              volume < 50
                                                        ? Icons.volume_down
                                                        : Icons.volume_up,
                                                    size: 20,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: SliderTheme(
                                                  data: SliderTheme.of(context).copyWith(
                                                    trackHeight: 2,
                                                    thumbShape:
                                                        const RoundSliderThumbShape(
                                                          enabledThumbRadius:
                                                              6.0,
                                                        ),
                                                    overlayShape:
                                                        const RoundSliderOverlayShape(
                                                          overlayRadius: 10.0,
                                                        ),
                                                  ),
                                                  child: Slider(
                                                    value:
                                                        playerController
                                                            .volume
                                                            .value /
                                                        100,
                                                    onChanged: (value) async {
                                                      await playerController
                                                          .setVolume(
                                                            (value * 100)
                                                                .toInt(),
                                                          );
                                                    },
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                    SizedBox(
                                      height: 40,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          IconButton(
                                            onPressed: () {
                                              playerController
                                                  .homeScaffoldKey
                                                  .currentState!
                                                  .openEndDrawer();
                                            },
                                            icon: const Icon(Icons.queue_music),
                                          ),
                                          if (size.width > 860)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                left: 10.0,
                                              ),
                                              child: AwaitableIconButton(
                                                onPressed: () async {
                                                  await showModalBottomSheet(
                                                    constraints:
                                                        const BoxConstraints(
                                                          maxWidth: 500,
                                                        ),
                                                    shape: const RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.vertical(
                                                            top:
                                                                Radius.circular(
                                                                  10.0,
                                                                ),
                                                          ),
                                                    ),
                                                    isScrollControlled: true,
                                                    context: playerController
                                                        .homeScaffoldKey
                                                        .currentState!
                                                        .context,
                                                    barrierColor: Colors
                                                        .transparent
                                                        .withAlpha(100),
                                                    builder: (context) =>
                                                        const SleepTimerBottomSheet(),
                                                  );
                                                },
                                                icon: Icon(
                                                  playerController
                                                          .isSleepTimerActive
                                                          .value
                                                      ? Icons.timer
                                                      : Icons.timer_outlined,
                                                ),
                                              ),
                                            ),
                                          const SizedBox(width: 10),
                                          const SongDownloadButton(
                                            calledFromPlayer: true,
                                          ),
                                          const SizedBox(width: 10),
                                          const AddToPlaylistButton(
                                            calledFromPlayer: true,
                                          ),
                                          if (size.width > 965)
                                            AwaitableIconButton(
                                              onPressed: () async {
                                                final currentSong =
                                                    playerController
                                                        .currentSong
                                                        .value;
                                                if (currentSong != null) {
                                                  await showDialog(
                                                    context: context,
                                                    builder: (context) =>
                                                        SongInfoDialog(
                                                          song: currentSong,
                                                          includePlaybackDebug:
                                                              true,
                                                        ),
                                                  );
                                                }
                                              },
                                              icon: const Icon(
                                                Icons.info,
                                                size: 22,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
