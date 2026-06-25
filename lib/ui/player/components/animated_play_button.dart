import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';

import '../../widgets/loader.dart';

/// A button that animates between a play and pause icon.
///
/// It also shows a loading indicator when the audio is in a loading state.
class AnimatedPlayButton extends StatefulWidget {
  /// size of the icon.
  final double iconSize;

  const AnimatedPlayButton({super.key, this.iconSize = 40.0});

  @override
  State<AnimatedPlayButton> createState() => _AnimatedPlayButtonState();
}

class _AnimatedPlayButtonState extends State<AnimatedPlayButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Worker _buttonStateWorker;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    final playerController = Get.find<PlayerController>();
    final initialState = playerController.buttonState.value;
    _controller.value = initialState == PlayButtonState.playing ? 1.0 : 0.0;

    _buttonStateWorker = ever<PlayButtonState>(
      playerController.buttonState,
      _syncAnimationWithButtonState,
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
    _buttonStateWorker.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GetX<PlayerController>(
      builder: (controller) {
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
