import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Nearby service id is stable across Android build variants', () {
    final source = File(
      'android/app/src/main/kotlin/com/anandnet/harmonymusic/'
      'NearbyConnectionsBridge.kt',
    ).readAsStringSync();

    expect(source, contains('com.anandnet.harmonymusic.listen_together'));
    expect(source, isNot(contains('serviceId = context.packageName')));
  });

  test('Nearby advertising, discovery, and connection are BLE low power', () {
    final source = File(
      'android/app/src/main/kotlin/com/anandnet/harmonymusic/'
      'NearbyConnectionsBridge.kt',
    ).readAsStringSync();

    expect('.setLowPower(true)'.allMatches(source), hasLength(3));
    expect(
      '.setConnectionType(ConnectionType.NON_DISRUPTIVE)'.allMatches(source),
      hasLength(2),
    );
    expect(source, contains('lifecycle, connectionOptions()'));
    expect(source, isNot(contains('setWifiEnabled')));
  });

  test('manifest declares the normal Wi-Fi permissions used by Nearby', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.ACCESS_WIFI_STATE'));
    expect(manifest, contains('android.permission.CHANGE_WIFI_STATE'));
  });

  test('repeated sessions fully dispose their previous transport', () {
    final source = File(
      'lib/services/listen_together/listen_together_controller.dart',
    ).readAsStringSync();

    expect(source, contains('await transport.dispose();'));
  });
}
