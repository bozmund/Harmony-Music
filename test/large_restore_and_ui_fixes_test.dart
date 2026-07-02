import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('large backup restore', () {
    late String source;

    setUp(() {
      source = File('lib/ui/widgets/restore_dialog.dart').readAsStringSync();
    });

    test('restore picks the backup via the large-file-safe picker', () {
      // file_selector's openFile reads the whole picked file into memory on
      // Android (size as a 32-bit int), which fails for multi-GB .hmb files.
      expect(source, contains('FilePickerService.pickLargeFilePath('));
      expect(source, isNot(contains('FilePickerService.openFile(')));
    });

    test('restore parses the archive before deleting live databases', () {
      final serviceSource = File(
        'lib/services/backup/restore_service.dart',
      ).readAsStringSync();
      final decodeIndex = serviceSource.indexOf('ZipDecoder().decodeStream(');
      final manifestReadIndex = serviceSource.indexOf('_readManifest(archive)');
      final closeDbIndex = serviceSource.indexOf('closeAll()');
      final deleteHiveIndex = serviceSource.indexOf(".endsWith('.hive')");
      expect(decodeIndex, greaterThan(-1));
      expect(manifestReadIndex, greaterThan(-1));
      expect(closeDbIndex, greaterThan(-1));
      expect(deleteHiveIndex, greaterThan(-1));
      // A corrupt/unreadable backup must fail before the .hive files are
      // deleted, otherwise a failed restore wipes the user's data. The
      // manifest is read up front too, while nothing has been touched.
      expect(decodeIndex, lessThan(manifestReadIndex));
      expect(manifestReadIndex, lessThan(closeDbIndex));
      expect(decodeIndex, lessThan(deleteHiveIndex));
    });

    test('restore reopens the boxes before rewriting persisted paths', () {
      final serviceSource = File(
        'lib/services/backup/restore_service.dart',
      ).readAsStringSync();
      final extractIndex = serviceSource.indexOf('_writeArchiveFileToDisk(');
      final reopenIndex = serviceSource.indexOf('reopenCoreBoxes()');
      final rewriteIndex = serviceSource.indexOf(
        'rewriteRestoredDownloadPaths(',
      );
      expect(extractIndex, greaterThan(-1));
      // closeAll() shut every box, and some repositories resolve theirs via
      // Hive.box(...), which throws while closed — without reopening first
      // the whole rewrite phase dies into the error handler.
      expect(reopenIndex, greaterThan(extractIndex));
      expect(rewriteIndex, greaterThan(reopenIndex));
    });

    test('restore surfaces the underlying error and cleans the cache copy', () {
      expect(source, contains(r'restoreError = "Restore failed: $e"'));
      expect(source, contains('_deletePickerCacheCopy(restoreFilePath)'));
      // Only paths inside the app temp dir may be deleted — never the
      // user's actual backup file.
      expect(source, contains('getTemporaryDirectory()'));
      expect(source, contains('startsWith(tempDirPath)'));
    });

    test('picker service implementation never loads file bytes', () {
      final pickerSource = File(
        'lib/services/file_picker_service.dart',
      ).readAsStringSync();
      expect(pickerSource, contains('pickFiles('));
      expect(pickerSource, contains('withData: false'));
      expect(pickerSource, contains('withReadStream: false'));
    });
  });

  group('home screen report issue button', () {
    test('button is part of the scrolling content list, not an overlay', () {
      final source = File(
        'lib/ui/screens/Home/home_screen.dart',
      ).readAsStringSync();
      // Built once in Body...
      expect(source, contains('final reportIssueButton = Align('));
      // ...and rendered as the first item of the home ListView.
      expect(source, contains('reportIssueButton,\n'));
      expect(source, contains('required this.reportIssueButton'));
      // The old pinned overlay placed it at a fixed top-right position.
      expect(
        source,
        isNot(contains('top: MediaQuery.of(context).padding.top + 10')),
      );
    });
  });

  group('song change frame drops', () {
    test('mediaItem listener coalesces notifications', () {
      final source = File(
        'lib/ui/player/player_controller.dart',
      ).readAsStringSync();
      final start = source.indexOf('void _listenForChangesInDuration()');
      expect(start, greaterThan(-1));
      final block = source.substring(start, source.indexOf('\n  }', start));
      // The observable writes in the listener already schedule a coalesced
      // notification; a direct notifyListeners() would rebuild everything
      // twice per song change.
      expect(block, contains('_notifyPlayerChanged();'));
      expect(block, isNot(contains('notifyListeners();')));
    });

    test('dynamic theme skips rebuilds when the palette is unchanged', () {
      final source = File(
        'lib/ui/utils/theme_controller.dart',
      ).readAsStringSync();
      final start = source.indexOf('Future<void> setTheme(');
      expect(start, greaterThan(-1));
      final block = source.substring(start, source.indexOf('\n  }', start));
      final earlyOutIndex = block.indexOf(
        'nextPrimaryColor == primaryColor.value',
      );
      final themeBuildIndex = block.indexOf('themeData.value = _createThemeData');
      expect(earlyOutIndex, greaterThan(-1));
      expect(themeBuildIndex, greaterThan(-1));
      // The identical-palette early return must run before the app-wide
      // ThemeData rebuild (and the Hive write) it is there to avoid.
      expect(earlyOutIndex, lessThan(themeBuildIndex));
    });
  });

  group('immersive mode after resume', () {
    test('sliding panel reapplies immersive mode on app resume', () {
      final source = File(
        'lib/ui/widgets/sliding_up_panel.dart',
      ).readAsStringSync();
      expect(source, contains('WidgetsBindingObserver'));
      expect(source, contains('WidgetsBinding.instance.addObserver(this)'));
      expect(source, contains('WidgetsBinding.instance.removeObserver(this)'));
      final start = source.indexOf('void didChangeAppLifecycleState');
      expect(start, greaterThan(-1));
      final block = source.substring(start, source.indexOf('\n  }', start));
      expect(block, contains('AppLifecycleState.resumed'));
      expect(block, contains('widget.setsScreenMode'));
      expect(block, contains('_isPanelOpen'));
      expect(block, contains('SystemUiMode.immersive'));
    });

    test('app resume handler does not stomp the open player panel', () {
      final source = File('lib/main.dart').readAsStringSync();
      final start = source.indexOf('didChangeAppLifecycleState');
      expect(start, greaterThan(-1));
      final block = source.substring(start, source.indexOf('\n  }', start));
      expect(block, contains('playerPanelController'));
      expect(
        block,
        contains(
          'playerPanelOpen ? SystemUiMode.immersive : SystemUiMode.edgeToEdge',
        ),
      );
    });
  });
}
