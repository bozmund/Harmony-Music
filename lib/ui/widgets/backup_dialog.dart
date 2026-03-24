import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/services/constant.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '/ui/widgets/loader.dart';
import '/utils/helper.dart';
import '../../services/permission_service.dart';
import 'common_dialog_widget.dart';

class BackupDialog extends StatelessWidget {
  const BackupDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final backupDialogController = Get.put(BackupDialogController());
    return CommonDialog(
      child: Container(
        height: GetPlatform.isAndroid ? 400 : 350,
        padding:
            const EdgeInsets.only(top: 20, bottom: 30, left: 20, right: 20),
        child: Stack(
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
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
                      Obx(() => (backupDialogController.scanning.isTrue ||
                              backupDialogController.backupRunning.isTrue)
                          ? const LoadingIndicator()
                          : const SizedBox.shrink()),
                      const SizedBox(
                        height: 10,
                      ),
                      Column(
                        children: [
                          Obx(() => Text(
                                backupDialogController.scanning.isTrue
                                    ? "scanning".tr
                                    : backupDialogController
                                            .isFinalizing.isTrue
                                        ? "finalizingBackup".tr
                                        : backupDialogController
                                                .backupRunning.isTrue
                                            ? "backupInProgress".tr
                                            : backupDialogController
                                                    .isbackupCompleted.isTrue
                                                ? "backupMsg".tr
                                                : "letsStrart".tr,
                                textAlign: TextAlign.center,
                              )),
                          const SizedBox(height: 10),
                          Obx(() => Visibility(
                                visible: backupDialogController
                                    .backupRunning.isTrue,
                                child: Column(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: LinearProgressIndicator(
                                        value: backupDialogController
                                            .backupProgress.value,
                                        backgroundColor: Theme.of(context)
                                            .dividerColor
                                            .withOpacity(0.1),
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Theme.of(context).primaryColor),
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      "${backupDialogController.processedCount.value} / ${backupDialogController.totalFilesCount.value}",
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                    Text(
                                      backupDialogController
                                          .currentFileName.value,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall!
                                          .copyWith(
                                              color: Theme.of(context)
                                                  .hintColor),
                                    ),
                                  ],
                                ),
                              )),
                          if (GetPlatform.isAndroid)
                            Obx(() => (backupDialogController
                                    .isDownloadedfilesSeclected.isTrue)
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(
                                      "androidBackupWarning".tr,
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall!
                                          .copyWith(
                                              fontWeight: FontWeight.bold),
                                    ),
                                  )
                                : const SizedBox.shrink())
                        ],
                      )
                    ],
                  )),
                ),
              ),
              if (!GetPlatform.isDesktop)
                Obx(() => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Checkbox(
                              value: backupDialogController
                                  .isDownloadedfilesSeclected.value,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(5)),
                              onChanged:
                                  backupDialogController.scanning.isTrue ||
                                          backupDialogController
                                              .backupRunning.isTrue ||
                                          backupDialogController
                                              .isbackupCompleted.isTrue
                                      ? null
                                      : (bool? value) {
                                          backupDialogController
                                              .isDownloadedfilesSeclected
                                              .value = value!;
                                        },
                            ),
                            Text("includeDownloadedFiles".tr),
                          ]),
                    )),
              SizedBox(
                width: double.maxFinite,
                child: Align(
                  child: Container(
                    decoration: BoxDecoration(
                        color: Theme.of(context).textTheme.titleLarge!.color,
                        borderRadius: BorderRadius.circular(10)),
                    child: InkWell(
                      onTap: () {
                        if (backupDialogController.isbackupCompleted.isTrue) {
                          Navigator.of(context).pop();
                        } else {
                          backupDialogController.backup();
                        }
                      },
                      child: Obx(
                        () => Visibility(
                          visible:
                              !(backupDialogController.backupRunning.isTrue ||
                                  backupDialogController.scanning.isTrue),
                          replacement: const SizedBox(
                            height: 40,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 15.0, vertical: 10),
                            child: Obx(
                              () => Text(
                                backupDialogController.isbackupCompleted.isTrue
                                    ? "close".tr
                                    : "backup".tr,
                                style: TextStyle(
                                    color: Theme.of(context).canvasColor),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class BackupDialogController extends GetxController {
  final scanning = false.obs;
  final isbackupCompleted = false.obs;
  final backupRunning = false.obs;
  final isFinalizing = false.obs;
  final isDownloadedfilesSeclected = false.obs;
  final backupProgress = 0.0.obs;
  final currentFileName = "".obs;
  final processedCount = 0.obs;
  final totalFilesCount = 0.obs;

  List<String> filesToExport = [];
  final supportDirPath = Get.find<SettingsScreenController>().supportDirPath;

  Future<void> scanFilesToBackup() async {
    final dbDir = await Get.find<SettingsScreenController>().dbDir;
    filesToExport.clear();
    filesToExport.addAll(await processDirectoryInIsolate(dbDir));
    if (isDownloadedfilesSeclected.value) {
      List<String> downlodedSongFilePaths = Hive.box(BoxNames.songDownloads)
          .values
          .map<String>((data) => data['url'])
          .toList();
      filesToExport.addAll(downlodedSongFilePaths);
      try {
        filesToExport.addAll(await processDirectoryInIsolate(
            "$supportDirPath/Music",
            extensionFilter: "")); // Include all music files
        filesToExport.addAll(await processDirectoryInIsolate(
            "$supportDirPath/thumbnails",
            extensionFilter: ".png"));
      } catch (e) {
        printERROR(e, tag: LogTags.backup);
      }
    }
    // Remove duplicates and non-existent files
    filesToExport = filesToExport.toSet().where((path) => File(path).existsSync()).toList();
    totalFilesCount.value = filesToExport.length;
  }

  Future<void> backup() async {
    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    final String? pickedFolderPath = await FilePicker.platform
        .getDirectoryPath(dialogTitle: "Select backup file folder");
    if (pickedFolderPath == '/' || pickedFolderPath == null) {
      return;
    }

    scanning.value = true;
    await scanFilesToBackup();
    scanning.value = false;

    if (filesToExport.isEmpty) {
      printERROR("No files to backup", tag: LogTags.backup);
      return;
    }

    backupRunning.value = true;
    isFinalizing.value = false;
    backupProgress.value = 0.0;
    processedCount.value = 0;
    
    final exportDirPath = pickedFolderPath.toString();
    final zipFilePath = '$exportDirPath/${DateTime.now().millisecondsSinceEpoch.toString()}.hmb';

    try {
      final receivePort = ReceivePort();
      await Isolate.spawn(_compressFilesIsolate, {
        'filePaths': filesToExport,
        'zipFilePath': zipFilePath,
        'sendPort': receivePort.sendPort,
      });

      await for (final message in receivePort) {
        if (message is Map) {
          processedCount.value = message['index'] + 1;
          currentFileName.value = message['fileName'];
          backupProgress.value = (message['index'] + 1) / filesToExport.length;
        } else if (message == 'finalizing') {
          isFinalizing.value = true;
        } else if (message == 'done') {
          receivePort.close();
          backupRunning.value = false;
          isFinalizing.value = false;
          isbackupCompleted.value = true;
          break;
        } else if (message is String && message.startsWith('error:')) {
          receivePort.close();
          backupRunning.value = false;
          isFinalizing.value = false;
          printERROR(message, tag: LogTags.backup);
          break;
        }
      }
    } catch (e) {
      backupRunning.value = false;
      isFinalizing.value = false;
      printERROR('Error during backup: $e', tag: LogTags.backup);
    }
  }
}

void _compressFilesIsolate(Map<String, dynamic> params) async {
  final List<String> filePaths = params['filePaths'];
  final String zipFilePath = params['zipFilePath'];
  final SendPort sendPort = params['sendPort'];

  try {
    final archive = Archive();
    final encoder = ZipEncoder();
    final zipFile = File(zipFilePath);
    
    // We use a custom stream-like approach by adding files one by one to the archive
    // and encoding at the end, but to be truly memory efficient with 'archive' library,
    // we should ideally use a library that supports streaming directly to disk.
    // For now, we optimize by ensuring we don't pre-load all bytes in the main thread.
    
    for (int i = 0; i < filePaths.length; i++) {
      final path = filePaths[i];
      final file = File(path);
      if (file.existsSync()) {
        final fileName = path.split(Platform.isWindows ? '\\' : '/').last;
        final fileData = file.readAsBytesSync();
        archive.addFile(ArchiveFile(fileName, fileData.length, fileData));
        
        // Notify progress
        sendPort.send({
          'index': i,
          'fileName': fileName,
        });
      }
    }

    sendPort.send('finalizing');

    final encodedArchive = encoder.encode(archive);
    if (encodedArchive != null) {
      zipFile.writeAsBytesSync(encodedArchive);
    }
    sendPort.send('done');
  } catch (e) {
    sendPort.send('error: $e');
  }
}

Future<List<String>> processDirectoryInIsolate(String dbDir,
    {String extensionFilter = ".hive"}) async {
  return await Isolate.run(() async {
    final dir = Directory(dbDir);
    if (!dir.existsSync()) return <String>[];
    
    final filesEntityList =
        await dir.list(recursive: false).toList();

    final filesPath = filesEntityList
        .whereType<File>()
        .map((entity) {
          if (extensionFilter.isEmpty || entity.path.endsWith(extensionFilter)) {
            return entity.path;
          }
          return null;
        })
        .whereType<String>()
        .toList();

    return filesPath;
  });
}
