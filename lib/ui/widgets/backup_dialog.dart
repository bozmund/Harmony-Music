import 'dart:io';

import '/services/file_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/utils/get_localization.dart';

import '../../app/providers/repository_providers.dart';
import '../../services/backup/backup_service.dart';
import '../../services/constant.dart';
import '../../utils/runtime_platform.dart';
import '/ui/widgets/loader.dart';
import '/utils/helper.dart';
import '../../services/permission_service.dart';
import 'common_dialog_widget.dart';

class BackupDialog extends ConsumerStatefulWidget {
  const BackupDialog({super.key});

  @override
  ConsumerState<BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends ConsumerState<BackupDialog> {
  late final BackupDialogController backupDialogController;

  @override
  void initState() {
    super.initState();
    backupDialogController = BackupDialogController(
      backupService: BackupService(
        downloadRepository: ref.read(downloadRepositoryProvider),
        playlistRepository: ref.read(playlistRepositoryProvider),
        settingsRepository: ref.read(settingsRepositoryProvider),
        storageAdminRepository: ref.read(storageAdminRepositoryProvider),
      ),
    );
  }

  @override
  void dispose() {
    backupDialogController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      child: Container(
        height: RuntimePlatform.isAndroid ? 400 : 350,
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
                    "backupAppData".tr,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 150,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: backupDialogController,
                            builder: (context, _) =>
                                (backupDialogController.scanning ||
                                    backupDialogController.backupRunning)
                                ? const LoadingIndicator()
                                : const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 10),
                          Column(
                            children: [
                              AnimatedBuilder(
                                animation: backupDialogController,
                                builder: (context, _) => Text(
                                  backupDialogController.statusText,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              AnimatedBuilder(
                                animation: backupDialogController,
                                builder: (context, _) =>
                                    backupDialogController
                                            .currentBackupFileName
                                            .isNotEmpty &&
                                        backupDialogController.backupRunning
                                    ? Padding(
                                        padding: const EdgeInsets.only(
                                          top: 6.0,
                                        ),
                                        child: Text(
                                          backupDialogController
                                              .currentBackupFileName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              if (RuntimePlatform.isAndroid)
                                AnimatedBuilder(
                                  animation: backupDialogController,
                                  builder: (context, _) =>
                                      backupDialogController
                                          .downloadedFilesSelected
                                      ? Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8.0,
                                          ),
                                          child: Text(
                                            "androidBackupWarning".tr,
                                            textAlign: TextAlign.center,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall!
                                                .copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!RuntimePlatform.isDesktop)
                  AnimatedBuilder(
                    animation: backupDialogController,
                    builder: (context, _) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Checkbox(
                            value:
                                backupDialogController.downloadedFilesSelected,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                            onChanged:
                                backupDialogController.scanning ||
                                    backupDialogController.backupRunning ||
                                    backupDialogController.backupCompleted
                                ? null
                                : (bool? value) {
                                    backupDialogController
                                        .setDownloadedFilesSelected(value!);
                                  },
                          ),
                          Text("includeDownloadedFiles".tr),
                        ],
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
                          if (backupDialogController.backupCompleted) {
                            Navigator.of(context).pop();
                          } else {
                            await backupDialogController.backup();
                          }
                        },
                        child: AnimatedBuilder(
                          animation: backupDialogController,
                          builder: (context, _) => Visibility(
                            visible:
                                !(backupDialogController.backupRunning ||
                                    backupDialogController.scanning),
                            replacement: const SizedBox(height: 40),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15.0,
                                vertical: 10,
                              ),
                              child: Text(
                                backupDialogController.backupCompleted
                                    ? "close".tr
                                    : "backup".tr,
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

class BackupDialogController extends ChangeNotifier {
  BackupDialogController({required BackupService backupService})
    : _backupService = backupService;

  final BackupService _backupService;
  var scanning = false;
  var backupCompleted = false;
  var backupRunning = false;
  var downloadedFilesSelected = false;
  var backupProgress = 0;
  var filesToBackup = 0;
  var currentBackupFileName = "";
  var backupError = "";

  String get statusText {
    if (backupError.isNotEmpty) {
      return backupError;
    }
    if (scanning) {
      return "scanning".tr;
    }
    if (backupRunning) {
      return "${"backupInProgress".tr}\n$backupProgress/$filesToBackup";
    }
    if (backupCompleted) {
      return "backupMsg".tr;
    }
    return "letsStart".tr;
  }

  void setDownloadedFilesSelected(bool value) {
    downloadedFilesSelected = value;
    notifyListeners();
  }

  Future<void> backup() async {
    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    final String? pickedFolderPath = await FilePickerService.getDirectoryPath(
      confirmButtonText: "Select backup file folder",
    );
    if (pickedFolderPath == '/' || pickedFolderPath == null) {
      return;
    }

    backupError = "";
    backupCompleted = false;
    backupProgress = 0;
    filesToBackup = 0;
    currentBackupFileName = "";
    notifyListeners();

    try {
      scanning = true;
      notifyListeners();
      final filesToExport = await _backupService.scanFilesToBackup(
        includeAudio: downloadedFilesSelected,
      );
      filesToBackup = filesToExport.length;
      scanning = false;
      notifyListeners();
      if (filesToExport.isEmpty) {
        throw StateError("No files to backup");
      }

      backupRunning = true;
      notifyListeners();
      final exportDirPath = pickedFolderPath.toString();
      final outputPath =
          '$exportDirPath/${DateTime.now().millisecondsSinceEpoch.toString()}.hmb';

      await _backupService.createBackup(filesToExport, outputPath, (progress) {
        backupProgress = progress.current;
        filesToBackup = progress.total;
        currentBackupFileName = progress.fileName;
        notifyListeners();
      });

      backupCompleted = true;
      notifyListeners();
      final outputFileSize = await File(outputPath).length();
      printINFO(
        "Backup saved to $outputPath ($outputFileSize bytes)",
        tag: LogTags.backup,
      );
    } catch (e, stackTrace) {
      backupError = "Backup failed";
      printERROR('Error during backup: $e', tag: LogTags.backup);
      printERROR(stackTrace, tag: LogTags.backup);
    } finally {
      scanning = false;
      backupRunning = false;
      notifyListeners();
    }
  }
}
