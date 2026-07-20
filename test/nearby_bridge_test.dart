import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/listen_together/nearby_bridge.dart';
import 'package:harmonymusic/services/listen_together/sync_transport.dart';

void main() {
  test('preserves Nearby missing-permission status for diagnostics', () {
    final failure = NearbyBridge.failureForCode('NEARBY_8033');

    expect(failure.code, TransportFailureCode.permissionDenied);
    expect(failure.platformCode, 'NEARBY_8033');
  });

  test('preserves unknown Nearby status as a typed startup failure', () {
    final failure = NearbyBridge.failureForCode('NEARBY_8012');

    expect(failure.code, TransportFailureCode.startupFailure);
    expect(failure.platformCode, 'NEARBY_8012');
  });
}
