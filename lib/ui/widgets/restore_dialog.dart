import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_selector/file_selector.dart';
import '/services/file_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../services/app_platform_service.dart';
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
                    child: Obx(
                      () =>
                          restoreDialogController.restoreError.value.isNotEmpty
                          ? Text(
                              restoreDialogController.restoreError.value,
                              textAlign: TextAlign.center,
                            )
                          : restoreDialogController.restoreCompleted
                          ? Text("restoreMsg".tr, textAlign: TextAlign.center)
                          : restoreDialogController.processingFiles.isTrue
                          ? Text("processFiles".tr)
                          : restoreDialogController.restoreRunning.isTrue
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "${restoreDialogController.restoreProgress.toInt()}/${restoreDialogController.filesToRestore.toInt()}",
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
                            GetPlatform.isAndroid
                                ? await AppPlatformService.restartApp()
                                : exit(0);
                          } else {
                            await restoreDialogController.restore();
                          }
                        },
                        child: Obx(
                          () => Visibility(
                            visible:
                                restoreDialogController
                                    .processingFiles
                                    .isFalse &&
                                restoreDialogController.restoreRunning.isFalse,
                            replacement: const SizedBox(height: 40),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15.0,
                                vertical: 10,
                              ),
                              child: Obx(
                                () => Text(
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
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class RestoreDialogController extends GetxController {
  final restoreRunning = false.obs;
  final restoreProgress = (-1).obs;
  final filesToRestore = 0.obs;
  final processingFiles = false.obs;
  final restoreError = "".obs;

  bool get restoreCompleted =>
      restoreError.value.isEmpty &&
      restoreProgress.toInt() == filesToRestore.toInt();

  Future<void> restore() async {
    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    final pickedFileResult = await FilePickerService.openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Harmony backup', extensions: ['hmb']),
      ],
      confirmButtonText: "Select backup file",
    );

    final String? pickedFile = pickedFileResult?.path;

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
      archive = ZipDecoder().decodeStream(input);
      filesToRestore.value = archive.files.where((file) => file.isFile).length;
      restoreProgress.value = 0;
      processingFiles.value = false;
      restoreRunning.value = true;

      for (final file in archive) {
        if (!file.isFile) continue;

        final filename = _safeArchiveFileName(file.name);
        if (filename == null) {
          printWarning(
            "Skipping invalid restore entry: ${file.name}",
            tag: LogTags.backup,
          );
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

      await rewriteRestoredDownloadPaths(supportDirPath: supportDirPath);
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

Future<void> rewriteRestoredDownloadPaths({
  required String supportDirPath,
}) async {
  final newSongBox = await Hive.openBox(BoxNames.songDownloads);
  for (final key in newSongBox.keys.toList()) {
    final rewrittenSong = rewriteRestoredDownloadSong(
      newSongBox.get(key),
      supportDirPath,
    );

    if (rewrittenSong == null) {
      await newSongBox.delete(key);
    } else {
      await newSongBox.put(key, rewrittenSong);
    }
  }
  await newSongBox.flush();
}

Map<dynamic, dynamic>? rewriteRestoredDownloadSong(
  dynamic song,
  String supportDirPath, {
  bool Function(String path)? fileExists,
}) {
  if (song is! Map) return null;

  final updatedSong = Map<dynamic, dynamic>.from(song);
  final originalPath = restoredDownloadPathFromSong(updatedSong);
  final fileName = restoredFileName(originalPath);
  if (fileName == null) return null;

  final exists = fileExists ?? ((path) => File(path).existsSync());
  final restoredPath = "$supportDirPath/Music/$fileName";
  final usablePath = exists(restoredPath)
      ? restoredPath
      : originalPath != null && exists(originalPath)
      ? originalPath
      : null;

  if (usablePath == null) {
    printWarning(
      "Skipping restored download with missing file: $fileName",
      tag: LogTags.backup,
    );
    return null;
  }

  updatedSong["url"] = usablePath;
  final streamInfo = updatedSong["streamInfo"];
  if (streamInfo is List && streamInfo.length > 1 && streamInfo[1] is Map) {
    final streamInfoData = Map<dynamic, dynamic>.from(streamInfo[1]);
    streamInfoData["url"] = usablePath;
    final updatedStreamInfo = List<dynamic>.from(streamInfo);
    updatedStreamInfo[1] = streamInfoData;
    updatedSong["streamInfo"] = updatedStreamInfo;
  }

  return updatedSong;
}

String? restoredDownloadPathFromSong(Map<dynamic, dynamic> song) {
  final topLevelPath = normalizeRestoredFilePath(song["url"]);
  if (topLevelPath != null) return topLevelPath;

  final streamInfo = song["streamInfo"];
  if (streamInfo is List && streamInfo.length > 1 && streamInfo[1] is Map) {
    return normalizeRestoredFilePath(streamInfo[1]["url"]);
  }

  return null;
}

String? normalizeRestoredFilePath(dynamic value) {
  if (value is! String || value.trim().isEmpty) return null;

  final path = value.trim();
  if (path.startsWith("file://")) {
    return Uri.parse(path).toFilePath();
  }
  return path;
}

String? restoredFileName(String? path) {
  if (path == null || path.isEmpty) return null;

  final fileName = path.split(RegExp(r'[\\/]')).last;
  if (fileName.isEmpty || fileName == "." || fileName == "..") {
    return null;
  }
  return fileName;
}

String? _safeArchiveFileName(String archiveName) {
  final normalizedName = archiveName.replaceAll('\\', '/');
  final parts = normalizedName
      .split('/')
      .where((part) => part.isNotEmpty)
      .toList();
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
  ArchiveFile file,
  String outputFilePath,
) async {
  final output = OutputFileStream(outputFilePath);
  try {
    file.writeContent(output);
  } finally {
    await output.close();
  }
}
