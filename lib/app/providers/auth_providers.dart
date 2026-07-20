import 'dart:async';

import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../services/auth0_service.dart';
import '../../data/repositories/cloud_sync_repository.dart';
import '../../services/cloud/cloud_sync_coordinator.dart';
import '../../services/cloud/cloud_audio_backup_service.dart';
import '../../services/cloud/harmony_cloud_client.dart';
import '../../services/resolver/resolver_client.dart';
import '../../services/resolver/resolver_discovery_service.dart';
import 'repository_providers.dart';

final auth0ServiceProvider = Provider<Auth0Service>(
  (ref) => Auth0Service.create(),
);

final resolverClientProvider = Provider<ResolverClient>(
  (ref) =>
      ResolverClient(accessToken: ref.watch(auth0ServiceProvider).accessToken),
);

final resolverDiscoveryServiceProvider = Provider<ResolverDiscoveryService>(
  (ref) => ResolverDiscoveryService(),
);

final authControllerProvider = ChangeNotifierProvider<AuthController>((ref) {
  final controller = AuthController(
    ref.watch(auth0ServiceProvider),
    ref.watch(cloudSyncCoordinatorProvider),
  );
  unawaited(controller.init());
  return controller;
});

final cloudSyncCoordinatorProvider = Provider<CloudSyncCoordinator>((ref) {
  final auth = ref.watch(auth0ServiceProvider);
  final repository = CloudSyncRepository(ref.watch(playlistRepositoryProvider));
  final client = HarmonyCloudClient(accessToken: auth.accessToken);
  return CloudSyncCoordinator(
    repository,
    client,
    CloudAudioBackupService(
      ref.watch(downloadRepositoryProvider),
      repository,
      client,
    ),
  );
});

class AuthController extends ChangeNotifier {
  AuthController(this._service, this._cloud);

  final Auth0Service _service;
  final CloudSyncCoordinator _cloud;
  UserProfile? userProfile;
  bool isBusy = false;
  bool cloudBackupRunning = false;
  String? errorMessage;

  bool get isConfigured => _service.isConfigured;
  bool get isSupportedPlatform => _service.isSupportedPlatform;
  bool get isAvailable => _service.isAvailable;
  bool get isAuthenticated => userProfile != null;
  bool get cloudSyncEnabled => _cloud.enabled;
  bool get needsCloudOptIn => isAuthenticated && _cloud.needsOptIn;

  Future<void> init() async {
    userProfile = await _service.tryRestoreSession();
    if (userProfile != null && _cloud.enabled) unawaited(_cloud.synchronize());
    notifyListeners();
  }

  Future<void> login() async => _run(() async {
    userProfile = await _service.login();
    if (_cloud.enabled) unawaited(_cloud.synchronize());
  });

  Future<void> logout() async => _run(() async {
    await _service.logout();
    userProfile = null;
  });

  Future<void> setCloudSyncEnabled(bool value) async {
    await _cloud.setEnabled(value);
    notifyListeners();
  }

  Future<CloudAudioBackupResult> backupCloudAudioNow({
    bool overrideBatteryPolicy = false,
  }) async {
    if (cloudBackupRunning) return CloudAudioBackupResult.alreadyRunning;
    cloudBackupRunning = true;
    notifyListeners();
    try {
      return await _cloud.backupAudioNow(
        overrideBatteryPolicy: overrideBatteryPolicy,
      );
    } finally {
      cloudBackupRunning = false;
      notifyListeners();
    }
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
