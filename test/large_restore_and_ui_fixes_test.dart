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
      // Normalize CRLF so the assertions hold regardless of the checkout's
      // line endings.
      final source = File('lib/ui/screens/Home/home_screen.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
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
    test('system ui mode service owns the platform mode call', () {
      final serviceSource = File(
        'lib/services/system_ui_mode_service.dart',
      ).readAsStringSync();
      expect(
        serviceSource,
        contains('SystemChrome.setEnabledSystemUIMode(resolvedMode)'),
      );

      final slidingPanelSource = File(
        'lib/ui/widgets/sliding_up_panel.dart',
      ).readAsStringSync();
      final mainSource = File('lib/main.dart').readAsStringSync();
      expect(
        slidingPanelSource,
        isNot(contains('SystemChrome.setEnabledSystemUIMode')),
      );
      expect(
        mainSource,
        isNot(contains('SystemChrome.setEnabledSystemUIMode')),
      );
    });

    test('home shell declares edge-to-edge as the default mode', () {
      final source = File('lib/ui/home.dart').readAsStringSync();
      expect(source, contains('SystemUiModeScope.edgeToEdge'));
    });

    test('sliding panel declares immersive mode for the main player', () {
      final source = File(
        'lib/ui/widgets/sliding_up_panel.dart',
      ).readAsStringSync();
      expect(source, contains('SystemUiModeScope.immersive'));
      expect(source, contains('active: widget.setsScreenMode'));
      expect(source, contains('SystemUiModePriority.player'));
    });

    test('queue panel does not own system ui mode', () {
      final source = File(
        'lib/ui/player/components/player_queue_panel.dart',
      ).readAsStringSync();
      expect(source, contains('setsScreenMode: false'));
    });
  });

  group('app text colors', () {
    test('text buttons inherit app text color by default', () {
      final source = File('lib/ui/utils/theme_controller.dart')
          .readAsStringSync();
      expect(source, contains('textButtonTheme: TextButtonThemeData'));
      expect(source, contains('foregroundColor: buttonTextColor'));
      expect(source, contains('disabledForegroundColor'));
      expect(source, contains('textStyle: appTextTheme.titleMedium'));
    });
  });
}
