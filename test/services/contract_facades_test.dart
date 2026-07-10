import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/app_contracts.dart';
import 'package:harmonymusic/services/app_platform_service.dart';
import 'package:harmonymusic/utils/helper.dart';
import 'package:mocktail/mocktail.dart';

class _MockUpdateService extends Mock implements UpdateServiceContract {}

class _MockAppPlatform extends Mock implements AppPlatformContract {}

void main() {
  setUp(() {
    newVersionCheckOverride = null;
    AppPlatformService.override = null;
  });

  tearDown(() {
    newVersionCheckOverride = null;
    AppPlatformService.override = null;
  });

  test('newVersionCheck delegates to registered update service', () async {
    final updateService = _MockUpdateService();
    const update = UpdateInfo(
      channel: UpdateChannel.rolling,
      version: 'main-latest',
      downloadUrl: 'https://example.test/app.apk',
      sha: 'abc1234',
    );

    when(
      () => updateService.checkNewVersion(
        '5.9.2',
        channel: UpdateChannel.rolling,
      ),
    ).thenAnswer((_) async => update);

    newVersionCheckOverride = updateService;

    final result = await newVersionCheck(
      '5.9.2',
      channel: UpdateChannel.rolling,
    );

    expect(result, update);
    verify(
      () => updateService.checkNewVersion(
        '5.9.2',
        channel: UpdateChannel.rolling,
      ),
    ).called(1);
  });

  test(
    'AppPlatformService delegates native actions to registered contract',
    () async {
      final platform = _MockAppPlatform();
      when(
        () => platform.openUrl('https://example.test'),
      ).thenAnswer((_) async {});
      when(() => platform.installApk('/tmp/app.apk')).thenAnswer((_) async {});
      when(() => platform.setPlaybackWakeLock(true)).thenAnswer((_) async {});
      when(
        () => platform.getSystemNavigationMode(),
      ).thenAnswer((_) async => SystemNavigationMode.buttons);

      AppPlatformService.override = platform;

      await AppPlatformService.openUrl('https://example.test');
      await AppPlatformService.installApk('/tmp/app.apk');
      await AppPlatformService.setPlaybackWakeLock(true);
      final navigationMode = await AppPlatformService.getSystemNavigationMode();

      verify(() => platform.openUrl('https://example.test')).called(1);
      verify(() => platform.installApk('/tmp/app.apk')).called(1);
      verify(() => platform.setPlaybackWakeLock(true)).called(1);
      verify(() => platform.getSystemNavigationMode()).called(1);
      expect(navigationMode, SystemNavigationMode.buttons);
    },
  );
}
