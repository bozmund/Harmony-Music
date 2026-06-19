import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:terminate_restart/terminate_restart.dart';

import '../../services/constant.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '/utils/helper.dart';
import '../../services/permission_service.dart';
import 'common_dialog_widget.dart';

class RestoreDialog extends StatelessWidget {
  const RestoreDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final restoreDialogController = Get.put(RestoreDialogController());
    return CommonDialog(
      child: Container(
        height: 300,
        padding:
            const EdgeInsets.only(top: 20, bottom: 30, left: 20, right: 20),
        child: Stack(
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
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
                  child: Obx(() => restoreDialogController
                          .restoreError.value.isNotEmpty
                      ? Text(
                          restoreDialogController.restoreError.value,
                          textAlign: TextAlign.center,
                        )
                      : restoreDialogController.restoreCompleted
                          ? Text(
                              "restoreMsg".tr,
                              textAlign: TextAlign.center,
                            )
                          : restoreDialogController.processingFiles.isTrue
                              ? Text("processFiles".tr)
                              : restoreDialogController.restoreRunning.isTrue
                                  ? Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                            "${restoreDialogController.restoreProgress.toInt()}/${restoreDialogController.filesToRestore.toInt()}",
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge),
                                        const SizedBox(
                                          height: 10,
                                        ),
                                        Text("restoring".tr)
                                      ],
                                    )
                                  : Text("letsStrart".tr)),
                ),
              ),
              SizedBox(
                width: double.maxFinite,
                child: Align(
                  child: Container(
                    decoration: BoxDecoration(
                        color: Theme.of(context).textTheme.titleLarge!.color,
                        borderRadius: BorderRadius.circular(10)),
                    child: InkWell(
                      onTap: () {
                        if (restoreDialogController.restoreCompleted) {
                          GetPlatform.isAndroid
                              ? TerminateRestart.instance.restartApp(
                                  options: const TerminateRestartOptions(
                                    terminate: true,
                                  ),
                                )
                              : exit(0);
                        } else {
                          restoreDialogController.restore();
                        }
                      },
                      child: Obx(
                        () => Visibility(
                          visible: restoreDialogController
                                  .processingFiles.isFalse &&
                              restoreDialogController.restoreRunning.isFalse,
                          replacement: const SizedBox(
                            height: 40,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 15.0, vertical: 10),
                            child: Obx(
                              () => Text(
                                restoreDialogController.restoreCompleted
                                    ? "restartApp".tr
                                    : "restore".tr,
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

class RestoreDialogController extends GetxController {
  final restoreRunning = false.obs;
  final restoreProgress = (-1).obs;
  final filesToRestore = (0).obs;
  final processingFiles = false.obs;
  final restoreError = "".obs;

  bool get restoreCompleted =>
      restoreError.value.isEmpty &&
      restoreProgress.toInt() == filesToRestore.toInt();

  Future<void> restore() async {
    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    final FilePickerResult? pickedFileResult = await FilePicker.platform
        .pickFiles(
            dialogTitle: "Select backup file",
            type: GetPlatform.isWindows ? FileType.custom : FileType.any,
            allowedExtensions: GetPlatform.isWindows ? ['hmb'] : null,
            allowMultiple: false);

    final String? pickedFile = pickedFileResult?.files.first.path;

    // is this check necessary?
    if (pickedFile == '/' || pickedFile == null) {
      return;
    }
    restoreError.value = "";
    restoreProgress.value = -1;
    filesToRestore.value = 0;
    processingFiles.value = true;

    final restoreFilePath = pickedFile.toString();
    final supportDirPath = Get.find<SettingsScreenController>().supportDirPath;
    final dbDirPath = await Get.find<SettingsScreenController>().dbDir;
    final Directory dbDir = Directory(dbDirPath);
    printInfo(info: dbDir.path);

    InputFileStream? input;
    Archive? archive;
    try {
      await Get.find<SettingsScreenController>().closeAllDatabases();

      // Delete all restored database files before writing the backup copy.
      for (final file in dbDir.listSync()) {
        if (file is File && file.path.endsWith('.hive')) {
          await file.delete();
        }
      }

      input = InputFileStream(restoreFilePath);
      archive = ZipDecoder().decodeBuffer(input);
      filesToRestore.value = archive.files.where((file) => file.isFile).length;
      restoreProgress.value = 0;
      processingFiles.value = false;
      restoreRunning.value = true;

      for (final file in archive) {
        if (!file.isFile) continue;

        final filename = _safeArchiveFileName(file.name);
        if (filename == null) {
          printWarning("Skipping invalid restore entry: ${file.name}",
              tag: LogTags.backup);
          continue;
        }

        printINFO("Restoring $filename", tag: LogTags.backup);
        final targetFileDir = _restoreTargetDir(
          filename,
          supportDirPath,
          dbDirPath,
        );
        final outputFile = File('$targetFileDir/$filename');
        await outputFile.parent.create(recursive: true);
        await _writeArchiveFileToDisk(file, outputFile.path);
        restoreProgress.value++;
      }

      // Clear file picker temp directory
      final tempFilePickerDirPath =
          "${(await getApplicationCacheDirectory()).path}/file_picker";
      final tempFilePickerDir = Directory(tempFilePickerDirPath);
      if (tempFilePickerDir.existsSync()) {
        await tempFilePickerDir.delete(recursive: true);
      }

      // Change file download path to support dir path in songs if system is Windows or Linux.
      if (GetPlatform.isWindows || GetPlatform.isLinux) {
        final newSongBox = await Hive.openBox(BoxNames.songDownloads);
        final downloadedSongs = newSongBox.values.toList();
        for (final song in downloadedSongs) {
          final songPath = song["url"];
          if (songPath != null && songPath is String) {
            final fileName = songPath.split("/").last;
            final newFilePath = "$supportDirPath/Music/$fileName";
            song["url"] = newFilePath;
            song['streamInfo'][1]['url'] = newFilePath;
            await newSongBox.put(song["videoId"], song);
          }
        }
      }
    } catch (e, stackTrace) {
      restoreError.value = "Restore failed";
      printERROR("Error during restore: $e", tag: LogTags.backup);
      printERROR(stackTrace, tag: LogTags.backup);
    } finally {
      processingFiles.value = false;
      restoreRunning.value = false;
      await archive?.clear();
      await input?.close();
    }
  }
}

String? _safeArchiveFileName(String archiveName) {
  final normalizedName = archiveName.replaceAll('\\', '/');
  final parts =
      normalizedName.split('/').where((part) => part.isNotEmpty).toList();
  final fileName = parts.isEmpty ? null : parts.last;
  if (fileName == null || fileName == '.' || fileName == '..') {
    return null;
  }
  return fileName;
}

String _restoreTargetDir(
  String filename,
  String supportDirPath,
  String dbDirPath,
) {
  final lowerFilename = filename.toLowerCase();
  if (lowerFilename.endsWith(".m4a") || lowerFilename.endsWith(".opus")) {
    return "$supportDirPath/Music";
  }
  if (lowerFilename.endsWith(".png")) {
    return "$supportDirPath/thumbnails";
  }
  return dbDirPath;
}

Future<void> _writeArchiveFileToDisk(
    ArchiveFile file, String outputFilePath) async {
  final output = OutputFileStream(outputFilePath);
  try {
    final rawContent = file.rawContent;
    if (rawContent == null) {
      file.writeContent(output);
      return;
    }

    if (file.compressionType == ArchiveFile.DEFLATE) {
      Inflate.stream(rawContent, output);
    } else if (file.compressionType == ArchiveFile.STORE) {
      output.writeInputStream(rawContent);
    } else {
      file.writeContent(output);
    }
  } finally {
    await output.close();
  }
}
