import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:get/get.dart';

import 'app_contracts.dart';

class DefaultFilePickerService implements FilePickerContract {
  const DefaultFilePickerService();

  @override
  Future<file_selector.XFile?> openFile({
    List<file_selector.XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) {
    return file_selector.openFile(
      acceptedTypeGroups: acceptedTypeGroups ?? const [],
      initialDirectory: initialDirectory,
      confirmButtonText: confirmButtonText,
    );
  }

  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) {
    return file_selector.getDirectoryPath(
      initialDirectory: initialDirectory,
      confirmButtonText: confirmButtonText,
    );
  }
}

class FilePickerService {
  FilePickerService._();

  static FilePickerContract get _service =>
      Get.isRegistered<FilePickerContract>()
      ? Get.find<FilePickerContract>()
      : const DefaultFilePickerService();

  static Future<file_selector.XFile?> openFile({
    List<file_selector.XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) {
    return _service.openFile(
      acceptedTypeGroups: acceptedTypeGroups,
      initialDirectory: initialDirectory,
      confirmButtonText: confirmButtonText,
    );
  }

  static Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) {
    return _service.getDirectoryPath(
      initialDirectory: initialDirectory,
      confirmButtonText: confirmButtonText,
    );
  }
}
