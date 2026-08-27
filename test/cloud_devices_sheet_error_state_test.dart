import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device picker shows errors instead of loading forever', () {
    final sheet = File(
      'lib/ui/widgets/cloud_devices_sheet.dart',
    ).readAsStringSync();
    final client = File(
      'lib/services/cloud/harmony_cloud_client.dart',
    ).readAsStringSync();

    expect(sheet, contains('snapshot.hasError'));
    expect(sheet, contains('deviceControlUnavailable'));
    expect(sheet, contains('onPressed: _retry'));
    expect(sheet, contains('try {'));
    expect(client, contains('connectTimeout: const Duration(seconds: 15)'));
  });

  test('device picker removes only non-current devices after confirmation', () {
    final sheet = File(
      'lib/ui/widgets/cloud_devices_sheet.dart',
    ).readAsStringSync();

    expect(sheet, contains('AwaitableIconButton'));
    expect(sheet, contains('!device.isCurrentDevice'));
    expect(sheet, contains('removeDeviceConfirmation(device.name)'));
    expect(sheet, contains('removePlaybackDevice(device.deviceId)'));
    expect(sheet, contains('setState(_loadDevices)'));
  });

  test('a device that owns the session but stopped is a transfer target', () {
    final sheet = File(
      'lib/ui/widgets/cloud_devices_sheet.dart',
    ).readAsStringSync();

    // isAudioTarget outlives the playback that claimed it: stopping or pausing
    // never releases the session. Reading it as "is playing" left a finished
    // device advertising itself as a sync target, with no way to transfer a
    // queue to it short of ending the session from that device.
    expect(sheet, contains('_isPlayingTarget(device, session)'));
    expect(
      'device.isAudioTarget'.allMatches(sheet).length,
      1,
      reason:
          'isAudioTarget belongs only inside _isPlayingTarget; any other use is '
          'a decision made on session ownership rather than playback',
    );

    // Both halves of the predicate matter. Without session.playing a stopped
    // device still reads as joinable; without presence, a killed app leaves
    // playing true on the session with no socket behind it.
    final predicate = sheet.substring(
      sheet.indexOf('bool _isPlayingTarget('),
      sheet.indexOf('session.playing;') + 'session.playing;'.length,
    );
    expect(predicate, contains('device.isAudioTarget'));
    expect(predicate, contains("device.presence == 'online'"));
    expect(predicate, contains('session.targetDeviceId == device.deviceId'));
  });

  test('the picker reads the session, not just the device list', () {
    final sheet = File(
      'lib/ui/widgets/cloud_devices_sheet.dart',
    ).readAsStringSync();
    final auth = File(
      'lib/app/providers/auth_providers.dart',
    ).readAsStringSync();

    expect(auth, contains('playbackSession() => _cloud.playbackSession()'));
    expect(sheet, contains('auth.playbackSession()'));
    // A session that is missing or fails to load must degrade to "everything is
    // a transfer target", never break the sheet.
    expect(sheet, contains('catchError((_) => null)'));
  });

  test('handing off with nothing playing says so', () {
    final sheet = File(
      'lib/ui/widgets/cloud_devices_sheet.dart',
    ).readAsStringSync();

    // Reachable now that tapping an idle target routes to _handoff.
    expect(sheet, contains('nothingHereToTransfer'));
  });
}
