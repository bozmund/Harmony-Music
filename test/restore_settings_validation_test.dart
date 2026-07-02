import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/backup/restore_path_rewriter.dart';

void main() {
  const supportDirPath = '/data/user/0/com.anandnet.harmonymusic.dev/files';
  const prodSupportDir = '/data/user/0/com.anandnet.harmonymusic.prod/files';

  group('rewriteRestoredSettingPath', () {
    test('maps in-app paths from the source install onto this install', () {
      expect(
        rewriteRestoredSettingPath(
          '$prodSupportDir/Music',
          sourceSupportDir: prodSupportDir,
          supportDirPath: supportDirPath,
        ),
        '$supportDirPath/Music',
      );
      expect(
        rewriteRestoredSettingPath(
          prodSupportDir,
          sourceSupportDir: prodSupportDir,
          supportDirPath: supportDirPath,
        ),
        supportDirPath,
      );
    });

    test('leaves external and unrelated paths alone', () {
      expect(
        rewriteRestoredSettingPath(
          '/storage/emulated/0/HarmonyMusic',
          sourceSupportDir: prodSupportDir,
          supportDirPath: supportDirPath,
        ),
        isNull,
      );
      // Prefix must match on a path-segment boundary.
      expect(
        rewriteRestoredSettingPath(
          '${prodSupportDir}Extra/Music',
          sourceSupportDir: prodSupportDir,
          supportDirPath: supportDirPath,
        ),
        isNull,
      );
      expect(
        rewriteRestoredSettingPath(
          '$prodSupportDir/Music',
          sourceSupportDir: null,
          supportDirPath: supportDirPath,
        ),
        isNull,
      );
    });

    test('normalizes Windows separators', () {
      const winSupport = r'C:\Users\me\AppData\Roaming\harmonymusic';
      expect(
        rewriteRestoredSettingPath(
          '$winSupport\\Music',
          sourceSupportDir: winSupport,
          supportDirPath: supportDirPath,
        ),
        '$supportDirPath/Music',
      );
    });
  });

  group('validateRestoredLocationSetting', () {
    late List<String> persisted;
    late int resetCalls;

    setUp(() {
      persisted = [];
      resetCalls = 0;
    });

    Future<void> validate({
      required String? currentValue,
      required Future<bool> Function(String) probe,
      String? sourceSupportDir = prodSupportDir,
    }) =>
        validateRestoredLocationSetting(
          currentValue: currentValue,
          sourceSupportDir: sourceSupportDir,
          supportDirPath: supportDirPath,
          isUsableDirectory: probe,
          persist: (value) async => persisted.add(value),
          reset: () async => resetCalls++,
          settingName: 'test location',
        );

    test('keeps a usable external directory untouched', () async {
      await validate(
        currentValue: '/storage/emulated/0/HarmonyMusic',
        probe: (path) async => path == '/storage/emulated/0/HarmonyMusic',
      );

      expect(persisted, isEmpty);
      expect(resetCalls, 0);
    });

    test('rewrites and persists a usable in-app path from the source install',
        () async {
      await validate(
        currentValue: '$prodSupportDir/Music',
        probe: (path) async => path == '$supportDirPath/Music',
      );

      expect(persisted, ['$supportDirPath/Music']);
      expect(resetCalls, 0);
    });

    test('resets when the directory is missing or unwritable', () async {
      await validate(
        currentValue: '/storage/emulated/0/Gone',
        probe: (_) async => false,
      );

      expect(persisted, isEmpty);
      expect(resetCalls, 1);
    });

    test('resets when even the rewritten in-app path is unusable', () async {
      await validate(
        currentValue: '$prodSupportDir/Music',
        probe: (_) async => false,
      );

      expect(persisted, isEmpty);
      expect(resetCalls, 1);
    });

    test('does nothing for unset values', () async {
      await validate(currentValue: null, probe: (_) async => true);
      await validate(currentValue: '', probe: (_) async => true);

      expect(persisted, isEmpty);
      expect(resetCalls, 0);
    });
  });

  group('restore service settings validation source checks', () {
    late String serviceSource;

    setUpAll(() {
      serviceSource =
          File('lib/services/backup/restore_service.dart').readAsStringSync();
    });

    test('settings are validated after the path rewrites', () {
      final libraryRewriteIndex =
          serviceSource.indexOf('await rewriteRestoredLibraryPaths(');
      final validateIndex =
          serviceSource.indexOf('_validateRestoredSettingsPaths(');
      expect(libraryRewriteIndex, greaterThan(-1));
      expect(validateIndex, greaterThan(libraryRewriteIndex));
    });

    test('both location settings are covered and can reset to defaults', () {
      expect(serviceSource, contains('resetDownloadLocationPath'));
      expect(serviceSource, contains('resetExportLocationPath'));
      // Usability means writable, not merely existing: probe by creating a
      // file, since another package's private dir can exist yet be denied.
      expect(serviceSource, contains('writeAsBytes'));
    });
  });
}
