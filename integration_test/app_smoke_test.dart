import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/app/providers/app_service_registration.dart';
import 'package:harmonymusic/app/providers/repository_providers.dart';
import 'package:harmonymusic/app/providers/service_providers.dart';
import 'package:harmonymusic/main.dart' as app;
import 'package:integration_test/integration_test.dart';

import 'support/fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots with mocked external service boundaries', (
    tester,
  ) async {
    await app.initHive();
    final container = ProviderContainer(
      overrides: [
        audioHandlerProvider.overrideWithValue(FakeAudioHandler()),
        musicServiceContractProvider.overrideWithValue(FakeMusicService()),
        updateServiceContractProvider.overrideWithValue(
          const FakeUpdateService(),
        ),
        appPlatformContractProvider.overrideWithValue(FakeAppPlatform()),
        filePickerContractProvider.overrideWithValue(FakeFilePicker()),
      ],
    );
    addTearDown(container.dispose);

    await app.setAppInitPrefs(container.read(settingsRepositoryProvider));
    registerAppServices(container);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const app.MyApp()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Home'), findsWidgets);
    expect(find.textContaining('Fixture'), findsWidgets);
  });
}
