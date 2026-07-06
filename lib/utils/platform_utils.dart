import 'package:flutter/foundation.dart';

bool get isDesktopPlatform {
  return switch (defaultTargetPlatform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    _ => false,
  };
}

bool get isAndroidPlatform => defaultTargetPlatform == TargetPlatform.android;
