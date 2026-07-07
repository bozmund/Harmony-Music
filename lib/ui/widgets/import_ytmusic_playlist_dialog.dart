import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/controller_providers.dart';
import '../screens/Library/library_controller.dart';
import 'common_dialog_widget.dart';
import 'modified_text_field.dart';

class ImportYtMusicPlaylistDialogController extends ChangeNotifier {
  ImportYtMusicPlaylistDialogController(this._libraryPlaylistsController);

  final LibraryPlaylistsController _libraryPlaylistsController;
  final inputController = TextEditingController();
  var isImporting = false;
  var status = "Paste a public YouTube Music playlist URL or ID";
  String? error;
  YouTubePlaylistImportResult? result;

  Future<void> importPlaylist() async {
    if (isImporting) return;

    error = null;
    result = null;
    isImporting = true;
    notifyListeners();

    try {
      result = await _libraryPlaylistsController.importPlaylistFromYouTubeMusic(
        inputController.text,
        onStatus: (value) {
          status = value;
          notifyListeners();
        },
      );
      status = "Completed";
    } on YouTubePlaylistImportException catch (e) {
      error = e.message;
      status = "Import failed";
    } catch (e) {
      error = "Network error or playlist unavailable";
      status = "Import failed";
    } finally {
      isImporting = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    inputController.dispose();
    super.dispose();
  }
}

class ImportYtMusicPlaylistDialog extends ConsumerStatefulWidget {
  const ImportYtMusicPlaylistDialog({super.key});

  @override
  ConsumerState<ImportYtMusicPlaylistDialog> createState() =>
      _ImportYtMusicPlaylistDialogState();
}

class _ImportYtMusicPlaylistDialogState
    extends ConsumerState<ImportYtMusicPlaylistDialog> {
  late final ImportYtMusicPlaylistDialogController controller;

  @override
  void initState() {
    super.initState();
    controller = ImportYtMusicPlaylistDialogController(
      ref.read(libraryPlaylistsControllerProvider),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => Column(
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
                controller.status,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (controller.isImporting) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (controller.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  controller.error!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              if (controller.result != null) ...[
                const SizedBox(height: 12),
                Text(
                  "${controller.result!.importedSongCount} songs imported\n"
                  "${controller.result!.conflictAddedCount} conflicts added to Import conflicts",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: controller.isImporting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(controller.result == null ? "Cancel" : "Close"),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: controller.isImporting
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
