import 'dart:async';

import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '../../../app/providers/controller_providers.dart';
import '../../widgets/toggle_icon_button.dart';
import '../../widgets/add_to_playlist_btn.dart';
import '/ui/player/components/animated_play_button.dart';
import '../player_controller.dart';

class PlayerControlWidget extends ConsumerWidget {
  const PlayerControlWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerController = ref.read(playerControllerProvider);
    return AnimatedBuilder(
      animation: Listenable.merge([
        playerController.currentSong,
        playerController.currentQueue,
        playerController.isCurrentSongFav,
        playerController.isShuffleModeEnabled,
        playerController.isLoopModeEnabled,
        playerController.isQueueLoopModeEnabled,
      ]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: ShaderMask(
                  shaderCallback: (rect) {
                    return const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.transparent,
                      ],
                    ).createShader(
                      Rect.fromLTWH(0, 0, rect.width, rect.height),
                    );
                  },
                  blendMode: BlendMode.dstIn,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Marquee(
                        delay: const Duration(milliseconds: 300),
                        duration: const Duration(seconds: 10),
                        id: "${playerController.currentSong.value}_title",
                        child: Text(
                          playerController.currentSong.value != null
                              ? playerController.currentSong.value!.title
                              : "NA",
                          textAlign: TextAlign.start,
                          style: Theme.of(context).textTheme.labelMedium!,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Marquee(
                        delay: const Duration(milliseconds: 300),
                        duration: const Duration(seconds: 10),
                        id: "${playerController.currentSong.value}_subtitle",
                        child: Text(
                          playerController.currentSong.value != null
                              ? playerController.currentSong.value!.artist!
                              : "NA",
                          textAlign: TextAlign.start,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(
                width: 45,
                child: AddToPlaylistButton(calledFromPlayer: true),
              ),
              SizedBox(
                width: 45,
                child: IconButton(
                  onPressed: playerController.toggleFavourite,
                  icon: Icon(
                    !playerController.isCurrentSongFav.value
                        ? Icons.favorite_border
                        : Icons.favorite,
                    color: Theme.of(context).textTheme.titleMedium!.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          AnimatedBuilder(
            animation: playerController.progressBarStatus,
            builder: (context, _) => ProgressBar(
              thumbRadius: 7,
              barHeight: 4.5,
              baseBarColor: Theme.of(context).sliderTheme.inactiveTrackColor,
              bufferedBarColor: Theme.of(
                context,
              ).sliderTheme.valueIndicatorColor,
              progressBarColor: Theme.of(context).sliderTheme.activeTrackColor,
              thumbColor: Theme.of(context).sliderTheme.thumbColor,
              timeLabelTextStyle: Theme.of(
                context,
              ).textTheme.titleMedium!.copyWith(fontSize: 14),
              progress: playerController.progressBarStatus.value.current,
              total: playerController.progressBarStatus.value.total,
              buffered: playerController.progressBarStatus.value.buffered,
              onSeek: playerController.requestSeek,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ToggleIconButton(
                isActive: playerController.isShuffleModeEnabled.value,
                activeIcon: Icons.shuffle,
                inactiveIcon: Icons.shuffle,
                onPressed: () {
                  unawaited(playerController.toggleShuffleMode());
                },
              ),
              _previousButton(playerController, context),
              const CircleAvatar(
                radius: 35,
                child: AnimatedPlayButton(key: Key("playButton")),
              ),
              _nextButton(playerController, context),
              ToggleIconButton(
                isActive: playerController.isLoopModeEnabled.value,
                activeIcon: Icons.all_inclusive,
                inactiveIcon: Icons.all_inclusive,
                onPressed: () {
                  unawaited(playerController.toggleLoopMode());
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previousButton(
    PlayerController playerController,
    BuildContext context,
  ) {
    return IconButton(
      icon: Icon(
        Icons.skip_previous,
        color: Theme.of(context).textTheme.titleMedium!.color,
      ),
      iconSize: 30,
      onPressed: playerController.requestPrev,
    );
  }
}

Widget _nextButton(PlayerController playerController, BuildContext context) {
  final isLastSong =
      playerController.currentQueue.isEmpty ||
      (!(playerController.isShuffleModeEnabled.value ||
              playerController.isQueueLoopModeEnabled.value) &&
          (playerController.currentQueue.last.id ==
              playerController.currentSong.value?.id));
  return IconButton(
    icon: Icon(
      Icons.skip_next,
      color: isLastSong
          ? Theme.of(
              context,
            ).textTheme.titleLarge!.color!.withValues(alpha: 0.2)
          : Theme.of(context).textTheme.titleMedium!.color,
    ),
    iconSize: 30,
    onPressed: isLastSong ? null : playerController.requestNext,
  );
}
