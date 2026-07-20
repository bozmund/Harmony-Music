import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../domain/repositories/download_repository.dart';
import '../../data/repositories/cloud_sync_repository.dart';
import 'harmony_cloud_client.dart';

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

  Future<void> run() async {
    if (_running || !_syncRepository.enabled || !await _policyAllowsUpload()) {
      return;
    }
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

      while (candidates.isNotEmpty && await _policyAllowsUpload()) {
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
    } finally {
      _running = false;
    }
  }

  Future<bool> _policyAllowsUpload() async {
    try {
      final connections = await _connectivity.checkConnectivity();
      if (!connections.contains(ConnectivityResult.wifi)) return false;
      return await _battery.batteryLevel > 50;
    } catch (_) {
      return false;
    }
  }
}
