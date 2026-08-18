import 'package:permission_handler/permission_handler.dart';

import 'sync_transport.dart';

/// Nearby Connections relies on Android platform capabilities unavailable in a
/// browser.
class NearbyPermissions {
  static Future<bool> areGranted() async => false;

  static Future<void> ensureGranted() async {
    throw const TransportFailure(TransportFailureCode.permissionDenied);
  }

  static List<Permission> requiredForSdk(int sdk) => <Permission>[
    if (sdk <= 28) Permission.location,
    if (sdk >= 29 && sdk <= 32) Permission.location,
    if (sdk >= 31) ...[
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ],
    if (sdk >= 33) Permission.nearbyWifiDevices,
  ];
}
