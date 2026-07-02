import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:file_selector/file_selector.dart' as file_selector;

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
  Future<String?> pickLargeFilePath({required List<String> extensions}) async {
    // file_picker with withData/withReadStream disabled only streams the
    // picked document to a cache file on Android (size handled as a long)
    // and returns its path, so multi-gigabyte files never touch the heap.
    final result = await file_picker.FilePicker.pickFiles(
      type: file_picker.FileType.custom,
      allowedExtensions: extensions,
      withData: false,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.first.path;
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

  static FilePickerContract? override;

  static FilePickerContract get _service =>
      override ?? const DefaultFilePickerService();

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

  static Future<String?> pickLargeFilePath({
    required List<String> extensions,
  }) {
    return _service.pickLargeFilePath(extensions: extensions);
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
