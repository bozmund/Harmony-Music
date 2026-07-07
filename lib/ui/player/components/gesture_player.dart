import 'dart:async';
import 'dart:ui';

import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/ui/player/components/background_image.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '../../../app/providers/controller_providers.dart';
import '../../widgets/song_info_bottom_sheet.dart';
import '../../utils/theme_controller.dart';
import '../../../utils/insets.dart';
class GesturePlayer extends ConsumerWidget {
  const GesturePlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerController = ref.read(playerControllerProvider);
    final bottomPadding = bottomNavInset(context);
    return Stack(
      children: [
        GestureDetector(
          /// Full screen Background image is acting as album art
          child: const BackgroundImage(),
          onHorizontalDragEnd: (DragEndDetails details) {
            if (details.primaryVelocity! < 0) {
              playerController.requestNext();
            } else if (details.primaryVelocity! > 0) {
              playerController.requestPrev();
            }
          },
          onDoubleTap: playerController.requestPlayPause,
          onLongPress: () async {
            await showModalBottomSheet(
              constraints: const BoxConstraints(maxWidth: 500),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(10.0)),
              ),
              isScrollControlled: true,
              context: playerController.homeScaffoldKey.currentState!.context,
              barrierColor: Colors.transparent.withAlpha(100),
              builder: (context) => SongInfoBottomSheet(
                playerController.currentSong.value!,
                calledFromPlayer: true,
              ),
            );
          },
        ),
        IgnorePointer(
          child: Align(
            child: Center(
              child: AnimatedBuilder(
                animation: playerController.gesturePlayerVisibleState,
                builder: (context, _) => FadeTransition(
                  opacity: playerController.gesturePlayerStateAnimation!,
                  child: playerController.gesturePlayerVisibleState.value == 2
                      ? const SizedBox.shrink()
                      : Icon(
                          playerController.gesturePlayerVisibleState.value == 1
                              ? Icons.play_arrow
                              : Icons.pause,
                          size: 180,
                          color: Colors.white,
                        ),
                ),
              ),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: Listenable.merge([
            playerController.currentSong,
            playerController.currentQueue,
            playerController.isCurrentSongFav,
            playerController.isShuffleModeEnabled,
            playerController.isLoopModeEnabled,
            playerController.isQueueLoopModeEnabled,
          ]),
          builder: (context, _) => Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: bottomPadding != 0 ? bottomPadding + 10 : 20,
                left: 20,
                right: 20,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(maxWidth: 500),
                height: 142,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 10,
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Marquee(
                                      delay: const Duration(milliseconds: 300),
                                      duration: const Duration(seconds: 10),
                                      id: "${playerController.currentSong.value}_title",
                                      child: Text(
                                        playerController.currentSong.value !=
                                                null
                                            ? playerController
                                                  .currentSong
                                                  .value!
                                                  .title
                                            : "NA",
                                        textAlign: TextAlign.start,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium!
                                            .copyWith(
                                              color: Theme.of(
                                                context,
                                              ).primaryColor.complementaryColor,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    Marquee(
                                      delay: const Duration(milliseconds: 300),
                                      duration: const Duration(seconds: 10),
                                      id: "${playerController.currentSong.value}_subtitle",
                                      child: Text(
                                        playerController.currentSong.value !=
                                                null
                                            ? playerController
                                                  .currentSong
                                                  .value!
                                                  .artist!
                                            : "NA",
                                        textAlign: TextAlign.start,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall!
                                            .copyWith(
                                              color: Theme.of(
                                                context,
                                              ).primaryColor.complementaryColor,
                                              fontWeight: FontWeight.normal,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 75,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      splashRadius: 10,
                                      iconSize: 20,
                                      visualDensity: const VisualDensity(
                                        horizontal: -4,
                                        vertical: -4,
                                      ),
                                      onPressed:
                                          playerController.toggleFavourite,
                                      icon: Icon(
                                        !playerController.isCurrentSongFav.value
                                            ? Icons.favorite_border
                                            : Icons.favorite,
                                        color: Theme.of(
                                          context,
                                        ).textTheme.titleMedium!.color,
                                      ),
                                    ),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        IconButton(
                                          splashRadius: 10,
                                          visualDensity: const VisualDensity(
                                            horizontal: -4,
                                            vertical: -4,
                                          ),
                                          iconSize: 18,
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
                                        IconButton(
                                          iconSize: 18,
                                          splashRadius: 10,
                                          visualDensity: const VisualDensity(
                                            horizontal: -4,
                                            vertical: -4,
                                          ),
                                          onPressed: () {
                                            unawaited(
                                              playerController
                                                  .toggleShuffleMode(),
                                            );
                                          },
                                          icon: Icon(
                                            Icons.shuffle,
                                            color:
                                                playerController
                                                    .isShuffleModeEnabled
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
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          AnimatedBuilder(
                            animation: playerController.progressBarStatus,
                            builder: (context, _) => ProgressBar(
                              thumbRadius: 6,
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
                              timeLabelTextStyle: Theme.of(context)
                                  .textTheme
                                  .titleSmall!
                                  .copyWith(
                                    color: Theme.of(
                                      context,
                                    ).primaryColor.complementaryColor,
                                  ),
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
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // absorb pointer to prevent the next,prev gesture from being triggered when the user tries to switch app
        Align(
          alignment: Alignment.bottomCenter,
          child: AbsorbPointer(
            child: SizedBox(height: bottomPadding + 20, child: Container()),
          ),
        ),
      ],
    );
  }
}
