import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:harmonymusic/app/navigation/router_provider.dart';
import 'package:harmonymusic/app/providers/repository_providers.dart';
import 'package:harmonymusic/app/providers/service_providers.dart';
import 'package:harmonymusic/domain/repositories/settings_repository.dart';
import 'package:harmonymusic/services/app_contracts.dart';

void main() {
  test('repository providers expose repository contracts', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(settingsRepositoryProvider),
      isA<SettingsRepository>(),
    );
  });

  test('service providers can be overridden in tests', () {
    final fakePlatform = _FakeAppPlatform();
    final container = ProviderContainer(
      overrides: [appPlatformContractProvider.overrideWithValue(fakePlatform)],
    );
    addTearDown(container.dispose);

    expect(container.read(appPlatformContractProvider), same(fakePlatform));
  });

  test('router provider exposes the app router', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(appRouterProvider), isA<GoRouter>());
  });

  test('player controller provider keeps long-lived dependencies stable', () {
    final source = File(
      'lib/app/providers/controller_providers.dart',
    ).readAsStringSync();
    final block = _providerBlock(source, 'playerControllerProvider');

    expect(block, contains('audioHandler: ref.read(audioHandlerProvider)'));
    expect(
      block,
      contains(
        'settingsController: ref.read(settingsScreenControllerProvider)',
      ),
    );
    expect(
      block,
      contains('homeScreenController: ref.read(homeScreenControllerProvider)'),
    );
    expect(block, contains('downloader: ref.read(downloaderProvider)'));
    expect(
      block,
      contains('settingsRepository: ref.read(settingsRepositoryProvider)'),
    );
    expect(
      block,
      contains(
        'playbackSessionRepository: ref.read(playbackSessionRepositoryProvider)',
      ),
    );
    expect(block, isNot(contains('ref.watch(')));
  });

  test('playback command service is an app-scoped Riverpod singleton', () {
    final serviceSource = File(
      'lib/app/providers/service_providers.dart',
    ).readAsStringSync();
    final controllerSource = File(
      'lib/app/providers/controller_providers.dart',
    ).readAsStringSync();
    final serviceBlock = _simpleProviderBlock(
      serviceSource,
      'playbackCommandServiceProvider',
    );
    final playerBlock = _providerBlock(
      controllerSource,
      'playerControllerProvider',
    );

    expect(serviceBlock, contains('Provider<PlaybackCommandService>'));
    expect(
      serviceBlock,
      contains('audioHandler: ref.read(audioHandlerProvider)'),
    );
    expect(
      serviceBlock,
      contains('settingsRepository: ref.read(settingsRepositoryProvider)'),
    );
    expect(
      serviceSource,
      isNot(contains('static final PlaybackCommandService')),
    );
    expect(
      playerBlock,
      contains('playbackCommands: ref.read(playbackCommandServiceProvider)'),
    );
  });
}

String _simpleProviderBlock(String source, String providerName) {
  final start = source.indexOf(providerName);
  expect(start, isNot(-1), reason: 'Missing $providerName');
  final end = source.indexOf('\n);', start);
  expect(end, isNot(-1), reason: 'Missing end for $providerName');
  return source.substring(start, end);
}

String _providerBlock(String source, String providerName) {
  final start = source.indexOf(providerName);
  expect(start, isNot(-1), reason: 'Missing $providerName');
  final returnIndex = source.indexOf('return controller;', start);
  expect(returnIndex, isNot(-1), reason: 'Missing return for $providerName');
  final end = source.indexOf('});', returnIndex);
  expect(end, isNot(-1), reason: 'Missing end for $providerName');
  return source.substring(start, end);
}

class _FakeAppPlatform implements AppPlatformContract {
  @override
  Future<AppPlatformInfo> getAppInfo() async {
    return const AppPlatformInfo(
      appName: 'Harmony Test',
      packageName: 'test.harmony',
      version: '1.0.0',
      buildNumber: '1',
    );
  }

  @override
  Future<void> installApk(String path) async {}

  @override
  Future<void> openUrl(String url) async {}

  @override
  Future<void> restartApp({bool terminate = true}) async {}

  @override
  Future<void> setKeepScreenAwake(bool enable) async {}

  @override
  Future<void> setPlaybackWakeLock(bool enable) async {}

  @override
  Future<void> shareText(String text) async {}
}
