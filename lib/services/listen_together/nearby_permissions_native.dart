import 'package:permission_handler/permission_handler.dart';

import '../../native_bindings/andrid_utils.dart';
import 'sync_transport.dart';

class NearbyPermissions {
  static Future<bool> areGranted() async {
    final permissions = requiredForSdk(SDKInt.Companion.sDKInt);
    final statuses = await Future.wait(permissions.map((item) => item.status));
    return statuses.every((status) => status.isGranted);
  }

  static Future<void> ensureGranted() async {
    final sdk = SDKInt.Companion.sDKInt;
    final statuses = await requiredForSdk(sdk).request();
    if (statuses.values.any((status) => !status.isGranted)) {
      throw const TransportFailure(TransportFailureCode.permissionDenied);
    }
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
