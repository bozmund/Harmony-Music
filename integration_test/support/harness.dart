import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/app/providers/app_service_registration.dart';
import 'package:harmonymusic/app/providers/auth_providers.dart';
import 'package:harmonymusic/app/providers/repository_providers.dart';
import 'package:harmonymusic/app/providers/service_providers.dart';
import 'package:harmonymusic/data/repositories/cloud_sync_repository.dart';
import 'package:harmonymusic/data/repositories/hive_playlist_repository.dart';
import 'package:harmonymusic/domain/repositories/lyrics_repository.dart';
import 'package:harmonymusic/main.dart' as app;
import 'package:harmonymusic/services/app_contracts.dart';
import 'package:harmonymusic/services/cloud/cloud_playback_gateway.dart';
import 'package:harmonymusic/services/cloud/cloud_sync_coordinator.dart';
import 'package:harmonymusic/services/cloud/harmony_cloud_client.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:harmonymusic/services/playback_command_service.dart';
import 'package:harmonymusic/services/release_prompt.dart';
import 'package:harmonymusic/utils/house_keeping.dart';
import 'package:hive/hive.dart';

import 'fakes.dart';

/// `AudioService.init` wires a single static handler into the plugin's
/// platform channel and can only be called once per test process — a second
/// call throws. Every `bootTestApp` in a file therefore shares this one
/// [FakeAudioHandler], reset between boots rather than replaced, instead of
/// each override constructing (and never registering) its own instance —
/// the gap that used to leave `AudioService.createPositionStream()` reading
/// an uninitialized handler and throwing `LateInitializationError`.
FakeAudioHandler? _sharedTestAudioHandler;

Future<FakeAudioHandler> _testAudioHandler() async {
  final existing = _sharedTestAudioHandler;
  if (existing != null) {
    existing.reset();
    return existing;
  }
  final handler = await AudioService.init(
    builder: () => FakeAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationIcon: 'mipmap/ic_launcher_monochrome',
      androidNotificationChannelId: 'com.anandnet.harmonymusic.test.audio',
      androidNotificationChannelName: 'Harmony Music Test Audio',
    ),
  );
  return _sharedTestAudioHandler = handler;
}

/// What a booted test app hands back so a scenario can keep driving it —
/// mainly the [FakeAuthService], whose `restorableSession`/`nextLogin` a test
/// mutates mid-run to simulate a lapsed session or a different account
/// signing in.
class TestAppHandle {
  TestAppHandle({
    required this.container,
    required this.authService,
    required this.downloader,
    required this.audioHandler,
  });

  final ProviderContainer container;
  final FakeAuthService authService;
  final FakeDownloader downloader;
  final FakeAudioHandler audioHandler;
}

