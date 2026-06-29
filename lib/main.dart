import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '/services/constant.dart';
import '/services/app_contracts.dart';
import '/services/app_platform_service.dart';
import '/services/file_picker_service.dart';
import '/utils/helper.dart';
import '/ui/screens/Search/search_screen_controller.dart';
import '/utils/get_localization.dart';
import '/services/downloader.dart';
import '/services/piped_service.dart';
import 'data/repositories/hive_repository_registration.dart';
import 'domain/repositories/download_repository.dart';
import 'domain/repositories/home_repository.dart';
import 'domain/repositories/library_repository.dart';
import 'domain/repositories/playback_session_repository.dart';
import 'domain/repositories/playlist_repository.dart';
import 'domain/repositories/search_history_repository.dart';
import 'domain/repositories/settings_repository.dart';
import 'domain/repositories/storage_admin_repository.dart';
import 'utils/app_link_controller.dart';
import '/services/audio_handler.dart';
import '/services/music_service.dart';
import '/ui/home.dart';
import '/ui/player/player_controller.dart';
import 'ui/screens/Settings/settings_screen_controller.dart';
import '/ui/utils/theme_controller.dart';
import 'ui/screens/Home/home_screen_controller.dart';
import 'ui/screens/Library/library_controller.dart';
import 'utils/system_tray.dart';
import 'utils/update_check_flag_file.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initHive();
  registerHiveRepositories();
  await setAppInitPrefs(Get.find<SettingsRepository>());
  await startApplicationServices();
  Get.put<AudioHandler>(await initAudioService(), permanent: true);
  WidgetsBinding.instance.addObserver(LifecycleHandler());
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    if (!GetPlatform.isDesktop) Get.put(AppLinksController());
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    return GetMaterialApp(
      title: 'Harmony Music',
      home: const Home(),
      debugShowCheckedModeBanner: false,
      translations: Languages(),
      locale: Locale(Get.find<SettingsRepository>().getLanguageCode()),
      fallbackLocale: const Locale("en"),
      builder: (context, child) {
        final mQuery = MediaQuery.of(context);
        final scale = mQuery.textScaler.clamp(
          minScaleFactor: 1.0,
          maxScaleFactor: 1.1,
        );
        return Stack(
          children: [
            GetX<ThemeController>(
              builder: (controller) => MediaQuery(
                data: mQuery.copyWith(textScaler: scale),
                child: AnimatedTheme(
                  duration: const Duration(milliseconds: 700),
                  data: controller.themeData.value!,
                  child: child!,
                ),
              ),
            ),
            GestureDetector(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  color: Colors.transparent,
                  height: mQuery.padding.bottom,
                  width: mQuery.size.width,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<void> startApplicationServices() async {
  registerHiveRepositories();
  if (!Get.isRegistered<PipedServices>()) {
    Get.lazyPut(
      () => PipedServices(Get.find<SettingsRepository>()),
      fenix: true,
    );
  }
  if (!Get.isRegistered<MusicServices>()) {
    Get.lazyPut(
      () => MusicServices(Get.find<SettingsRepository>()),
      fenix: true,
    );
  }
  if (!Get.isRegistered<MusicServiceContract>()) {
    Get.lazyPut<MusicServiceContract>(
      () => Get.find<MusicServices>(),
      fenix: true,
    );
  }
  if (!Get.isRegistered<AppPlatformContract>()) {
    Get.lazyPut<AppPlatformContract>(
      () => const DefaultAppPlatformService(),
      fenix: true,
    );
  }
  if (!Get.isRegistered<UpdateServiceContract>()) {
    Get.lazyPut<UpdateServiceContract>(
      () => const GithubUpdateService(),
      fenix: true,
    );
  }
  if (!Get.isRegistered<FilePickerContract>()) {
    Get.lazyPut<FilePickerContract>(
      () => const DefaultFilePickerService(),
      fenix: true,
    );
  }
  if (!Get.isRegistered<ThemeController>()) {
    Get.lazyPut(
      () => ThemeController(Get.find<SettingsRepository>()),
      fenix: true,
    );
  }
  if (!Get.isRegistered<PlayerController>()) {
    Get.lazyPut(
      () => PlayerController(
        settingsRepository: Get.find<SettingsRepository>(),
        libraryRepository: Get.find<LibraryRepository>(),
        playbackSessionRepository: Get.find<PlaybackSessionRepository>(),
      ),
      fenix: true,
    );
  }
  if (!Get.isRegistered<HomeScreenController>()) {
    Get.lazyPut(
      () => HomeScreenController(
        settingsRepository: Get.find<SettingsRepository>(),
        homeRepository: Get.find<HomeRepository>(),
      ),
      fenix: true,
    );
  }
  if (!Get.isRegistered<LibrarySongsController>()) {
    Get.lazyPut(
      () => LibrarySongsController(
        libraryRepository: Get.find<LibraryRepository>(),
      ),
      fenix: true,
    );
  }
  if (!Get.isRegistered<LibraryPlaylistsController>()) {
    Get.lazyPut(
      () => LibraryPlaylistsController(
        playlistRepository: Get.find<PlaylistRepository>(),
        settingsRepository: Get.find<SettingsRepository>(),
      ),
      fenix: true,
    );
  }
  if (!Get.isRegistered<LibraryAlbumsController>()) {
    Get.lazyPut(
      () => LibraryAlbumsController(
        libraryRepository: Get.find<LibraryRepository>(),
      ),
      fenix: true,
    );
  }
  if (!Get.isRegistered<LibraryArtistsController>()) {
    Get.lazyPut(
      () => LibraryArtistsController(
        libraryRepository: Get.find<LibraryRepository>(),
      ),
      fenix: true,
    );
  }
  if (!Get.isRegistered<SettingsScreenController>()) {
    Get.lazyPut(
      () => SettingsScreenController(
        settingsRepository: Get.find<SettingsRepository>(),
        storageAdminRepository: Get.find<StorageAdminRepository>(),
      ),
      fenix: true,
    );
  }
  if (!Get.isRegistered<Downloader>()) {
    Get.lazyPut(() => Downloader(Get.find<DownloadRepository>()), fenix: true);
  }
  if (!Get.isRegistered<DownloaderContract>()) {
    Get.lazyPut<DownloaderContract>(() => Get.find<Downloader>(), fenix: true);
  }
  if (GetPlatform.isDesktop) {
    if (!Get.isRegistered<SearchScreenController>()) {
      Get.lazyPut(
        () => SearchScreenController(Get.find<SearchHistoryRepository>()),
        fenix: true,
      );
    }
    if (!Get.isRegistered<DesktopSystemTray>()) {
      Get.put(DesktopSystemTray());
    }
  }
}

Future<void> initHive() async {
  String applicationDataDirectoryPath;
  if (GetPlatform.isDesktop) {
    applicationDataDirectoryPath =
        "${(await getApplicationSupportDirectory()).path}/db";
  } else {
    applicationDataDirectoryPath =
        (await getApplicationDocumentsDirectory()).path;
  }
  await Hive.initFlutter(applicationDataDirectoryPath);
  await Hive.openBox(BoxNames.songsCache);
  await Hive.openBox(BoxNames.songDownloads);
  await Hive.openBox(BoxNames.songsUrlCache);
  await Hive.openBox(BoxNames.appPrefs);
}

Future<void> setAppInitPrefs(SettingsRepository settingsRepository) async {
  await settingsRepository.seedDefaults(updateCheckFlag);
}

class LifecycleHandler extends WidgetsBindingObserver {
  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else if (state == AppLifecycleState.detached) {
      await Get.find<AudioHandler>().customAction("saveSession");
    }
  }
}
