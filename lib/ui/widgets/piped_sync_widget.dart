import 'dart:async';

import 'package:flutter/material.dart';
import 'package:harmonymusic/utils/get_localization.dart';
import 'package:harmonymusic/utils/helper.dart';

import '../screens/Library/library_controller.dart';
import 'snackbar.dart';

class PipedSyncWidget extends StatelessWidget {
  const PipedSyncWidget({super.key, required this.padding});
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final libraryPlaylistController =
        LibraryPlaylistsControllerRegistry.current!;
    return Padding(
      padding: padding,
      child: RotationTransition(
        turns: Tween(
          begin: 0.0,
          end: 1.0,
        ).animate(libraryPlaylistController.controller),
        child: IconButton(
          splashRadius: 20,
          iconSize: 20,
          visualDensity: const VisualDensity(vertical: -4),
          icon: const Icon(Icons.sync), // <-- Icon
          onPressed: () async {
            try {
              await libraryPlaylistController.controller.forward();
              unawaited(libraryPlaylistController.controller.repeat());
              await libraryPlaylistController.syncPipedPlaylist();
              libraryPlaylistController.controller.stop();
              libraryPlaylistController.controller.reset();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                snackbar(
                  context,
                  "pipedPlaylistSyncAlert".tr,
                  size: SanckBarSize.MEDIUM,
                ),
              );
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  snackbar(
                    context,
                    "errorOccurredAlert".tr,
                    size: SanckBarSize.BIG,
                  ),
                );
              }
              printERROR(e);
            }
          },
        ),
      ),
    );
  }
}
