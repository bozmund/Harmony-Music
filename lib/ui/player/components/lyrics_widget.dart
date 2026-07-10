import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:harmonymusic/l10n/l10n.dart';

import '../../../app/providers/controller_providers.dart';
import '../../widgets/loader.dart';

class LyricsWidget extends ConsumerWidget {
  final EdgeInsetsGeometry padding;
  const LyricsWidget({super.key, required this.padding});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerController = ref.read(playerControllerProvider);
    return AnimatedBuilder(
      animation: Listenable.merge([
        playerController.isLyricsLoading,
        playerController.lyricsMode,
        playerController.lyrics,
      ]),
      builder: (context, _) => playerController.isLyricsLoading.value
          ? const Center(child: LoadingIndicator())
          : playerController.lyricsMode.value == 1
          ? Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: padding,
                child: TextSelectionTheme(
                  data: Theme.of(context).textSelectionTheme,
                  child: SelectableText(
                    playerController.lyrics["plainLyrics"] == "NA"
                        ? context.l10n.lyricsNotAvailable
                        : playerController.lyrics["plainLyrics"],
                    textAlign: TextAlign.center,
                    style: playerController.isDesktopLyricsDialogOpen
                        ? Theme.of(context).textTheme.titleMedium!
                        : Theme.of(context).textTheme.titleMedium!.copyWith(
                            color: Colors.white,
                          ),
                  ),
                ),
              ),
            )
          : IgnorePointer(
              child: Builder(
                builder: (context) {
                  final syncedLyrics = playerController.lyrics['synced']
                      .toString();
                  if (syncedLyrics.isEmpty || syncedLyrics == "NA") {
                    return Center(
                      child: Text(
                        context.l10n.syncedLyricsNotAvailable,
                        style: playerController.isDesktopLyricsDialogOpen
                            ? Theme.of(context).textTheme.titleMedium!
                            : Theme.of(context).textTheme.titleMedium!.copyWith(
                                color: Colors.white,
                              ),
                      ),
                    );
                  }

                  playerController.updateSyncedLyricsController();
                  return Padding(
                    padding: padding,
                    child: LyricView(
                      controller: playerController.lyricController,
                      style: LyricStyles.default1,
                    ),
                  );
                },
              ),
            ),
    );
  }
}
