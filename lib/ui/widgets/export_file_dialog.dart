import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/l10n/l10n.dart';
import 'package:harmonymusic/ui/widgets/loader.dart';

import '../../app/providers/controller_providers.dart';
import '../../services/permission_service.dart';
import '../screens/Settings/settings_screen_controller.dart';
import 'common_dialog_widget.dart';

class ExportFileDialog extends ConsumerStatefulWidget {
  const ExportFileDialog({super.key});

  @override
  ConsumerState<ExportFileDialog> createState() => _ExportFileDialogState();
}

class _ExportFileDialogState extends ConsumerState<ExportFileDialog> {
  late final ExportFileDialogController exportFileDialogController;

  @override
  void initState() {
    super.initState();
    exportFileDialogController = ExportFileDialogController(
      settingsScreenController: ref.read(settingsScreenControllerProvider),
    );
  }

  @override
  void dispose() {
    exportFileDialogController.dispose();
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
                    context.l10n.exportDownloadedFiles,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                SizedBox(
                  height: 150,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: exportFileDialogController,
                      builder: (context, _) =>
                          exportFileDialogController.exportProgress ==
                              exportFileDialogController.filesToExport.length
                          ? Text(context.l10n.exportMsg)
                          : exportFileDialogController.exportRunning
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "${exportFileDialogController.exportProgress}/${exportFileDialogController.filesToExport.length}",
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 10),
                                Text(context.l10n.exporting),
                              ],
                            )
                          : exportFileDialogController.ready
                          ? Text(
                              "${exportFileDialogController.filesToExport.length} ${context.l10n.downFilesFound}",
                            )
                          : exportFileDialogController.scanning
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const LoadingIndicator(),
                                const SizedBox(height: 10),
                                Text(context.l10n.scanning),
                              ],
                            )
                          : const SizedBox(),
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
                          if (exportFileDialogController.exportProgress ==
                              exportFileDialogController.filesToExport.length) {
                            Navigator.of(context).pop();
                          } else {
                            await exportFileDialogController.export();
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15.0,
                            vertical: 10,
                          ),
                          child: AnimatedBuilder(
                            animation: exportFileDialogController,
                            builder: (context, _) => Text(
                              exportFileDialogController.exportProgress ==
                                      exportFileDialogController
                                          .filesToExport
                                          .length
                                  ? context.l10n.close
                                  : context.l10n.export,
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ExportFileDialogController extends ChangeNotifier {
  ExportFileDialogController({
    required SettingsScreenController settingsScreenController,
  }) : _settingsScreenController = settingsScreenController {
    unawaited(scanFilesToExport());
  }

  final SettingsScreenController _settingsScreenController;
  var scanning = true;
  var ready = false;
  var exportRunning = false;
  var exportProgress = -1;
  List<String> filesToExport = [];

  Future<void> scanFilesToExport() async {
    final supportDirPath = _settingsScreenController.supportDirPath;
    final filesEntityList = Directory(
      "$supportDirPath/Music",
    ).listSync(recursive: false);
    final filesPath = filesEntityList.map((entity) => entity.path).toList();
    filesToExport.addAll(filesPath);
    scanning = false;
    ready = true;
    notifyListeners();
  }

  Future<void> export() async {
    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    exportProgress = 0;
    exportRunning = true;
    notifyListeners();
    final exportDirPath = _settingsScreenController.exportLocationPath
        .toString();
    final length_ = filesToExport.length;
    for (int i = 0; i < length_; i++) {
      final filePath = filesToExport[i];
      final newFilePath = "$exportDirPath/${filePath.split("/").last}";
      await File(filePath).copy(newFilePath);
      exportProgress = i + 1;
      notifyListeners();
    }
    exportRunning = false;
    notifyListeners();
  }
}
