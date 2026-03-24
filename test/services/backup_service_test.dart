import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/widgets/backup_dialog.dart';
import 'dart:io';

void main() {
  group('Backup Logic Tests', () {
    late Directory tempDir;
    
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('backup_test');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('processDirectoryInIsolate should find files with correct extension', () async {
      // Create mock files
      final hiveFile = File('${tempDir.path}/test.hive');
      final otherFile = File('${tempDir.path}/test.txt');
      await hiveFile.writeAsString('test');
      await otherFile.writeAsString('test');

      final result = await processDirectoryInIsolate(tempDir.path, extensionFilter: '.hive');

      expect(result.length, 1);
      expect(result.first.endsWith('test.hive'), true);
    });

    test('processDirectoryInIsolate should find all files when extensionFilter is empty', () async {
      // Create mock files
      final file1 = File('${tempDir.path}/test1.mp3');
      final file2 = File('${tempDir.path}/test2.opus');
      await file1.writeAsString('test');
      await file2.writeAsString('test');

      final result = await processDirectoryInIsolate(tempDir.path, extensionFilter: '');

      expect(result.length, 2);
    });
  });
}
