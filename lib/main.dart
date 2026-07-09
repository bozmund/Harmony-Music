import 'dart:async';
import 'dart:ui' as ui;
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'app/providers/app_service_registration.dart';
import 'app/providers/app_locale_provider.dart';
import 'app/providers/controller_providers.dart';
import 'app/providers/repository_providers.dart';
import 'app/providers/service_providers.dart';
import 'app/navigation/router_provider.dart';
import 'domain/repositories/settings_repository.dart';
import 'l10n/app_localizations.dart';
import '/services/constant.dart';
import 'services/app_contracts.dart';
import 'services/app_platform_service.dart';
import 'services/crash_diagnostics_service.dart';
import 'services/system_ui_mode_service.dart';
import 'utils/app_link_controller.dart';
import '/services/audio_handler.dart';
import 'ui/widgets/system_ui_mode_scope.dart';
import 'utils/runtime_platform.dart';
import 'utils/insets.dart';
import 'utils/update_check_flag_file.dart';

late final ProviderContainer appProviderContainer;
AppLinksController? appLinksController;

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await CrashDiagnosticsService.instance.init();
      _installCrashDiagnosticsHandlers();
      _configureFlutterImageCache();
      await initHive();
      final bootstrapContainer = ProviderContainer();
      await setAppInitPrefs(
        bootstrapContainer.read(settingsRepositoryProvider),
      );
      final audioHandler = await initAudioService(
        settingsRepository: bootstrapContainer.read(settingsRepositoryProvider),
        libraryRepository: bootstrapContainer.read(libraryRepositoryProvider),
        downloadRepository: bootstrapContainer.read(downloadRepositoryProvider),
        songCacheRepository: bootstrapContainer.read(
          songCacheRepositoryProvider,
        ),
        playlistRepository: bootstrapContainer.read(playlistRepositoryProvider),
        playbackSessionRepository: bootstrapContainer.read(
          playbackSessionRepositoryProvider,
        ),
      );
      bootstrapContainer.dispose();
      final systemUiModeService = await _createSystemUiModeService();
      appProviderContainer = ProviderContainer(
        overrides: [
          audioHandlerProvider.overrideWithValue(audioHandler),
          systemUiModeServiceProvider.overrideWithValue(systemUiModeService),
        ],
      );
      registerAppServices(appProviderContainer);
      WidgetsBinding.instance.addObserver(LifecycleHandler(audioHandler));
      runApp(
        UncontrolledProviderScope(
          container: appProviderContainer,
          child: const MyApp(),
        ),
      );
    },
    (error, stackTrace) {
      CrashDiagnosticsService.instance.recordZoneError(error, stackTrace);
    },
  );
}

Future<SystemUiModeService> _createSystemUiModeService() async {
  final service = SystemUiModeService(
    immersiveAllowed: !RuntimePlatform.isAndroid,
  );
  if (!RuntimePlatform.isAndroid) return service;

  final navigationMode = await const DefaultAppPlatformService()
      .getSystemNavigationMode();
  service.setImmersiveAllowed(navigationMode == SystemNavigationMode.gesture);
  return service;
}

void _installCrashDiagnosticsHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    CrashDiagnosticsService.instance.recordFlutterError(details);
  };
  ui.PlatformDispatcher.instance.onError = (error, stackTrace) {
    CrashDiagnosticsService.instance.recordPlatformError(error, stackTrace);
    return false;
  };
}

void _configureFlutterImageCache() {
  final imageCache = PaintingBinding.instance.imageCache;
  imageCache.maximumSize = 120;
  imageCache.maximumSizeBytes = 48 * 1024 * 1024;
  CrashDiagnosticsService.instance.record(
    'cache',
    'configured Flutter image cache maxImages=${imageCache.maximumSize}'
        ' maxBytes=${imageCache.maximumSizeBytes}',
    includeMemory: true,
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!RuntimePlatform.isDesktop) {
      appLinksController ??= AppLinksController(
        musicService: ref.read(musicServiceContractProvider),
        playerController: ref.read(playerControllerProvider),
      );
    }
    final themeController = ref.watch(themeControllerProvider);
    final appLocaleController = ref.watch(appLocaleControllerProvider);
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Harmony Music',
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: appLocaleController.locale,
      builder: (context, child) {
        final mQuery = MediaQuery.of(context);
        final scale = mQuery.textScaler.clamp(
          minScaleFactor: 1.0,
          maxScaleFactor: 1.1,
        );
        return SystemUiModeScope.edgeToEdge(
          child: Stack(
            children: [
              AnimatedBuilder(
                animation: themeController,
                builder: (context, _) => MediaQuery(
                  data: mQuery.copyWith(textScaler: scale),
                  child: AnimatedTheme(
                    duration: const Duration(milliseconds: 700),
                    data: themeController.themeData.value ?? ThemeData.dark(),
                    child: child!,
                  ),
                ),
              ),
              GestureDetector(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    color: Colors.transparent,
                    height: bottomNavInset(context),
                    width: mQuery.size.width,
                  ),
                ),
              ),
              if (!kReleaseMode &&
                  CrashDiagnosticsService.instance.previousSessionCrashed)
                const _DiagnosticsStartupNotice(),
            ],
          ),
        );
      },
    );
  }
}

Future<void> initHive() async {
  String applicationDataDirectoryPath;
  if (RuntimePlatform.isDesktop) {
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
  LifecycleHandler(this._audioHandler);

  final AudioHandler _audioHandler;

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    CrashDiagnosticsService.instance.record(
      'lifecycle',
      state.name,
      includeMemory: true,
      flush: state != AppLifecycleState.resumed,
    );
    if (state == AppLifecycleState.resumed) {
      // SystemUiModeScope owns edge-to-edge / immersive restoration for the
      // currently mounted app surfaces.
    } else if (state == AppLifecycleState.paused) {
      // Back on the home tab now minimizes (predictive-back standard) instead
      // of hard-exiting, so persist the session whenever we go to background.
      await _audioHandler.customAction("saveSession");
    } else if (state == AppLifecycleState.detached) {
      await _audioHandler.customAction("saveSession");
      await CrashDiagnosticsService.instance.markCleanShutdown();
    }
  }
}

class _DiagnosticsStartupNotice extends StatefulWidget {
  const _DiagnosticsStartupNotice();

  @override
  State<_DiagnosticsStartupNotice> createState() =>
      _DiagnosticsStartupNoticeState();
}

class _DiagnosticsStartupNoticeState extends State<_DiagnosticsStartupNotice> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _shown) return;
      _shown = true;
      final diagnostics = CrashDiagnosticsService.instance;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(
            'Previous app session ended unexpectedly. Diagnostic log saved at ${diagnostics.logPath}.',
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
