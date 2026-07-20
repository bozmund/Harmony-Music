import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/listen_together/nearby_permissions.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  test('Android 12 requests location and Bluetooth permissions', () {
    expect(NearbyPermissions.requiredForSdk(31), [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ]);
  });

  test('Android 12L requests location and Bluetooth permissions', () {
    expect(NearbyPermissions.requiredForSdk(32), [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ]);
  });

  test('Android 13 replaces location with nearby Wi-Fi access', () {
    expect(NearbyPermissions.requiredForSdk(33), [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ]);
  });

  test('modern Android does not require location or notification access', () {
    final permissions = NearbyPermissions.requiredForSdk(36);
    expect(permissions, contains(Permission.nearbyWifiDevices));
    expect(permissions, isNot(contains(Permission.location)));
    expect(permissions, isNot(contains(Permission.notification)));
  });
}
