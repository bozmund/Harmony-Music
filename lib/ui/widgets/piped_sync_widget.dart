import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/utils/helper.dart';

import '../screens/Library/library_controller.dart';
import 'snackbar.dart';

class PipedSyncWidget extends StatelessWidget {
  const PipedSyncWidget({super.key, required this.padding});
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final libraryPlaylistController = Get.find<LibraryPlaylistsController>();
    return Padding(
      padding: padding,
      child: RotationTransition(
        turns: Tween(begin: 0.0, end: 1.0).animate(libraryPlaylistController.controller),
        child: IconButton(
            splashRadius: 20,
            iconSize: 20,
            visualDensity: const VisualDensity(vertical: -4),
            icon: const Icon(
              Icons.sync,
            ), // <-- Icon
            onPressed: () async {
              try {
                await libraryPlaylistController.controller.forward();
                unawaited(libraryPlaylistController.controller.repeat());
                await libraryPlaylistController.syncPipedPlaylist();
                libraryPlaylistController.controller.stop();
                libraryPlaylistController.controller.reset();
                ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
                    Get.context!, "pipedPlaylistSyncAlert".tr,
                    size: SanckBarSize.MEDIUM));
              } catch (e) {
                ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
                    Get.context!, "errorOccurredAlert".tr,
                    size: SanckBarSize.BIG));
                printERROR(e);
              }
            }),
      ),
    );
  }
}
