import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../services/constant.dart';
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
                                backupDialogController.statusText,
                                textAlign: TextAlign.center,
                              )),
                          Obx(() => backupDialogController
                                      .currentBackupFileName.value.isNotEmpty &&
                                  backupDialogController.backupRunning.isTrue
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 6.0),
                                  child: Text(
                                    backupDialogController
                                        .currentBackupFileName.value,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                )
                              : const SizedBox.shrink()),
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
  final isDownloadedfilesSeclected = false.obs;
  final backupProgress = 0.obs;
  final filesToBackup = 0.obs;
  final currentBackupFileName = "".obs;
  final backupError = "".obs;
  List<String> filesToExport = [];
  final supportDirPath = Get.find<SettingsScreenController>().supportDirPath;

  String get statusText {
    if (backupError.value.isNotEmpty) {
      return backupError.value;
    }
    if (scanning.isTrue) {
      return "scanning".tr;
    }
    if (backupRunning.isTrue) {
      return "${"backupInProgress".tr}\n${backupProgress.value}/${filesToBackup.value}";
    }
    if (isbackupCompleted.isTrue) {
      return "backupMsg".tr;
    }
    return "letsStrart".tr;
  }

  Future<void> scanFilesToBackup() async {
    filesToExport = [];
    final seenPaths = <String>{};
    var totalBackupBytes = 0;

    void addIfValid(String? path) {
      final normalizedPath = _normalizeFilePath(path);
      if (normalizedPath == null || normalizedPath.isEmpty) return;
      final file = File(normalizedPath);
      if (!file.existsSync()) {
        printWarning("Skipping missing backup file: $normalizedPath",
            tag: LogTags.backup);
        return;
      }
      final absolutePath = file.absolute.path;
      if (seenPaths.add(absolutePath)) {
        final fileLength = file.lengthSync();
        filesToExport.add(absolutePath);
        totalBackupBytes += fileLength;
      }
    }

    await _flushOpenBackupBoxes();

    final dbDir = await Get.find<SettingsScreenController>().dbDir;
    for (final filePath in await processDirectoryInIsolate(dbDir)) {
      addIfValid(filePath);
    }

    if (isDownloadedfilesSeclected.value) {
      final downlodedSongFilePaths = Hive.box(BoxNames.songDownloads)
          .values
          .map<String?>((data) => data['url']?.toString())
          .toList();
      for (final filePath in downlodedSongFilePaths) {
        addIfValid(filePath);
      }
      try {
        for (final filePath in await processDirectoryInIsolate(
            "$supportDirPath/thumbnails",
            extensionFilter: ".png")) {
          addIfValid(filePath);
        }
      } catch (e) {
        printERROR(e, tag: LogTags.backup);
      }
    }

    filesToBackup.value = filesToExport.length;
    printINFO(
        "Found ${filesToExport.length} files for backup (${totalBackupBytes} bytes)",
        tag: LogTags.backup);
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

    backupError.value = "";
    isbackupCompleted.value = false;
    backupProgress.value = 0;
    filesToBackup.value = 0;
    currentBackupFileName.value = "";

    try {
      scanning.value = true;
      await scanFilesToBackup();
      scanning.value = false;
      if (filesToExport.isEmpty) {
        throw StateError("No files to backup");
      }

      backupRunning.value = true;
      final exportDirPath = pickedFolderPath.toString();
      final outputPath =
          '$exportDirPath/${DateTime.now().millisecondsSinceEpoch.toString()}.hmb';

      await compressFilesInBackground(filesToExport, outputPath, (progress) {
        backupProgress.value = progress.current;
        filesToBackup.value = progress.total;
        currentBackupFileName.value = progress.fileName;
      });

      isbackupCompleted.value = true;
      final outputFileSize = await File(outputPath).length();
      printINFO("Backup saved to $outputPath ($outputFileSize bytes)",
          tag: LogTags.backup);
    } catch (e, stackTrace) {
      backupError.value = "Backup failed";
      printERROR('Error during backup: $e', tag: LogTags.backup);
      printERROR(stackTrace, tag: LogTags.backup);
    } finally {
      scanning.value = false;
      backupRunning.value = false;
    }
  }
}

