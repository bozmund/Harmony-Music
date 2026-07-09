import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/controller_providers.dart';
import '../../../utils/runtime_platform.dart';
import '../../../utils/insets.dart';
import '../../screens/listen_together/listen_together_sheet.dart';
import '../../widgets/awaitable_button.dart';
import '../../widgets/song_info_bottom_sheet.dart';
import 'album_art_lyrics.dart';
import 'background_image.dart';
import 'lyrics_switch.dart';
import 'player_control.dart';

/// Standard player widget
///
/// This widget is used to display the player in the standard mode
///
/// It contains the album art image, lyrics switch, album art with lyrics and player controls
/// and is used in the [Player] widget
class StandardPlayer extends ConsumerWidget {
  const StandardPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.of(context).size;
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = bottomNavInset(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final playerController = ref.read(playerControllerProvider);

    double playerArtImageSize =
        size.width - 60; //((size.height < 750) ? 90 : 60);
    //playerArtImageSize = playerArtImageSize > 350 ? 350 : playerArtImageSize;
    final spaceAvailableForArtImage = size.height - (70 + bottomPadding + 330);
    playerArtImageSize =
        playerArtImageSize > spaceAvailableForArtImage
            ? spaceAvailableForArtImage
            : playerArtImageSize;
    return Stack(
      children: [
        /// Stack first child
        /// Album art image in background covering the whole screen
        const BackgroundImage(cacheHeight: 200),

        /// Stack child
        /// Blur effect on background
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Stack(
            children: [
              /// opacity effect on background
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).primaryColor.withValues(alpha: 0.8),
                  ),
                ),
              ),

              /// used to hide queue header when player is minimized
              /// gradient to used here
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: 65 + bottomPadding + 120,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).primaryColor,
                        Theme.of(context).primaryColor,
                        Theme.of(context).primaryColor.withValues(alpha: 0.4),
                        Theme.of(context).primaryColor.withValues(alpha: 0),
                      ],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      stops: const [0, 0.5, 0.8, 1],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        /// Stack child
        /// Player content in landscape mode
        Padding(
          padding: const EdgeInsets.only(left: 25, right: 25),
          child:
              isLandscape
                  ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      /// Album art with lyrics in .45  of width
                      SizedBox(
                        width: size.width * .45,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 90.0),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 40),
                            child: Center(
                              child: AlbumArtNLyrics(
                                playerArtImageSize: size.width * .29,
                              ),
                            ),
                          ),
                        ),
                      ),

                      /// Player controls in .48 of width
                      SizedBox(
                        width: size.width * .48,
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: 10.0,
                            right: 10,
                            bottom: bottomPadding,
                          ),
                          child: const PlayerControlWidget(),
                        ),
                      ),
                    ],
                  )
                  :
                  /// Player content in portrait mode
                  Column(
                    children: [
                      /// Work as top padding depending on the lyrics visibility and screen size
                      AnimatedBuilder(
                        animation: playerController.showLyricsFlag,
                        builder:
                            (context, _) =>
                                playerController.showLyricsFlag.value
                                    ? SizedBox(
                                      height: size.height < 750 ? 60 : 90,
                                    )
                                    : SizedBox(
                                      height: size.height < 750 ? 110 : 140,
                                    ),
                      ),

                      /// Contains the lyrics switch and album art with lyrics
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const LyricsSwitch(),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 500),
                            child: AlbumArtNLyrics(
                              playerArtImageSize: playerArtImageSize,
                            ),
                          ),
                        ],
                      ),

                      /// Extra space container
                      Expanded(child: Container()),

                      /// Contains the player controls
                      Padding(
                        padding: EdgeInsets.only(bottom: 80 + bottomPadding),
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 500),
                          child: const PlayerControlWidget(),
                        ),
                      ),
                    ],
                  ),
        ),

        /// Stack child
        /// Contains [Minimize button], Playing from [Album name], [More button] for current song context
        /// This is not visible in mobile devices in landscape mode
        if (!(isLandscape && RuntimePlatform.isMobile))
          Padding(
            padding: EdgeInsets.only(
              top: mediaQuery.padding.top + 20,
              left: 10,
              right: 10,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// Minimize button
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down, size: 28),
                  onPressed: playerController.playerPanelController.close,
                ),

                /// Playing from [Album name]
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8.0, left: 5, right: 5),
                    child: AnimatedBuilder(
                      animation: playerController.playingFrom,
                      builder:
                          (context, _) => Column(
                            children: [
                              Text(
                                playerController.playingFrom.value.typeString,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                "\"${playerController.playingFrom.value.nameString}\"",
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                    ),
                  ),
                ),

                /// Listen together (synchronized playback across phones)
                AnimatedBuilder(
                  animation: ref.read(listenTogetherControllerProvider),
                  builder: (context, _) {
                    final lt = ref.read(listenTogetherControllerProvider);
                    return IconButton(
                      icon: Icon(
                        lt.isActive ? Icons.groups_2 : Icons.groups_2_outlined,
                        size: 25,
                        color:
                            lt.isActive
                                ? Theme.of(context).colorScheme.primary
                                : null,
                      ),
                      onPressed: () async {
                        await showListenTogetherSheet(
                          playerController
                              .homeScaffoldKey
                              .currentState!
                              .context,
                        );
                      },
                    );
                  },
                ),

                /// More button for current song context
                AwaitableIconButton(
                  icon: const Icon(Icons.more_vert, size: 25),
                  onPressed: () async {
                    await showModalBottomSheet(
                      constraints: const BoxConstraints(maxWidth: 500),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(10.0),
                        ),
                      ),
                      isScrollControlled: true,
                      context:
                          playerController
                              .homeScaffoldKey
                              .currentState!
                              .context,
                      barrierColor: Colors.transparent.withAlpha(100),
                      builder:
                          (context) => SongInfoBottomSheet(
                            playerController.currentSong.value!,
                            calledFromPlayer: true,
                          ),
                    );
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}
