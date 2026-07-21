import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import '../../domain/repositories/download_repository.dart';
import '../../data/repositories/cloud_sync_repository.dart';
import 'harmony_cloud_client.dart';

enum CloudAudioBackupResult {
  completed,
  alreadyRunning,
  disabled,
  wifiRequired,
  batteryTooLow,
  authenticationRequired,
  permissionDenied,
  serviceUnavailable,
  networkFailure,
}

class CloudAudioBackupService {
  CloudAudioBackupService(
    this._downloads,
    this._syncRepository,
    this._cloud, {
    Connectivity? connectivity,
    Battery? battery,
  }) : _connectivity = connectivity ?? Connectivity(),
       _battery = battery ?? Battery();

  final DownloadRepository _downloads;
  final CloudSyncRepository _syncRepository;
  final HarmonyCloudClient _cloud;
  final Connectivity _connectivity;
  final Battery _battery;
  bool _running = false;

  Future<CloudAudioBackupResult> run({
    bool overrideBatteryPolicy = false,
  }) async {
    if (_running) return CloudAudioBackupResult.alreadyRunning;
    if (!_syncRepository.enabled) return CloudAudioBackupResult.disabled;
    final initialBlock = await _policyBlock(
      overrideBatteryPolicy: overrideBatteryPolicy,
    );
    if (initialBlock != null) return initialBlock;
    _running = true;
    try {
      final entries = await _downloads.getAllDownloadJsonEntries();
      final candidates = <String, String>{};
      for (final entry in entries.entries) {
        final id = entry.key.toString();
        final value = entry.value;
        if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) || value is! Map) {
          continue;
        }
        final path = value['url']?.toString();
        if (path == null || path.isEmpty || !await File(path).exists())
          continue;
        candidates[id] = path;
      }

      try {
        while (candidates.isNotEmpty &&
            await _policyBlock(overrideBatteryPolicy: overrideBatteryPolicy) ==
                null) {
          final plan = await _cloud.nextAudio(
            deviceId: _syncRepository.deviceId,
            videoIds: candidates.keys.take(500).toList(),
          );
          if (plan['status'] != 'upload') break;
          final videoId = plan['videoId']?.toString();
          final uploadUrl = plan['uploadUrl']?.toString();
          final uploadToken = plan['uploadToken']?.toString();
          final path = videoId == null ? null : candidates.remove(videoId);
          if (path == null || uploadUrl == null || uploadToken == null) break;
          await _cloud.uploadAudio(
            uploadUrl: uploadUrl,
            uploadToken: uploadToken,
            filePath: path,
          );
        }
      } on DioException catch (error) {
        return _resultFor(error);
      }
      return CloudAudioBackupResult.completed;
    } finally {
      _running = false;
    }
  }

  static CloudAudioBackupResult _resultFor(DioException error) =>
      switch (error.response?.statusCode) {
        401 => CloudAudioBackupResult.authenticationRequired,
        403 => CloudAudioBackupResult.permissionDenied,
        500 || 502 || 503 || 504 => CloudAudioBackupResult.serviceUnavailable,
        _
            when error.type == DioExceptionType.connectionError ||
                error.type == DioExceptionType.connectionTimeout ||
                error.type == DioExceptionType.receiveTimeout ||
                error.type == DioExceptionType.sendTimeout =>
          CloudAudioBackupResult.networkFailure,
        _ => CloudAudioBackupResult.serviceUnavailable,
      };

  Future<CloudAudioBackupResult?> _policyBlock({
    required bool overrideBatteryPolicy,
  }) async {
    try {
      final connections = await _connectivity.checkConnectivity();
      if (!connections.contains(ConnectivityResult.wifi)) {
        return CloudAudioBackupResult.wifiRequired;
      }
      if (overrideBatteryPolicy || await _battery.batteryLevel > 50) {
        return null;
      }
      final state = await _battery.batteryState;
      if (state == BatteryState.charging || state == BatteryState.full) {
        return null;
      }
      return CloudAudioBackupResult.batteryTooLow;
    } catch (_) {
      return CloudAudioBackupResult.wifiRequired;
    }
  }
}
