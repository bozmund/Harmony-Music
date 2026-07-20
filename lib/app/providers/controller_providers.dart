import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../services/listen_together/lan_transport.dart';
import '../../services/listen_together/hybrid_transport.dart';
import '../../services/listen_together/nearby_transport.dart';
import '../../services/listen_together/listen_together_controller.dart';
import '../../services/listen_together/sync_transport.dart';
import '../../utils/system_tray.dart';
import '../../utils/runtime_platform.dart';
import '../../data/repositories/listen_together_preferences.dart';
import '../../ui/player/player_controller.dart';
import '../../ui/screens/Home/home_screen_controller.dart';
import '../../ui/screens/Library/library_controller.dart';
import '../../ui/screens/Search/search_screen_controller.dart';
import '../../ui/screens/Settings/settings_screen_controller.dart';
import '../../ui/utils/theme_controller.dart';
import 'app_locale_provider.dart';
import 'auth_providers.dart';
import 'repository_providers.dart';
import 'service_providers.dart';

final themeControllerProvider = ChangeNotifierProvider<ThemeController>(
  (ref) => ThemeController(ref.watch(settingsRepositoryProvider)),
);

final ChangeNotifierProvider<PlayerController> playerControllerProvider =
    ChangeNotifierProvider<PlayerController>((ref) {
      final controller = PlayerController(
        audioHandler: ref.read(audioHandlerProvider),
        settingsController: ref.read(settingsScreenControllerProvider),
        homeScreenController: ref.read(homeScreenControllerProvider),
        downloader: ref.read(downloaderProvider),
        settingsRepository: ref.read(settingsRepositoryProvider),
        libraryRepository: ref.read(libraryRepositoryProvider),
        lyricsRepository: ref.read(lyricsRepositoryProvider),
        playbackSessionRepository: ref.read(playbackSessionRepositoryProvider),
        musicService: ref.read(musicServiceContractProvider),
        playbackCommands: ref.read(playbackCommandServiceProvider),
      );
      unawaited(controller.init());
      return controller;
    });

final ChangeNotifierProvider<ListenTogetherController>
listenTogetherControllerProvider =
    ChangeNotifierProvider<ListenTogetherController>((ref) {
      final preferences = ListenTogetherPreferences();
      return ListenTogetherController(
        playerController: ref.read(playerControllerProvider),
        playbackCommands: ref.read(playbackCommandServiceProvider),
        transportFactory: createListenTogetherTransport,
        deviceName: preferences.deviceName,
        saveDeviceName: preferences.setDeviceName,
        initialTransport: RuntimePlatform.isAndroid
            ? preferences.transport
            : TransportKind.wifi,
        saveTransport: preferences.setTransport,
      );
    });

SyncTransport createListenTogetherTransport(TransportKind kind) =>
    switch (kind) {
      TransportKind.wifi => LanTransport(),
      TransportKind.bluetooth => NearbyTransport(),
      TransportKind.both => HybridTransport(),
    };

final ChangeNotifierProvider<HomeScreenController>
homeScreenControllerProvider = ChangeNotifierProvider<HomeScreenController>((
  ref,
) {
  final controller = HomeScreenController(
    settingsRepository: ref.watch(settingsRepositoryProvider),
    homeRepository: ref.watch(homeRepositoryProvider),
    musicService: ref.watch(musicServiceContractProvider),
    audioHandler: ref.watch(audioHandlerProvider),
    settingsScreenController: () => ref.read(settingsScreenControllerProvider),
    playerController: () => ref.read(playerControllerProvider),
  );
  unawaited(controller.init());
  return controller;
});

final librarySongsControllerProvider =
    ChangeNotifierProvider<LibrarySongsController>((ref) {
      final controller = LibrarySongsController(
        downloadRepository: ref.watch(downloadRepositoryProvider),
        libraryRepository: ref.watch(libraryRepositoryProvider),
        songCacheRepository: ref.watch(songCacheRepositoryProvider),
      );
      LibrarySongsControllerRegistry.register(controller);
      unawaited(controller.init());
      return controller;
    });

final libraryPlaylistsControllerProvider =
    ChangeNotifierProvider<LibraryPlaylistsController>((ref) {
      final controller = LibraryPlaylistsController(
        playlistRepository: ref.watch(playlistRepositoryProvider),
        libraryRepository: ref.watch(libraryRepositoryProvider),
        musicService: ref.watch(musicServiceContractProvider),
        settingsRepository: ref.watch(settingsRepositoryProvider),
        pipedServices: ref.watch(pipedServicesProvider),
      );
      LibraryPlaylistsControllerRegistry.register(controller);
      unawaited(controller.init());
      return controller;
    });

final libraryAlbumsControllerProvider =
    ChangeNotifierProvider<LibraryAlbumsController>((ref) {
      final controller = LibraryAlbumsController(
        libraryRepository: ref.watch(libraryRepositoryProvider),
      );
      unawaited(controller.init());
      return controller;
    });

final libraryArtistsControllerProvider =
    ChangeNotifierProvider<LibraryArtistsController>((ref) {
      final controller = LibraryArtistsController(
        libraryRepository: ref.watch(libraryRepositoryProvider),
      );
      unawaited(controller.init());
      return controller;
    });

final ChangeNotifierProvider<SettingsScreenController>
settingsScreenControllerProvider =
    ChangeNotifierProvider<SettingsScreenController>((ref) {
      final controller = SettingsScreenController(
        audioHandler: ref.watch(audioHandlerProvider),
        playlistRepository: ref.watch(playlistRepositoryProvider),
        settingsRepository: ref.watch(settingsRepositoryProvider),
        storageAdminRepository: ref.watch(storageAdminRepositoryProvider),
        musicService: ref.watch(musicServiceContractProvider),
        homeScreenController: () => ref.read(homeScreenControllerProvider),
        playerController: () => ref.read(playerControllerProvider),
        themeController: () => ref.read(themeControllerProvider),
        pipedServices: () => ref.read(pipedServicesProvider),
        // read, NOT watch: a locale change would otherwise dispose and
        // recreate this controller while the settings UI still holds it.
        appLocaleController: ref.read(appLocaleControllerProvider),
        resolverClient: ref.watch(resolverClientProvider),
        resolverDiscovery: ref.watch(resolverDiscoveryServiceProvider),
      );
      unawaited(controller.init());
      return controller;
    });

final searchScreenControllerProvider =
    ChangeNotifierProvider<SearchScreenController>(
      (ref) => SearchScreenController(
        searchHistoryRepository: ref.watch(searchHistoryRepositoryProvider),
        musicService: ref.watch(musicServiceContractProvider),
        // read, NOT watch: watching a ChangeNotifierProvider here rebuilds
        // this provider on every notifyListeners() of that controller —
        // disposing the previous SearchScreenController (and its
        // textInputController) while the mounted search TextField still
        // references it ("TextEditingController was used after being
        // disposed" on every subsequent rebuild).
        playerController: ref.read(playerControllerProvider),
      ),
    );

final desktopSystemTrayProvider = Provider<DesktopSystemTray>(
  (ref) => DesktopSystemTray(
    audioHandler: ref.watch(audioHandlerProvider),
    // read, NOT watch: see searchScreenControllerProvider above.
    playerController: ref.read(playerControllerProvider),
    settingsScreenController: ref.read(settingsScreenControllerProvider),
  ),
);
