import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/l10n/l10n.dart';

import '../../../app/providers/controller_providers.dart';
import '../../widgets/snackbar.dart';

class PlayerQueueFooterControls extends ConsumerWidget {
  const PlayerQueueFooterControls({super.key, required this.bottomPadding});

  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerController = ref.read(playerControllerProvider);
    return AnimatedBuilder(
      animation: Listenable.merge([
        playerController.currentQueue,
        playerController.isQueueLoopModeEnabled,
        playerController.isShuffleModeEnabled,
      ]),
      builder: (context, _) => Align(
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.only(
                top: 15,
                bottom: 10,
                left: 10,
                right: 10,
              ),
              decoration: BoxDecoration(
                boxShadow: const [
                  BoxShadow(blurRadius: 5, color: Colors.black54),
                ],
                color: Theme.of(context).primaryColor.withValues(alpha: 0.5),
              ),
              height: 60 + bottomPadding,
              child: Align(
                alignment: Alignment.topCenter,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text(
                      "${playerController.currentQueue.length} ${context.l10n.songs}",
                      style: Theme.of(context).textTheme.titleSmall!.copyWith(
                        color: Theme.of(context).textTheme.titleMedium!.color,
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        unawaited(playerController.toggleQueueLoopMode());
                      },
                      child: Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        decoration: BoxDecoration(
                          color: !playerController.isQueueLoopModeEnabled.value
                              ? Colors.white24
                              : Colors.white.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(child: Text(context.l10n.queueLoop)),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        if (playerController.isShuffleModeEnabled.value) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            snackbar(
                              context,
                              context.l10n.queueShufflingDeniedMsg,
                              size: SanckBarSize.BIG,
                            ),
                          );
                          return;
                        }
                        unawaited(playerController.shuffleQueue());
                      },
                      child: Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Center(
                          child: Icon(Icons.shuffle, color: Colors.black),
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        unawaited(playerController.clearQueue());
                      },
                      child: Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.playlist_remove,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
