import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'sync_transport.dart';

/// Android-only bridge for Google Play services Nearby Connections.
class NearbyBridge {
  static const _methods = MethodChannel('harmonymusic/nearby_connections');
  static const _events = EventChannel('harmonymusic/nearby_connections/events');

  static final Stream<Map<String, dynamic>> _eventStream = _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .cast<Map>()
      .map((event) => Map<String, dynamic>.from(event))
      .asBroadcastStream();

  Stream<Map<String, dynamic>> get events => _eventStream;

  Stream<TransportAvailability> get availabilityChanges => _eventStream
      .where((event) => event['type'] == 'radioState')
      .map(_availabilityFromMap);

  Future<void> advertise({required String name, required String sessionId}) =>
      _invoke('advertise', {'name': name, 'sessionId': sessionId});

  Future<void> discover() => _invoke('discover');

  Future<void> connect({required String endpointId, required String name}) =>
      _invoke('connect', {'endpointId': endpointId, 'name': name});

  Future<void> confirm(String endpointId, bool accept) =>
      _invoke('confirm', {'endpointId': endpointId, 'accept': accept});

  Future<void> send(String endpointId, Uint8List bytes) => _invoke('send', {
    'endpointId': endpointId,
    'payload': base64Encode(bytes),
  });

  Future<void> stop() => _invoke('stop');

  Future<TransportAvailability> getAvailability() async {
    final raw = await _methods.invokeMapMethod<String, dynamic>(
      'getRadioState',
    );
    return _availabilityFromMap(raw ?? const {});
  }

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    try {
      await _methods.invokeMethod<void>(method, arguments);
    } on PlatformException catch (error) {
      throw failureForCode(error.code);
    }
  }

  static TransportFailure failureForCode(String code) {
    if (code == 'BLUETOOTH_DISABLED') {
      return TransportFailure(
        TransportFailureCode.bluetoothDisabled,
        platformCode: code,
      );
    }
    if (code == 'PLAY_SERVICES_UNAVAILABLE') {
      return TransportFailure(
        TransportFailureCode.playServicesUnavailable,
        platformCode: code,
      );
    }
    if (code == 'NEARBY_8007') {
      return TransportFailure(
        TransportFailureCode.radioFailure,
        platformCode: code,
      );
    }
    if (RegExp(r'^NEARBY_80(29|3[0-9])$').hasMatch(code)) {
      return TransportFailure(
        TransportFailureCode.permissionDenied,
        platformCode: code,
      );
    }
    return TransportFailure(
      TransportFailureCode.startupFailure,
      platformCode: code,
    );
  }

  static TransportAvailability _availabilityFromMap(Map<String, dynamic> raw) =>
      TransportAvailability(
        bluetoothEnabled: raw['bluetoothEnabled'] == true,
        wifiEnabled: raw['wifiEnabled'] == true,
        playServicesAvailable: raw['playServicesAvailable'] == true,
      );
}
