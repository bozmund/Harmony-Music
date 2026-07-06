import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';

import '../../../app/providers/controller_providers.dart';
import '../../widgets/loader.dart';

/// A button that animates between a play and pause icon.
///
/// It also shows a loading indicator when the audio is in a loading state.
class AnimatedPlayButton extends ConsumerStatefulWidget {
  /// size of the icon.
  final double iconSize;

  const AnimatedPlayButton({super.key, this.iconSize = 40.0});

  @override
  ConsumerState<AnimatedPlayButton> createState() => _AnimatedPlayButtonState();
}

class _AnimatedPlayButtonState extends ConsumerState<AnimatedPlayButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  PlayerController? _playerController;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    final playerController = ref.read(playerControllerProvider);
    final initialState = playerController.buttonState.value;
    _controller.value = initialState == PlayButtonState.playing ? 1.0 : 0.0;
    _playerController = playerController;
    playerController.buttonState.addListener(_syncAnimationFromController);
  }

  void _syncAnimationFromController() {
    final playerController = _playerController;
    if (playerController == null) return;
    unawaited(
      _syncAnimationWithButtonState(playerController.buttonState.value),
    );
  }

  Future<void> _syncAnimationWithButtonState(
    PlayButtonState buttonState,
  ) async {
    if (!mounted) return;

    try {
      if (buttonState == PlayButtonState.playing) {
        await _controller.forward().orCancel;
      } else if (buttonState != PlayButtonState.loading) {
        await _controller.reverse().orCancel;
      }
    } on TickerCanceled {
      // Animation was cancelled because another animation started
      // or because the widget was disposed.
    }
  }

  @override
  void dispose() {
    _playerController?.buttonState.removeListener(_syncAnimationFromController);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(playerControllerProvider);
    return AnimatedBuilder(
      animation: controller.buttonState,
      builder: (context, _) {
        final buttonState = controller.buttonState.value;
        final isPlaying = buttonState == PlayButtonState.playing;
        final isLoading = buttonState == PlayButtonState.loading;

        return IconButton(
          iconSize: widget.iconSize,
          onPressed: () {
            if (isPlaying) {
              controller.requestPause();
            } else {
              controller.requestPlay();
            }
          },
          icon: isLoading
              ? const LoadingIndicator(dimension: 20)
              : AnimatedIcon(
                  icon: AnimatedIcons.play_pause,
                  progress: _controller,
                ),
        );
      },
    );
  }
}
