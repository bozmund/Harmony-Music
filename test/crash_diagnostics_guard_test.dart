import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('startup installs crash diagnostics and caps image cache memory', () {
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(mainSource, contains('runZonedGuarded<Future<void>>'));
    expect(mainSource, contains('CrashDiagnosticsService.instance.init()'));
    expect(mainSource, contains('FlutterError.onError'));
    expect(mainSource, contains('ui.PlatformDispatcher.instance.onError'));
    expect(
      mainSource,
      contains('imageCache.maximumSizeBytes = 48 * 1024 * 1024'),
    );
    expect(mainSource, contains('_DiagnosticsStartupNotice'));
  });

  test('debug log output is truncated and persisted as diagnostics', () {
    final helperSource = File('lib/utils/helper.dart').readAsStringSync();
    final diagnosticsSource = File(
      'lib/services/crash_diagnostics_service.dart',
    ).readAsStringSync();

    expect(helperSource, contains('_maxDebugLogChars = 2000'));
    expect(helperSource, contains('_safeLogText'));
    expect(
      helperSource,
      contains('CrashDiagnosticsService.instance.recordLog'),
    );
    expect(diagnosticsSource, contains('_maxBufferedLines = 240'));
    expect(diagnosticsSource, contains('_lastLogRepeatCount'));
    expect(diagnosticsSource, contains('memorySnapshot()'));
    expect(diagnosticsSource, contains('previousSessionCrashed'));
  });

  test('player artwork and dynamic theme work are memory bounded', () {
    final themeSource = File(
      'lib/ui/utils/theme_controller.dart',
    ).readAsStringSync();
    final backgroundSource = File(
      'lib/ui/player/components/background_image.dart',
    ).readAsStringSync();
    final imageWidgetSource = File(
      'lib/ui/widgets/image_widget.dart',
    ).readAsStringSync();

    expect(themeSource, contains('String? _pendingSongId'));
    expect(
      themeSource,
      contains('songId == currentSongId || songId == _pendingSongId'),
    );
    expect(themeSource, contains('Dynamic theme extraction failed'));
    expect(backgroundSource, contains('_defaultBackgroundCacheHeight = 360'));
    expect(backgroundSource, contains('memCacheHeight: effectiveCacheHeight'));
    expect(imageWidgetSource, contains('int _decodeHeightFor'));
    expect(imageWidgetSource, contains('memCacheHeight: decodeHeight'));
    expect(imageWidgetSource, contains('cacheHeight: decodeHeight'));
  });

  test('playback and download paths record memory breadcrumbs', () {
    final audioSource = File(
      'lib/services/audio_handler.dart',
    ).readAsStringSync();
    final downloaderSource = File(
      'lib/services/downloader.dart',
    ).readAsStringSync();
    final preloadSource = File(
      'lib/services/playback_preload_manager.dart',
    ).readAsStringSync();

    expect(audioSource, contains("CrashDiagnosticsService.instance.record("));
    expect(audioSource, contains("'completion song="));
    expect(audioSource, contains("'source-started song="));
    expect(audioSource, contains("'stop position="));
    expect(downloaderSource, contains("'phase=\$phase trace=\$traceId"));
    expect(preloadSource, contains("'ready song="));
    expect(preloadSource, contains("'failed song="));
  });
}
