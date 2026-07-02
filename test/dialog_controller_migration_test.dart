import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'import and export dialog controllers are locally owned Flutter state',
    () {
      for (final path in [
        'lib/ui/widgets/link_piped.dart',
        'lib/ui/widgets/import_ytmusic_playlist_dialog.dart',
        'lib/ui/widgets/import_spotify_playlist_dialog.dart',
        'lib/ui/widgets/export_file_dialog.dart',
        'lib/ui/widgets/backup_dialog.dart',
        'lib/ui/widgets/restore_dialog.dart',
        'lib/ui/widgets/add_to_playlist.dart',
      ]) {
        final source = File(path).readAsStringSync();

        expect(source, contains('extends ChangeNotifier'), reason: path);
        expect(source, contains('AnimatedBuilder'), reason: path);
        expect(source, isNot(contains('Get.put(')), reason: path);
        expect(source, isNot(contains('extends GetxController')), reason: path);
        expect(source, isNot(contains('Obx(')), reason: path);
        expect(source, isNot(contains('.obs')), reason: path);
      }
    },
  );

  test('create playlist dialog uses Flutter listenable state', () {
    final dialogSource = File(
      'lib/ui/widgets/create_playlist_dialog.dart',
    ).readAsStringSync();
    final controllerSource = File(
      'lib/ui/screens/Library/library_controller.dart',
    ).readAsStringSync();

    expect(dialogSource, contains('AnimatedBuilder'));
    expect(dialogSource, isNot(contains('Obx(')));
    expect(controllerSource, contains('String playlistCreationMode'));
    expect(controllerSource, contains('bool creationInProgress'));
    expect(
      controllerSource,
      isNot(contains('playlistCreationMode = "local".obs')),
    );
    expect(controllerSource, isNot(contains('creationInProgress = false.obs')));
  });

  test('import and playlist export progress use Flutter listenable state', () {
    final libraryController = File(
      'lib/ui/screens/Library/library_controller.dart',
    ).readAsStringSync();
    final playlistController = File(
      'lib/ui/screens/Playlist/playlist_screen_controller.dart',
    ).readAsStringSync();

    expect(libraryController, contains('bool isImporting'));
    expect(libraryController, contains('double importProgress'));
    expect(libraryController, isNot(contains('isImporting = false.obs')));
    expect(libraryController, isNot(contains('importProgress = 0.0.obs')));
    expect(playlistController, contains('bool isExporting'));
    expect(playlistController, contains('double exportProgress'));
    expect(playlistController, isNot(contains('isExporting = false.obs')));
    expect(playlistController, isNot(contains('exportProgress = 0.0.obs')));
  });

  test('theme controller is Riverpod-owned Flutter state', () {
    final themeSource = File(
      'lib/ui/utils/theme_controller.dart',
    ).readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();
    final providerSource = File(
      'lib/app/providers/controller_providers.dart',
    ).readAsStringSync();

    expect(themeSource, contains('extends ChangeNotifier'));
    expect(themeSource, isNot(contains("package:get/get.dart")));
    expect(themeSource, isNot(contains('extends GetxController')));
    expect(themeSource, isNot(contains('.obs')));
    expect(mainSource, contains('ref.watch(themeControllerProvider)'));
    expect(mainSource, contains('AnimatedBuilder'));
    expect(mainSource, isNot(contains('GetX<ThemeController>')));
    expect(providerSource, contains('ChangeNotifierProvider<ThemeController>'));
  });

  test('desktop tray is a plain disposable service', () {
    final source = File('lib/utils/system_tray.dart').readAsStringSync();

    expect(source, contains('class DesktopSystemTray with TrayListener'));
    expect(source, contains('void dispose()'));
    expect(source, isNot(contains("package:get/get.dart")));
    expect(source, isNot(contains('extends GetxService')));
    expect(source, isNot(contains('Get.find')));
  });

  test('audio handler is not a GetX service', () {
    final source = File('lib/services/audio_handler.dart').readAsStringSync();

    expect(source, contains('class MyAudioHandler extends BaseAudioHandler'));
    expect(source, isNot(contains('GetxServiceMixin')));
  });

  test('downloader is not a GetX service', () {
    final source = File('lib/services/downloader.dart').readAsStringSync();

    expect(
      source,
      contains(
        'class Downloader extends ChangeNotifier implements DownloaderContract',
      ),
    );
    expect(source, isNot(contains('extends GetxService')));
  });

  test('combined library owns tab controller locally', () {
    final source = File(
      'lib/ui/screens/Library/library_combined.dart',
    ).readAsStringSync();

    expect(source, contains('with SingleTickerProviderStateMixin'));
    expect(source, contains('CombinedLibraryTabControllerScope'));
    expect(source, isNot(contains('CombinedLibraryController')));
    expect(source, isNot(contains('Get.put(')));
    expect(source, isNot(contains('extends GetxController')));
  });

  test('sort widget controller is local Flutter state', () {
    final source = File('lib/ui/widgets/sort_widget.dart').readAsStringSync();
    final controllerBlock = _classBlock(source, 'SortWidgetController');

    expect(source, contains('class SortWidget extends StatefulWidget'));
    expect(source, contains('SortWidgetRegistry.register'));
    expect(source, isNot(contains('Get.put(')));
    expect(controllerBlock, contains('extends ChangeNotifier'));
    expect(controllerBlock, isNot(contains('extends GetxController')));
    expect(controllerBlock, isNot(contains('.obs')));
    expect(source, isNot(contains('Obx(')));
  });

  test('song info bottom sheet owns controller locally', () {
    final source = File(
      'lib/ui/widgets/song_info_bottom_sheet.dart',
    ).readAsStringSync();
    final controllerBlock = _classBlock(source, 'SongInfoController');

    expect(
      source,
      contains('class SongInfoBottomSheet extends ConsumerStatefulWidget'),
    );
    expect(source, contains('SongInfoControllerRegistry.open'));
    expect(source, isNot(contains('Get.put(')));
    expect(controllerBlock, contains('extends ChangeNotifier'));
    expect(controllerBlock, isNot(contains('extends GetxController')));
    expect(controllerBlock, isNot(contains('.obs')));
    expect(source, isNot(contains('Obx(')));
    expect(source, contains('kDebugMode'));
    expect(source, contains('developerSettingsEnabled'));
    expect(source, contains('IssueReportDialog'));
    expect(source, contains('detailedPlaybackDebugSnapshot'));
    expect(source, contains('includePlaybackDebug: true'));
  });

  test('issue reports can include extra diagnostics at submit time', () {
    final source = File(
      'lib/ui/widgets/issue_report_dialog.dart',
    ).readAsStringSync();
    final homeSource = File(
      'lib/ui/screens/Home/home_screen.dart',
    ).readAsStringSync();
    final playerSource = File(
      'lib/ui/player/player_controller.dart',
    ).readAsStringSync();

    expect(source, contains('extraDiagnosticsBuilder'));
    expect(source, contains('diagnostics.addAll(extraDiagnostics)'));
    expect(homeSource, contains('developerSettingsEnabled'));
    expect(homeSource, contains('detailedPlaybackDebugSnapshot'));
    expect(
      playerSource,
      contains('Map<String, dynamic> playbackDebugSnapshot()'),
    );
    expect(
      playerSource,
      contains('Future<Map<String, dynamic>> detailedPlaybackDebugSnapshot()'),
    );
    expect(playerSource, contains("'audioHandler'"));
    expect(playerSource, contains("'playerController'"));
  });

  test('library saved searches use local controller and repository', () {
    final librarySource = File(
      'lib/ui/screens/Library/library.dart',
    ).readAsStringSync();
    final controllerSource = File(
      'lib/ui/screens/Library/library_controller.dart',
    ).readAsStringSync();
    final savedSearchBlock = _classBlock(
      controllerSource,
      'LibrarySearchesController',
    );

    expect(librarySource, isNot(contains('Get.put(LibrarySearchesController')));
    expect(savedSearchBlock, contains('extends ChangeNotifier'));
    expect(savedSearchBlock, contains('LibraryRepository'));
    expect(savedSearchBlock, isNot(contains('Hive.openBox')));
    expect(savedSearchBlock, isNot(contains('extends GetxController')));
    expect(savedSearchBlock, isNot(contains('.obs')));
  });

  test('song action widgets do not import Hive directly', () {
    for (final path in [
      'lib/ui/widgets/song_download_btn.dart',
      'lib/ui/widgets/song_info_bottom_sheet.dart',
    ]) {
      final source = File(path).readAsStringSync();

      expect(source, contains('Repository'), reason: path);
      expect(source, isNot(contains("package:hive")), reason: path);
      expect(source, isNot(contains('Hive.openBox')), reason: path);
      expect(source, isNot(contains('Hive.box')), reason: path);
    }
  });

  test('album and artist page controllers use repositories for storage', () {
    for (final path in [
      'lib/ui/screens/Album/album_screen_controller.dart',
      'lib/ui/screens/Artists/artist_screen_controller.dart',
      'lib/ui/screens/Playlist/playlist_screen_controller.dart',
      'lib/base_class/playlist_album_screen_con_base.dart',
    ]) {
      final source = File(path).readAsStringSync();

      expect(source, contains('Repository'), reason: path);
      expect(source, isNot(contains("package:hive")), reason: path);
      expect(source, isNot(contains('Hive.openBox')), reason: path);
      expect(source, isNot(contains('Hive.box')), reason: path);
    }
  });

  test('route media controllers receive core dependencies explicitly', () {
    for (final path in [
      'lib/ui/screens/Album/album_screen_controller.dart',
      'lib/ui/screens/Artists/artist_screen_controller.dart',
      'lib/ui/screens/Playlist/playlist_screen_controller.dart',
      'lib/base_class/playlist_album_screen_con_base.dart',
    ]) {
      final source = File(path).readAsStringSync();

      expect(source, isNot(contains('Get.find<MusicServiceContract>')));
      expect(source, isNot(contains('Get.find<PlaylistRepository>')));
      expect(source, isNot(contains('Get.find<LibraryRepository>')));
      expect(source, isNot(contains('Get.find<HomeScreenController>')));
      expect(source, isNot(contains('Get.find<SettingsScreenController>')));
    }
  });

  test(
    'route media controllers are locally owned and registered outside GetX',
    () {
      final routeScreens = {
        'lib/ui/screens/Album/album_screen.dart':
            'AlbumScreenControllerRegistry.register',
        'lib/ui/screens/Artists/artist_screen.dart':
            'ArtistScreenControllerRegistry.register',
        'lib/ui/screens/Playlist/playlist_screen.dart':
            'PlaylistScreenControllerRegistry.register',
      };

      for (final entry in routeScreens.entries) {
        final source = File(entry.key).readAsStringSync();
        expect(
          source,
          anyOf(
            contains('extends StatefulWidget'),
            contains('extends ConsumerStatefulWidget'),
          ),
          reason: entry.key,
        );
        expect(source, contains(entry.value), reason: entry.key);
        expect(source, isNot(contains('Get.put(')), reason: entry.key);
      }
    },
  );

  test('backup and restore dialogs do not import Hive directly', () {
    for (final path in [
      'lib/ui/widgets/backup_dialog.dart',
      'lib/ui/widgets/restore_dialog.dart',
    ]) {
      final source = File(path).readAsStringSync();

      expect(source, contains('Repository'), reason: path);
      expect(source, isNot(contains("package:hive")), reason: path);
      expect(source, isNot(contains('Hive.openBox')), reason: path);
      expect(source, isNot(contains('Hive.box')), reason: path);
    }
  });

  test('production Hive access stays in data repositories and bootstrap', () {
    final disallowed = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalizedPath = entity.path.replaceAll('\\', '/');
      final isAllowed =
          normalizedPath == 'lib/main.dart' ||
          normalizedPath.startsWith('lib/data/repositories/');
      if (isAllowed) continue;

      final source = entity.readAsStringSync();
      if (source.contains('package:hive') ||
          source.contains('Hive.openBox') ||
          source.contains('Hive.box') ||
          source.contains('Hive.isBoxOpen') ||
          source.contains('Hive.close') ||
          source.contains('HiveError')) {
        disallowed.add(normalizedPath);
      }
    }

    expect(disallowed, isEmpty);
  });

  test('core repositories and music service are not resolved through GetX', () {
    final disallowed = <String>[];
    final patterns = [
      'Get.find<MusicServiceContract>',
      'Get.find<SettingsRepository>',
      'Get.find<LibraryRepository>',
      'Get.find<DownloadRepository>',
      'Get.find<SongCacheRepository>',
      'Get.find<PlaylistRepository>',
      'Get.find<PlaybackSessionRepository>',
      'Get.find<SearchHistoryRepository>',
      'Get.find<LyricsRepository>',
      'Get.find<StorageAdminRepository>',
    ];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final pattern in patterns) {
        if (source.contains(pattern)) {
          disallowed.add('${entity.path}: $pattern');
        }
      }
    }

    expect(disallowed, isEmpty);
  });

  test('production code does not create controllers with Get.put', () {
    final disallowed = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('Get.put(')) {
        disallowed.add(entity.path);
      }
    }

    expect(disallowed, isEmpty);
  });

  test('production app shell and navigation do not use GetX APIs', () {
    final disallowed = <String>[];
    const patterns = [
      'GetMaterialApp',
      'Get.toNamed',
      'Get.nestedKey',
      'Get.lazyPut',
      'Get.find<',
      'Get.put(',
      'GetPlatform',
      'Get.mediaQuery',
      'Get.height',
      'Get.width',
      'Get.size',
    ];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final pattern in patterns) {
        if (source.contains(pattern)) {
          disallowed.add('${entity.path}: $pattern');
        }
      }
    }

    expect(disallowed, isEmpty);
  });

  test('production code has no GetX controller subclasses', () {
    final disallowed = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('GetxController') ||
          source.contains('extends GetxController')) {
        disallowed.add(entity.path);
      }
    }

    expect(disallowed, isEmpty);
  });

  test('audio handler is owned by Riverpod, not GetX DI', () {
    final disallowed = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('Get.put<AudioHandler>') ||
          source.contains('Get.find<AudioHandler>') ||
          source.contains('Get.isRegistered<AudioHandler>')) {
        disallowed.add(entity.path);
      }
    }

    expect(disallowed, isEmpty);
  });
}

String _classBlock(String source, String className) {
  final classStart = source.indexOf('class $className');
  expect(classStart, isNonNegative);

  final bodyStart = source.indexOf('{', classStart);
  var depth = 0;
  for (var index = bodyStart; index < source.length; index++) {
    final char = source[index];
    if (char == '{') depth++;
    if (char == '}') {
      depth--;
      if (depth == 0) return source.substring(classStart, index + 1);
    }
  }
  fail('Could not parse $className block');
}
