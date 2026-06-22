import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/main.dart' as app;
import 'package:harmonymusic/services/app_contracts.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots with mocked external service boundaries', (
    tester,
  ) async {
    Get.testMode = true;
    Get.reset();

    await app.initHive();
    app.setAppInitPrefs();

    Get.put<AudioHandler>(FakeAudioHandler(), permanent: true);
    Get.put<MusicServiceContract>(FakeMusicService(), permanent: true);
    Get.put<DownloaderContract>(FakeDownloader(), permanent: true);
    Get.put<UpdateServiceContract>(const FakeUpdateService(), permanent: true);
    Get.put<AppPlatformContract>(FakeAppPlatform(), permanent: true);
    Get.put<FilePickerContract>(FakeFilePicker(), permanent: true);

    await app.startApplicationServices();
    await tester.pumpWidget(const app.MyApp());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Home'), findsWidgets);
    expect(find.textContaining('Fixture'), findsWidgets);
  });
}
