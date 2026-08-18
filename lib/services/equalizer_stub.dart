/// Browser builds do not have an Android audio session or system equalizer.
class EqualizerService {
  static bool openEqualizer(int sessionId) => false;

  static void initAudioEffect(int sessionId) {}

  static void endAudioEffect(int sessionId) {}
}
