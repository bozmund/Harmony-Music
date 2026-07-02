import 'dart:io';

import '/services/file_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/utils/get_localization.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/providers/repository_providers.dart';
import '../../services/app_platform_service.dart';
import '../../services/backup/restore_service.dart';
import '../../services/constant.dart';
import '../../utils/runtime_platform.dart';
import '/utils/helper.dart';
import '../../services/permission_service.dart';
import 'common_dialog_widget.dart';

class RestoreDialog extends ConsumerStatefulWidget {
  const RestoreDialog({super.key});

  @override
  ConsumerState<RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends ConsumerState<RestoreDialog> {
  late final RestoreDialogController restoreDialogController;

  @override
  void initState() {
    super.initState();
    restoreDialogController = RestoreDialogController(
      restoreService: RestoreService(
        downloadRepository: ref.read(downloadRepositoryProvider),
        libraryRepository: ref.read(libraryRepositoryProvider),
        playlistRepository: ref.read(playlistRepositoryProvider),
        playbackSessionRepository: ref.read(playbackSessionRepositoryProvider),
        settingsRepository: ref.read(settingsRepositoryProvider),
        storageAdminRepository: ref.read(storageAdminRepositoryProvider),
      ),
    );
  }

  @override
  void dispose() {
    restoreDialogController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      child: Container(
        height: 300,
        padding: const EdgeInsets.only(
          top: 20,
          bottom: 30,
          left: 20,
          right: 20,
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.only(bottom: 10.0, top: 10),
                  child: Text(
                    "restoreAppData".tr,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                SizedBox(
                  height: 150,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: restoreDialogController,
                      builder: (context, _) =>
                          restoreDialogController.restoreError.isNotEmpty
                          ? Text(
                              restoreDialogController.restoreError,
                              textAlign: TextAlign.center,
                            )
                          : restoreDialogController.restoreCompleted
                          ? Text("restoreMsg".tr, textAlign: TextAlign.center)
                          : restoreDialogController.processingFiles
                          ? Text("processFiles".tr)
                          : restoreDialogController.restoreRunning
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "${restoreDialogController.restoreProgress}/${restoreDialogController.filesToRestore}",
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 10),
                                Text("restoring".tr),
                              ],
                            )
                          : Text("letsStart".tr),
                    ),
                  ),
                ),
                SizedBox(
                  width: double.maxFinite,
                  child: Align(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).textTheme.titleLarge!.color,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: InkWell(
                        onTap: () async {
                          if (restoreDialogController.restoreCompleted) {
                            RuntimePlatform.isAndroid
                                ? await AppPlatformService.restartApp()
                                : exit(0);
                          } else {
                            await restoreDialogController.restore();
                          }
                        },
                        child: AnimatedBuilder(
                          animation: restoreDialogController,
                          builder: (context, _) => Visibility(
                            visible:
                                !restoreDialogController.processingFiles &&
                                !restoreDialogController.restoreRunning,
                            replacement: const SizedBox(height: 40),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15.0,
                                vertical: 10,
                              ),
                              child: Text(
                                restoreDialogController.restoreCompleted
                                    ? "restartApp".tr
                                    : "restore".tr,
                                style: TextStyle(
                                  color: Theme.of(context).canvasColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class RestoreDialogController extends ChangeNotifier {
  RestoreDialogController({required RestoreService restoreService})
    : _restoreService = restoreService;

  final RestoreService _restoreService;
  var restoreRunning = false;
  var restoreProgress = -1;
  var filesToRestore = 0;
  var processingFiles = false;
  var restoreError = "";

  bool get restoreCompleted =>
      restoreError.isEmpty && restoreProgress == filesToRestore;

  Future<void> restore() async {
    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    // Picked via file_picker rather than file_selector: file_selector's
    // Android implementation reads the whole picked file into a byte array
    // (with its size in a 32-bit int), so multi-gigabyte .hmb backups fail
    // inside the picker. file_picker only streams the document to a cache
    // file, which means restore transiently needs roughly twice the backup
    // size in free space on Android.
    final String? pickedFile = await FilePickerService.pickLargeFilePath(
      extensions: ['hmb'],
    );

    if (pickedFile == '/' || pickedFile == null) {
      return;
    }
    restoreError = "";
    restoreProgress = -1;
    filesToRestore = 0;
    processingFiles = true;
    notifyListeners();

    final restoreFilePath = pickedFile.toString();
    try {
      await _restoreService.restoreFromFile(
        restoreFilePath,
        onProgress: (progress) {
          processingFiles = false;
          restoreRunning = true;
          restoreProgress = progress.current;
          filesToRestore = progress.total;
          notifyListeners();
        },
      );
    } catch (e, stackTrace) {
      restoreError = "Restore failed: $e";
      printERROR("Error during restore: $e", tag: LogTags.backup);
      printERROR(stackTrace, tag: LogTags.backup);
    } finally {
      processingFiles = false;
      restoreRunning = false;
      await _deletePickerCacheCopy(restoreFilePath);
      notifyListeners();
    }
  }

  /// On Android the picker hands us a cached copy of the backup; delete it
  /// so a multi-gigabyte temp file doesn't linger. Never touches the real
  /// backup: only paths inside the app's own temp directory are removed.
  Future<void> _deletePickerCacheCopy(String pickedPath) async {
    try {
      final tempDirPath = (await getTemporaryDirectory()).path;
      if (!pickedPath.startsWith(tempDirPath)) return;
      final pickedFile = File(pickedPath);
      if (await pickedFile.exists()) {
        await pickedFile.delete();
      }
    } catch (e) {
      printWarning(
        "Could not delete picker cache copy: $e",
        tag: LogTags.backup,
      );
    }
  }
}
