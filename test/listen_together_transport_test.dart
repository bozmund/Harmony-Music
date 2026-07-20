import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:harmonymusic/app/providers/controller_providers.dart';
import 'package:harmonymusic/data/repositories/listen_together_preferences.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:harmonymusic/services/listen_together/sync_transport.dart';
import 'package:harmonymusic/services/listen_together/lan_transport.dart';
import 'package:harmonymusic/services/listen_together/nearby_transport.dart';
import 'package:harmonymusic/services/listen_together/hybrid_transport.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const nearbyChannel = MethodChannel('harmonymusic/nearby_connections');
  late Directory hiveDir;
  late ListenTogetherPreferences preferences;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nearbyChannel, (_) async => null);
    hiveDir = await Directory.systemTemp.createTemp(
      'listen_together_transport_',
    );
    Hive.init(hiveDir.path);
    await Hive.openBox(BoxNames.appPrefs);
    preferences = ListenTogetherPreferences();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nearbyChannel, null);
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  test('combined transport is the first-install default', () {
    expect(preferences.transport, TransportKind.both);
  });

  test('selected transport is persisted', () async {
    await preferences.setTransport(TransportKind.bluetooth);
    expect(preferences.transport, TransportKind.bluetooth);

    await preferences.setTransport(TransportKind.wifi);
    expect(preferences.transport, TransportKind.wifi);
  });

  test('availability enforces exact selected radios', () {
    const bluetoothOnly = TransportAvailability(
      bluetoothEnabled: true,
      wifiEnabled: false,
      playServicesAvailable: true,
    );
    expect(bluetoothOnly.supports(TransportKind.bluetooth), isTrue);
    expect(bluetoothOnly.supports(TransportKind.wifi), isFalse);
    expect(bluetoothOnly.supports(TransportKind.both), isFalse);

    const both = TransportAvailability(
      bluetoothEnabled: true,
      wifiEnabled: true,
      playServicesAvailable: true,
    );
    expect(both.supports(TransportKind.values.last), isTrue);
  });

  test('transport factory maps every explicit mode', () async {
    final wifi = createListenTogetherTransport(TransportKind.wifi);
    final bluetooth = createListenTogetherTransport(TransportKind.bluetooth);
    final both = createListenTogetherTransport(TransportKind.both);

    expect(wifi, isA<LanTransport>());
    expect(bluetooth, isA<NearbyTransport>());
    expect(both, isA<HybridTransport>());

    await wifi.dispose();
    await bluetooth.dispose();
    await both.dispose();
  });
}
