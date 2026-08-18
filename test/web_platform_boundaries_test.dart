import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'JNI-dependent services select web-safe stubs outside the IO runtime',
    () {
      expect(
        File('lib/services/equalizer.dart').readAsStringSync(),
        contains("if (dart.library.io) 'equalizer_native.dart'"),
      );
      expect(
        File('lib/services/permission_service.dart').readAsStringSync(),
        contains("if (dart.library.io) 'permission_service_native.dart'"),
      );
      expect(
        File(
          'lib/services/listen_together/nearby_permissions.dart',
        ).readAsStringSync(),
        contains("if (dart.library.io) 'nearby_permissions_native.dart'"),
      );
      expect(
        File('lib/services/desktop_audio_platform.dart').readAsStringSync(),
        contains("if (dart.library.io) 'desktop_audio_platform_native.dart'"),
      );
      expect(
        File('lib/services/windows_audio_service.dart').readAsStringSync(),
        contains("if (dart.library.io) 'windows_audio_service_native.dart'"),
      );
    },
  );

  test('platform-neutral callers never import a native-only package', () {
    // The split only pays off if call sites stay clean: `audio_handler.dart`
    // once kept an unused `package:media_kit/src/...` import after its last
    // reference moved to the native half, which would drag a desktop-only
    // package into a web build for nothing.
    const nativeOnlyPackages = [
      'package:media_kit/',
      'package:smtc_windows/',
      'package:just_audio_media_kit/',
    ];
    for (final path in [
      'lib/services/audio_handler.dart',
      'lib/services/windows_audio_service.dart',
      'lib/services/equalizer.dart',
      'lib/services/permission_service.dart',
    ]) {
      final source = File(path).readAsStringSync();
      for (final package in nativeOnlyPackages) {
        expect(
          source.contains("import '$package") ||
              source.contains('import "$package'),
          isFalse,
          reason: '$path should reach $package through its native half only',
        );
      }
    }
  });
}
