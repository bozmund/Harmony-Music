/// Browser builds use the web audio implementation and have no desktop media
/// session integration to configure.
class DesktopAudioPlatform {
  static void register() {}

  static Future<void> initializeWindowsMediaControls() async {}

  static void configure({
    required void Function(String category, String message) onDiagnostic,
  }) {}
}
