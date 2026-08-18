import 'package:just_audio_media_kit/just_audio_media_kit.dart';
// ignore: implementation_imports, depend_on_referenced_packages
import 'package:media_kit/src/player/platform_player.dart' show MPVLogLevel;
import 'package:smtc_windows/smtc_windows.dart';

class DesktopAudioPlatform {
  static void register() {
    JustAudioMediaKit.registerWith();
  }

  static Future<void> initializeWindowsMediaControls() =>
      SMTCWindows.initialize();

  static void configure({
    required void Function(String category, String message) onDiagnostic,
  }) {
    JustAudioMediaKit.title = 'Harmony music';
    JustAudioMediaKit.protocolWhitelist = const ['http', 'https', 'file'];
    // The library defaults to `error`, which is below the level the endpoint
    // diagnostics need: `audio-device` and `audio-params` arrive as mpv
    // warnings, so leaving this unset silently empties [onDiagnostic].
    JustAudioMediaKit.mpvLogLevel = MPVLogLevel.warn;
    JustAudioMediaKit.diagnosticCallback = onDiagnostic;
  }
}
