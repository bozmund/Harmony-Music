import 'dart:ui';

import 'package:harmonymusic/native_bindings/andrid_utils.dart';
import 'package:jni_flutter/jni_flutter.dart';

class EqualizerService {
  static bool openEqualizer(int sessionId) {
    final engineId = PlatformDispatcher.instance.engineId;
    if (engineId == null) return false;

    final activity = androidActivity(engineId);
    if (activity == null) return false;
    final context = androidApplicationContext;
    final success = Equalizer().openEqualizer(sessionId, context, activity);
    activity.release();
    context.release();
    return success;
  }

  static void initAudioEffect(int sessionId) {
    final context = androidApplicationContext;
    Equalizer().initAudioEffect(sessionId, context);
    context.release();
  }

  static void endAudioEffect(int sessionId) {
    final context = androidApplicationContext;
    Equalizer().endAudioEffect(sessionId, context);
    context.release();
  }
}