/// Boots the real app against an isolated, per-test Hive directory with the
/// network and platform boundaries faked — the same shape as
/// `app_smoke_test.dart`'s boot sequence, extended with the auth and cloud
/// sync fakes this feature needs.
///
/// A fresh temp directory per call (rather than `app.initHive()`'s real
/// application-support path) is what keeps scenarios independent: two
/// `testWidgets` in the same file must not see each other's Hive state the
/// way two runs sharing one real device directory would.
///
/// [seedHive] runs after the standard boxes are open but before the widget
/// tree is pumped, so a scenario can seed "this device already has a library"
/// or "this box already has a fingerprint" before the app ever boots — mirrors
/// how the unit tests seed state ahead of the operation under test.
/// [cloudSyncEnabled] answers the cloud opt-in prompt either way — what
/// differs is the answer. Off by default (nothing here needs the sync loop
/// running); on for scenarios that depend on sync actually being active, such
/// as session expiry, which `AuthController.init()` only reports when a known
/// account has sync turned on.
Future<TestAppHandle> bootTestApp(
  WidgetTester tester, {
  FakeAuthService? authService,
  LyricsRepository? lyricsRepository,
  MusicServiceContract? musicService,
  CloudPlaybackGateway? playbackGateway,
  Future<void> Function()? seedHive,
  bool cloudSyncEnabled = false,
  bool autoOpenPlayer = false,
}) async {
  // resolverClientProvider and playbackSocketClientProvider construct a real
  // Auth0Service directly (see auth_providers.dart) regardless of the
  // authServiceContractProvider override above, and Auth0Service.create()
  // reads dotenv unconditionally — without this, mounting those providers
  // throws NotInitializedError before a single frame renders.
  if (!dotenv.isInitialized) {
    await dotenv.load(fileName: '.env', isOptional: true);
  }

  final hiveDir = await Directory.systemTemp.createTemp('harmony_it_');
  addTearDown(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });
  Hive.init(hiveDir.path);
  for (final box in const [
    BoxNames.songsCache,
    BoxNames.songDownloads,
    BoxNames.songsUrlCache,
    BoxNames.appPrefs,
    BoxNames.libFav,
    BoxNames.cloudSyncOutbox,
    BoxNames.cloudSyncState,
  ]) {
    await Hive.openBox(box);
  }
  // `getAutoOpenPlayer()` defaults to true in production, which on a
  // phone-width device makes the full player take over the moment a song
  // starts — so `find.byType(MiniPlayer)` finds nothing and the assertion
  // outcome depends on the screen size of whatever device the suite happens to
  // run on. Pin it here so layout is deterministic, and let the tests that
  // actually care about the auto-open behaviour opt back in.
  await Hive.box(BoxNames.appPrefs).put(PrefKeys.autoOpenPlayer, autoOpenPlayer);

  if (seedHive != null) await seedHive();

  final auth = authService ?? FakeAuthService();
  final audioHandler = await _testAudioHandler();
  PlaybackCommandService? bridgePlaybackCommands;
  final container = ProviderContainer(
    overrides: [
      audioHandlerProvider.overrideWithValue(audioHandler),
      musicServiceContractProvider.overrideWithValue(
        musicService ?? FakeMusicService(),
      ),
      if (playbackGateway != null)
        playbackCommandServiceProvider.overrideWith(
          (ref) => bridgePlaybackCommands ??= PlaybackCommandService(
            audioHandler: audioHandler,
            settingsRepository: ref.read(settingsRepositoryProvider),
            cloudSync: playbackGateway,
          ),
        ),
      if (lyricsRepository != null)
        lyricsRepositoryProvider.overrideWithValue(lyricsRepository),
      updateServiceContractProvider.overrideWithValue(
        const FakeUpdateService(),
      ),
      appPlatformContractProvider.overrideWithValue(FakeAppPlatform()),
      filePickerContractProvider.overrideWithValue(FakeFilePicker()),
      authServiceContractProvider.overrideWithValue(auth),
      // Real CloudFcmService.start() calls Firebase.initializeApp(), which
      // this test process has no Firebase configuration for. See
      // fcmStarterProvider's doc comment.
      fcmStarterProvider.overrideWithValue((_) async {}),
      // Real Downloader.download() ends in a genuine network fetch; see
      // FakeDownloader's doc comment for why every scenario needs this.
      downloaderProvider.overrideWith(
        (ref) => FakeDownloader(
          ref.watch(downloadRepositoryProvider),
          ref.watch(settingsRepositoryProvider),
        ),
      ),
      // Network never leaves the process: registerDevice/sync/pause all hit
      // fakeCloudDio(), so what's under test is the local wipe/merge/filter
      // logic, not a real Resolver round trip.
      cloudSyncCoordinatorProvider.overrideWithValue(
        CloudSyncCoordinator(
          CloudSyncRepository(HivePlaylistRepository()),
          HarmonyCloudClient(
            dio: fakeCloudDio(),
            accessToken: () async => 'fake-access-token',
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);

  final settings = container.read(settingsRepositoryProvider);
  await app.setAppInitPrefs(settings);
  // Real, unawaited Android permission request on first run
  // (SettingsScreenController._requestIgnoringBatteryOptimizationsOnInstall).
  // Harmless on a real device, but every bootTestApp in a file is a "first
  // run" against its own fresh settings box, and the plugin only allows one
  // request in flight process-wide — the second boot's request throws
  // "already running" as an uncaught async error attributed to whatever test
  // happens to be current when it lands. Pre-marking it shown skips it.
  await settings.setBatteryOptimizationPromptShown(true);
  // The home screen's one-time release prompt (currently the 6.0.0 update
  // channel choice) is a modal dialog on first launch — against a fresh
  // settings box that's every boot, and it sits on top of the bottom nav,
  // turning the very first `tester.tap` on a nav icon into a silent miss.
  final prompt = currentReleasePrompt;
  if (prompt != null) {
    await settings.setReleasePromptAnswered(prompt.id);
  }
  // The startup update check (HomeScreenController._checkNewVersion) calls a
  // free `newVersionCheck()` function that hits the real GitHub API directly —
  // it does not go through updateServiceContractProvider, so nothing in the
  // override list above reaches it. Left on, its real network round trip
  // resolves at an arbitrary point during a *later* test in the same file and
  // pops a real NewVersionDialog over whatever that test is doing, which
  // absorbs its next tap. Turning the popup off entirely is the only seam
  // available short of faking DNS/HTTP.
  await settings.setNewVersionVisibility(false);
  // One-time housekeeping (removeThinCachedSongs) purges any SongsCache entry
  // without an `album.id`, on the assumption a real device's existing cache
  // predates rich metadata — but every hand-seeded cache fixture looks exactly
  // like that thin-metadata shape unless a test deliberately adds an album, so
  // it would otherwise vanish before the first frame the test inspects.
  await settings.setSongCachePurgeVersion(thinCachePurgeVersion);
  // SettingsScreen shows a real "Harmony Cloud backup" opt-in dialog
  // (_showCloudOptInDialog) the moment an authenticated session has never
  // answered it — which every fresh sign-in in a test is, unless a scenario
  // specifically wants to exercise that prompt. Left up, it stacks on top of
  // whatever dialog the test just triggered (e.g. the merge/replace prompt)
  // and absorbs the next tap. Pre-answering "not now" keeps sync off, which
  // also means these tests never need to fake the sync network path.
  await container
      .read(cloudSyncCoordinatorProvider)
      .setEnabled(cloudSyncEnabled);
  registerAppServices(container);

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const app.MyApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 2));

  return TestAppHandle(
    container: container,
    authService: auth,
    downloader: container.read(downloaderProvider) as FakeDownloader,
    audioHandler: audioHandler,
  );
}