Future<void> _flushOpenBackupBoxes() async {
  for (final boxName in [
    BoxNames.songsCache,
    BoxNames.songDownloads,
    BoxNames.songsUrlCache,
    BoxNames.appPrefs,
    BoxNames.homeScreenData,
    BoxNames.prevSessionData,
    BoxNames.libFav,
    BoxNames.libRP,
    BoxNames.libraryPlaylists,
    BoxNames.libraryAlbums,
    BoxNames.libraryArtists,
    BoxNames.librarySearches,
  ]) {
    if (Hive.isBoxOpen(boxName)) {
      await Hive.box(boxName).flush();
    }
  }
}

class BackupProgress {
  const BackupProgress({
    required this.current,
    required this.total,
    required this.fileName,
  });

  final int current;
  final int total;
  final String fileName;
}

typedef BackupProgressCallback = void Function(BackupProgress progress);

Future<void> compressFilesInBackground(List<String> filePaths,
    String zipFilePath, BackupProgressCallback onProgress) async {
  final encoder = ZipFileEncoder();
  final usedArchiveNames = <String>{};

  encoder.create(zipFilePath);
  try {
    for (var i = 0; i < filePaths.length; i++) {
      final file = File(filePaths[i]);
      if (!await file.exists()) {
        printWarning("Skipping missing backup file: ${file.path}",
            tag: LogTags.backup);
        continue;
      }

      final archiveName = _uniqueArchiveName(file.path, usedArchiveNames);
      final level = _shouldStoreWithoutCompression(file.path)
          ? ZipFileEncoder.STORE
          : ZipFileEncoder.GZIP;
      onProgress(BackupProgress(
          current: i + 1, total: filePaths.length, fileName: archiveName));
      printINFO("Adding $archiveName to backup (${i + 1}/${filePaths.length})",
          tag: LogTags.backup);
      try {
        await encoder.addFile(file, archiveName, level);
      } catch (e) {
        if (!await file.exists()) {
          printWarning("Skipping removed backup file: ${file.path}",
              tag: LogTags.backup);
          continue;
        }
        rethrow;
      }
    }
  } finally {
    await encoder.close();
  }
}

String? _normalizeFilePath(String? path) {
  if (path == null) return null;
  final trimmedPath = path.trim();
  if (trimmedPath.startsWith("file://")) {
    return Uri.parse(trimmedPath).toFilePath();
  }
  return trimmedPath;
}

bool _shouldStoreWithoutCompression(String path) {
  final lowerPath = path.toLowerCase();
  return lowerPath.endsWith(".m4a") ||
      lowerPath.endsWith(".opus") ||
      lowerPath.endsWith(".png");
}

String _uniqueArchiveName(String filePath, Set<String> usedArchiveNames) {
  final fileName = filePath.split(RegExp(r'[\\/]')).last;
  if (usedArchiveNames.add(fileName)) return fileName;

  final extensionIndex = fileName.lastIndexOf('.');
  final baseName =
      extensionIndex == -1 ? fileName : fileName.substring(0, extensionIndex);
  final extension =
      extensionIndex == -1 ? "" : fileName.substring(extensionIndex);
  var counter = 2;
  while (true) {
    final candidate = "$baseName ($counter)$extension";
    if (usedArchiveNames.add(candidate)) return candidate;
    counter++;
  }
}

Future<List<String>> processDirectoryInIsolate(String dbDir,
    {String extensionFilter = ".hive"}) async {
  // Use Isolate.run to execute the function in a new isolate
  return await Isolate.run(() async {
    final dir = Directory(dbDir);
    if (!dir.existsSync()) return <String>[];

    // List files in the directory
    final filesEntityList = await dir.list(recursive: false).toList();

    // Filter out .hive files
    final filesPath = filesEntityList
        .whereType<File>() // Ensure we only work with files
        .map((entity) {
          if (extensionFilter.isEmpty ||
              entity.path.endsWith(extensionFilter)) {
            return entity.path;
          }
        })
        .whereType<String>()
        .toList();

    return filesPath;
  });
}
