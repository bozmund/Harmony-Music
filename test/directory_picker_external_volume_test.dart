import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Picking a folder on an SD card as the download location failed (#78).
///
/// file_selector's Android implementation resolves a picked tree URI to a path
/// only for the "primary" volume and throws for anything else, so every folder
/// on an SD card or USB drive was rejected. file_picker maps non-primary
/// volumes to /storage/<volume-id>/<path>, so Android goes through it instead.
///
/// The host running these tests is never Android, so the branch is pinned at
/// source level.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/services/file_picker_service.dart').readAsStringSync();
  });

  test('Android picks folders through file_picker', () {
    final method = _block(source, 'Future<String?> getDirectoryPath({');
    final android = method.indexOf('if (RuntimePlatform.isAndroid) {');
    final filePicker = method.indexOf(
      'file_picker.FilePicker.getDirectoryPath(',
    );
    final fileSelector = method.indexOf('file_selector.getDirectoryPath(');
    expect(android, greaterThan(-1));
    expect(filePicker, greaterThan(android));
    expect(fileSelector, greaterThan(filePicker));
  });

  test('every folder picker in the app goes through the service', () {
    // A direct call to file_selector would bring the SD card failure back for
    // that one setting.
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path
          .replaceAll(r'\', '/')
          .endsWith('lib/services/file_picker_service.dart')) {
        continue;
      }
      final text = file.readAsStringSync();
      expect(
        text.contains('file_selector.getDirectoryPath(') ||
            text.contains('FilePicker.getDirectoryPath('),
        isFalse,
        reason: '${file.path} should use FilePickerService.getDirectoryPath',
      );
    }
  });
}

/// The declaration starting at [signature], up to its matching closing brace.
String _block(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, greaterThan(-1), reason: 'missing $signature');
  final open = source.indexOf('{', source.indexOf(')', start));
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  return source.substring(start);
}
