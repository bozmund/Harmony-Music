import 'dart:async';

import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../services/app_contracts.dart';
import '../../services/auth0_service.dart';
import '../../data/repositories/cloud_sync_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../services/cloud/cloud_sync_coordinator.dart';
import '../../services/cloud/harmony_cloud_client.dart';
import '../../services/cloud/cloud_fcm_service.dart';
import '../../services/cloud/playback_socket_client.dart';
import '../../services/resolver/resolver_client.dart';
import '../../services/resolver/resolver_discovery_service.dart';
import '../../ui/screens/Library/library_controller.dart';
import 'repository_providers.dart';

final auth0ServiceProvider = Provider<Auth0Service>((ref) {
  final service = Auth0Service.create();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

/// Indirection so tests can substitute a fake without `auth0ServiceProvider`
/// itself needing to return anything other than a real `Auth0Service` —
/// mirrors `musicServiceContractProvider` over `musicServicesProvider`.
final authServiceContractProvider = Provider<AuthServiceContract>(
  (ref) => ref.watch(auth0ServiceProvider),
);

final resolverClientProvider = Provider<ResolverClient>(
  (ref) =>
      ResolverClient(accessToken: ref.watch(auth0ServiceProvider).accessToken),
);

final resolverDiscoveryServiceProvider = Provider<ResolverDiscoveryService>(
  (ref) => ResolverDiscoveryService(),
);

/// The one realtime channel for cloud playback. Shares the Cloud client's base
/// URL so both speak to the same deployment.
final playbackSocketClientProvider = Provider<PlaybackSocketClient>((ref) {
  final client = PlaybackSocketClient(
    accessToken: ref.watch(auth0ServiceProvider).accessToken,
    baseUrl: HarmonyCloudClient.defaultBaseUrl,
  );
  ref.onDispose(() => unawaited(client.dispose()));
  return client;
});

/// Starts FCM registration for a signed-in device. A real, uninjected
/// `CloudFcmService(...).start()` call inside `AuthController` would call
/// `Firebase.initializeApp()` on every test process, whether or not that
/// process has Firebase configured — this indirection is what lets tests
/// substitute a no-op instead, the same way `authServiceContractProvider`
/// lets them substitute auth.
final fcmStarterProvider =
    Provider<Future<void> Function(Future<void> Function(String))>(
      (ref) => (registerToken) => CloudFcmService(registerToken).start(),
    );

final authControllerProvider = ChangeNotifierProvider<AuthController>((ref) {
  final controller = AuthController(
    ref.watch(authServiceContractProvider),
    ref.watch(cloudSyncCoordinatorProvider),
    ref.watch(settingsRepositoryProvider),
    fcmStarter: ref.watch(fcmStarterProvider),
  );
  unawaited(controller.init());
  return controller;
});

final cloudSyncCoordinatorProvider = Provider<CloudSyncCoordinator>((ref) {
  final auth = ref.watch(auth0ServiceProvider);
  final repository = CloudSyncRepository(ref.watch(playlistRepositoryProvider));
  final client = HarmonyCloudClient(accessToken: auth.accessToken);
  // Same socket playback already uses — a `libraryChanged` frame is how a
  // device left open hears about another device's edit immediately, instead
  // of waiting on the poll timer.
  return CloudSyncCoordinator(
    repository,
    client,
    socket: ref.watch(playbackSocketClientProvider),
  );
});

class AuthController extends ChangeNotifier {
  AuthController(
    this._service,
    this._cloud,
    this._settings, {
    required Future<void> Function(Future<void> Function(String))
    fcmStarter,
  }) : _fcmStarter = fcmStarter {
    _revocationSubscription = _service.onSessionRevoked.listen(
      (_) => unawaited(_onSessionRevoked()),
    );
  }

  final AuthServiceContract _service;
  StreamSubscription<void>? _revocationSubscription;
  final CloudSyncCoordinator _cloud;
  final SettingsRepository _settings;
  final Future<void> Function(Future<void> Function(String)) _fcmStarter;
  UserProfile? userProfile;
  bool isBusy = false;
  String? errorMessage;

  /// Whether the user has dismissed the Library banner for this app run.
  ///
  /// Deliberately separate from [needsReauthentication]: dismissing the banner
  /// is "stop interrupting me", not "this is resolved". Folding both into one
  /// flag also cleared the settings badge, which is the one thing meant to
  /// persist until the session is genuinely restored.
  bool sessionExpiredNoticeDismissed = false;

  bool get isConfigured => _service.isConfigured;
  bool get isSupportedPlatform => _service.isSupportedPlatform;
  bool get isAvailable => _service.isAvailable;
  bool get isAuthenticated => userProfile != null;
  bool get cloudSyncEnabled => _cloud.enabled;

  /// Whether this device advertises what it is playing, so another device can
  /// subscribe to it as a remote.
  bool get shareNowPlaying => _cloud.shareNowPlaying;
  bool get needsCloudOptIn => isAuthenticated && _cloud.needsOptIn;

  /// The account this device's library belongs to, even while signed out.
  String? get accountSubject => _settings.getCloudAccountSubject();

  /// Whether this device belongs to an account nobody is currently signed in
  /// to, with sync turned on — so library edits are piling up locally and
  /// reaching no account. Drives the settings badge, which stays until the
  /// user signs back in.
  ///
  /// Derived rather than flagged, because the state is the same however it was
  /// arrived at: a token that quietly lapsed, or a deliberate sign-out. Only
  /// the first of those used to say anything, so signing out and carrying on
  /// adding albums looked exactly like a working, syncing library.
  bool get needsReauthentication =>
      !isAuthenticated && accountSubject != null && cloudSyncEnabled;

  /// Whether the Library banner should be shown — the same state, minus the
  /// interruption once the user has acknowledged it.
  bool get showSessionExpiredBanner =>
      needsReauthentication && !sessionExpiredNoticeDismissed;

  void dismissSessionExpiredNotice() {
    sessionExpiredNoticeDismissed = true;
    notifyListeners();
  }

  Future<List<CloudPlaybackDevice>> playbackDevices() =>
      _cloud.playbackDevices();

  /// The account's open playback session, if any.
  ///
  /// The device list only says which device *owns* the session, which outlives
  /// the playback that created it. This says whether that device is actually
  /// playing right now.
  Future<CloudPlaybackSession?> playbackSession() => _cloud.playbackSession();

  Future<void> removePlaybackDevice(String deviceId) =>
      _cloud.removePlaybackDevice(deviceId);

  Future<bool> handoffPlayback({
    required String targetDeviceId,
    required Map<String, Object?> payload,
  }) =>
      _cloud.handoffPlayback(targetDeviceId: targetDeviceId, payload: payload);

  Future<bool> refreshAccessToken() async {
    if (!isAuthenticated) return false;
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      return await _service.accessToken(forceRefresh: true) != null;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> init() async {
    userProfile = await _service.tryRestoreSession();
    if (userProfile != null) {
      // A restored session is by definition the account this device already
      // belongs to. Recording it here — rather than treating a missing subject
      // as a first sign-in — is what stops every existing install from being
      // asked to merge or replace on first launch after the upgrade.
      await _settings.setCloudAccountSubject(userProfile!.sub);
      unawaited(_activateDeviceControl());
      if (_cloud.enabled) unawaited(_startCloudSync());
    }
    // A stored account with no restorable session means the token lapsed; the
    // banner follows from that state rather than needing to be flagged here.
    notifyListeners();
  }

  /// Signals a first interactive sign-in on a device that already holds a
  /// library, so the caller can ask whether to merge it into the account or
  /// replace it. Null means nothing to decide.
  Future<bool> Function()? onFirstSignInWithLocalLibrary;

  Future<void> login({bool chooseAccount = false}) async => _run(() async {
    final previousAccount = _settings.getCloudAccountSubject();
    userProfile = await _service.login(chooseAccount: chooseAccount);
    final subject = userProfile?.sub;
    if (subject == null) return;
    sessionExpiredNoticeDismissed = false;

    if (previousAccount != null && previousAccount != subject) {
      // A different account: this device's synced library belongs to someone
      // else and must not become part of the new one.
      await _cloud.forgetAccountLibrary();
    } else if (previousAccount == null &&
        (await onFirstSignInWithLocalLibrary?.call() ?? false)) {
      await _cloud.forgetAccountLibrary();
    }

    await _settings.setCloudAccountSubject(subject);
    // The Songs tab scopes itself to the stored account, but only reads it
    // when its controller initialises — so signing in (or switching accounts)
    // mid-session left it showing the previous, unscoped list until the next
    // launch, including music that had just been wiped.
    unawaited(LibrarySongsControllerRegistry.current?.reloadSongs());
    unawaited(_activateDeviceControl());
    if (_cloud.enabled) unawaited(_startCloudSync());
  });

  /// The session died under us. This is the same end state as a deliberate
  /// sign-out — the device keeps its library and its account subject, so
  /// [needsReauthentication] turns true and the banner and settings badge
  /// appear — except nobody asked for it, so it must not wait for a relaunch to
  /// be admitted. Clearing the subject here would instead make the device look
  /// like it never belonged to an account and silence the very warning this
  /// exists to raise.
  Future<void> _onSessionRevoked() async {
    if (userProfile == null) return;
    userProfile = null;
    sessionExpiredNoticeDismissed = false;
    notifyListeners();
    await _cloud.stop();
  }

  @override
  void dispose() {
    unawaited(_revocationSubscription?.cancel());
    super.dispose();
  }

  Future<void> logout() async => _run(() async {
    await _cloud.stop();
    await _service.logout();
    userProfile = null;
    // The device keeps its library and its account subject, so edits made from
    // here on reach nobody until the user signs back in. Re-arm the notice: a
    // dismissal earlier in this run answered a different sign-out.
    sessionExpiredNoticeDismissed = false;
  });

  Future<void> setShareNowPlaying(bool value) async {
    await _cloud.setShareNowPlaying(value);
    notifyListeners();
  }

  Future<void> setCloudSyncEnabled(bool value) async {
    await _cloud.setEnabled(value);
    notifyListeners();
    // A first sync can scan a large local library and must not make the
    // settings switch appear unresponsive while that work is in progress.
    if (value) {
      unawaited(_startCloudSync());
    } else {
      unawaited(_cloud.stop());
    }
  }

  /// Syncs now, then keeps watching: local edits push within a couple of
  /// seconds and other devices' edits are pulled on a timer, instead of both
  /// waiting for the next app launch.
  Future<void> _startCloudSync() async {
    await _cloud.synchronize();
    await _cloud.start();
  }

  /// Pulls anything other devices wrote while this one was in the background.
  Future<void> onAppResumed() async {
    if (userProfile == null || !_cloud.enabled) return;
    await _cloud.synchronize();
  }

  Future<void> _activateDeviceControl() async {
    await _cloud.registerCurrentDevice();
    await _fcmStarter(_cloud.registerFcmToken);
  }

  Future<void> _run(Future<void> Function() action) async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }
}
