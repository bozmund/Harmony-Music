import 'dart:async';

import '../../data/repositories/cloud_sync_repository.dart';
import 'cloud_audio_backup_service.dart';
import 'harmony_cloud_client.dart';

class CloudSyncCoordinator {
  CloudSyncCoordinator(this._repository, this._client, this._audioBackup);

  final CloudSyncRepository _repository;
  final HarmonyCloudClient _client;
  final CloudAudioBackupService _audioBackup;
  Future<void>? _activeSync;
  Timer? _debounce;

  bool get enabled => _repository.enabled;
  bool get needsOptIn => !_repository.optInAnswered;

  Future<void> setEnabled(bool value) async {
    await _repository.setEnabled(value);
    if (value) {
      await synchronize();
    } else {
      await _client.pause(_repository.deviceId, true);
    }
  }

  void schedule() {
    if (!enabled) return;
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(seconds: 2),
      () => unawaited(synchronize()),
    );
  }

  Future<void> synchronize() {
    if (!enabled) return Future.value();
    final current = _activeSync;
    if (current != null) return current;
    final operation = _synchronizeCore();
    _activeSync = operation;
    return operation.whenComplete(() {
      if (identical(_activeSync, operation)) _activeSync = null;
    });
  }

  Future<CloudAudioBackupResult> backupAudioNow({
    bool overrideBatteryPolicy = false,
  }) => _audioBackup.run(overrideBatteryPolicy: overrideBatteryPolicy);

  Future<void> _synchronizeCore() async {
    final deviceId = _repository.deviceId;
    await _client.registerDevice(deviceId, 'Harmony device');
    final pending = await _repository.scan();
    final response = await _client.sync(
      deviceId: deviceId,
      checkpoint: _repository.checkpoint,
      events: pending.take(500).toList(),
    );
    final changes = response['changes'];
    if (changes is List) await _repository.applyRemote(changes);
    final accepted = response['acceptedEventIds'];
    await _repository.acknowledge(
      accepted is List ? accepted.map((id) => id.toString()) : const [],
      response['checkpoint'] as int? ?? _repository.checkpoint,
    );
    unawaited(_audioBackup.run());
  }
}
