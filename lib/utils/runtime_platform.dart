import 'dart:io';

import 'package:flutter/foundation.dart';

class RuntimePlatform {
  RuntimePlatform._();

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static bool get isLinux => !kIsWeb && Platform.isLinux;
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;
  static bool get isWindows => !kIsWeb && Platform.isWindows;

  static bool get isDesktop => isLinux || isMacOS || isWindows;
  static bool get isMobile => isAndroid || isIOS;
}
