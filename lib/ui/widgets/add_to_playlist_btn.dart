import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/controller_providers.dart';
import 'add_to_playlist.dart';

class AddToPlaylistButton extends ConsumerWidget {
  const AddToPlaylistButton({
    super.key,
    this.calledFromPlayer = false,
    this.song,
  });
  final bool calledFromPlayer;
  final MediaItem? song;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerController = calledFromPlayer
        ? ref.read(playerControllerProvider)
        : null;
    return IconButton(
      icon: Icon(
        Icons.add_circle_outline,
        color: Theme.of(context).textTheme.titleMedium!.color,
      ),
      onPressed: () async {
        final currentSong = calledFromPlayer
            ? playerController!.currentSong.value
            : song;
        if (currentSong != null) {
          await showDialog(
            context: context,
            builder: (context) => AddToPlaylist([currentSong]),
          );
        }
      },
    );
  }
}
