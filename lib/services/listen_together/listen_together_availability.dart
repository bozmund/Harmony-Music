import '../../utils/runtime_platform.dart';
import 'nearby_bridge.dart';
import 'nearby_permissions.dart';
import 'sync_transport.dart';

class ListenTogetherAvailabilityService {
  ListenTogetherAvailabilityService({NearbyBridge? bridge})
    : _bridge = bridge ?? NearbyBridge();

  final NearbyBridge _bridge;

  Stream<TransportAvailability> get changes => RuntimePlatform.isAndroid
      ? _bridge.availabilityChanges.asyncMap(_withPermissions)
      : const Stream<TransportAvailability>.empty();

  Future<TransportAvailability> read() async {
    if (RuntimePlatform.isAndroid) {
      return _withPermissions(await _bridge.getAvailability());
    }
    if (RuntimePlatform.isDesktop) {
      return const TransportAvailability(
        bluetoothEnabled: false,
        wifiEnabled: true,
        playServicesAvailable: false,
      );
    }
    return const TransportAvailability(
      bluetoothEnabled: false,
      wifiEnabled: false,
      playServicesAvailable: false,
    );
  }

  Future<TransportAvailability> require(TransportKind kind) async {
    final value = await read();
    if ((kind == TransportKind.bluetooth || kind == TransportKind.both) &&
        !value.bluetoothEnabled) {
      throw const TransportFailure(TransportFailureCode.bluetoothDisabled);
    }
    if ((kind == TransportKind.wifi || kind == TransportKind.both) &&
        !value.wifiEnabled) {
      throw const TransportFailure(TransportFailureCode.wifiDisabled);
    }
    if ((kind == TransportKind.bluetooth || kind == TransportKind.both) &&
        !value.playServicesAvailable) {
      throw const TransportFailure(
        TransportFailureCode.playServicesUnavailable,
      );
    }
    if ((kind == TransportKind.bluetooth || kind == TransportKind.both) &&
        !value.bluetoothPermissionGranted) {
      throw const TransportFailure(TransportFailureCode.permissionDenied);
    }
    return value;
  }

  Future<TransportAvailability> _withPermissions(
    TransportAvailability value,
  ) async => TransportAvailability(
    bluetoothEnabled: value.bluetoothEnabled,
    wifiEnabled: value.wifiEnabled,
    playServicesAvailable: value.playServicesAvailable,
    bluetoothPermissionGranted: await NearbyPermissions.areGranted(),
  );
}
