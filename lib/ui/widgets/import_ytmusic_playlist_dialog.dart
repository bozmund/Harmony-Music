import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../screens/Library/library_controller.dart';
import 'common_dialog_widget.dart';
import 'modified_text_field.dart';

class ImportYtMusicPlaylistDialogController extends GetxController {
  final inputController = TextEditingController();
  final isImporting = false.obs;
  final status = "Paste a public YouTube Music playlist URL or ID".obs;
  final error = RxnString();
  final result = Rxn<YouTubePlaylistImportResult>();

  Future<void> importPlaylist() async {
    if (isImporting.value) return;

    error.value = null;
    result.value = null;
    isImporting.value = true;

    try {
      result.value = await Get.find<LibraryPlaylistsController>()
          .importPlaylistFromYouTubeMusic(
        inputController.text,
        onStatus: (value) => status.value = value,
      );
      status.value = "Completed";
    } on YouTubePlaylistImportException catch (e) {
      error.value = e.message;
      status.value = "Import failed";
    } catch (e) {
      error.value = "Network error or playlist unavailable";
      status.value = "Import failed";
    } finally {
      isImporting.value = false;
    }
  }

  @override
  void onClose() {
    inputController.dispose();
    super.onClose();
  }
}

class ImportYtMusicPlaylistDialog extends StatelessWidget {
  const ImportYtMusicPlaylistDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<ImportYtMusicPlaylistDialogController>()
        ? Get.find<ImportYtMusicPlaylistDialogController>()
        : Get.put(ImportYtMusicPlaylistDialogController());

    return CommonDialog(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Obx(
          () => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Import YouTube Music playlist",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              ModifiedTextField(
                controller: controller.inputController,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => controller.importPlaylist(),
                decoration: const InputDecoration(
                  labelText: "Playlist URL or ID",
                  hintText: "https://music.youtube.com/playlist?list=...",
                ),
              ),
              const SizedBox(height: 14),
              Text(
                controller.status.value,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (controller.isImporting.value) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (controller.error.value != null) ...[
                const SizedBox(height: 12),
                Text(
                  controller.error.value!,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (controller.result.value != null) ...[
                const SizedBox(height: 12),
                Text(
                  "${controller.result.value!.importedSongCount} songs imported\n"
                  "${controller.result.value!.conflictAddedCount} conflicts added to Import conflicts",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        controller.isImporting.value ? null : () => Get.back(),
                    child: Text(
                        controller.result.value == null ? "Cancel" : "Close"),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: controller.isImporting.value
                        ? null
                        : controller.importPlaylist,
                    child: const Text("Import"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
