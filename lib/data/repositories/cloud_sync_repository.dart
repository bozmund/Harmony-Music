import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:hive/hive.dart';

import '../../domain/repositories/playlist_repository.dart';
import '../../services/cloud/cloud_sync_event.dart';
import '../../services/constant.dart';

class CloudSyncRepository {
  CloudSyncRepository(this._playlists);

  final PlaylistRepository _playlists;

  Box get _outbox => Hive.box(BoxNames.cloudSyncOutbox);
  Box get _state => Hive.box(BoxNames.cloudSyncState);
  Box get _prefs => Hive.box(BoxNames.appPrefs);

  static const _staticBoxes = <String>[
    BoxNames.songDownloads,
    BoxNames.libFav,
    BoxNames.libFavNotDownloaded,
    BoxNames.libRP,
    BoxNames.libImportDuplicates,
    BoxNames.libImportReview,
    BoxNames.libraryPlaylists,
    BoxNames.libraryAlbums,
    BoxNames.libraryArtists,
    BoxNames.librarySearches,
    BoxNames.blacklistedPlaylist,
    BoxNames.searchQuery,
    BoxNames.lyrics,
    BoxNames.prevSessionData,
    BoxNames.appPrefs,
  ];

  static const _excludedPreferenceKeys = <String>{
    PrefKeys.downloadLocationPath,
    PrefKeys.exportLocationPath,
    PrefKeys.visitorId,
    PrefKeys.piped,
    PrefKeys.resolverDebugOverride,
    PrefKeys.resolverProductionOverride,
    PrefKeys.cloudDeviceId,
    PrefKeys.cloudCheckpoint,
    PrefKeys.cloudDeviceSequence,
  };

  bool get enabled => _prefs.get(PrefKeys.cloudSyncEnabled) == true;
  bool get optInAnswered => _prefs.get(PrefKeys.cloudOptInAnswered) == true;
  String get deviceId {
    final current = _prefs.get(PrefKeys.cloudDeviceId)?.toString();
    if (current != null && current.isNotEmpty) return current;
    final generated = _uuid();
    unawaited(_prefs.put(PrefKeys.cloudDeviceId, generated));
    return generated;
  }

  int get checkpoint => _prefs.get(PrefKeys.cloudCheckpoint) as int? ?? 0;

  Future<void> setEnabled(bool value) async {
    await _prefs.put(PrefKeys.cloudOptInAnswered, true);
    await _prefs.put(PrefKeys.cloudSyncEnabled, value);
  }

  Future<List<CloudSyncEvent>> scan() async {
    final currentEntities = <String>{};
    final boxes = <String>{
      ..._staticBoxes,
      for (final playlist in await _playlists.getPlaylists())
        playlist.playlistId,
    };

    for (final boxName in boxes) {
      final box = Hive.isBoxOpen(boxName)
          ? Hive.box(boxName)
          : await Hive.openBox(boxName);
      for (final key in box.keys) {
        if (boxName == BoxNames.appPrefs &&
            _excludedPreferenceKeys.contains(key.toString())) {
          continue;
        }
        final encodedKey = base64UrlEncode(utf8.encode(jsonEncode(key)));
        final entityId = '$boxName:$encodedKey';
        currentEntities.add(entityId);
        final sanitized = _sanitize(box.get(key));
        final fingerprint = stableFingerprint(canonicalJson(sanitized));
        if (_state.get('fingerprint:$entityId') == fingerprint) continue;
        await _enqueue(entityId, 'upsert', sanitized);
        await _state.put('fingerprint:$entityId', fingerprint);
      }
    }

    final known = _state.keys
        .map((key) => key.toString())
        .where((key) => key.startsWith('fingerprint:'))
        .map((key) => key.substring('fingerprint:'.length))
        .toList();
    for (final entityId in known) {
      if (currentEntities.contains(entityId)) continue;
      await _enqueue(entityId, 'delete', const <String, Object?>{});
      await _state.delete('fingerprint:$entityId');
    }
    return pending();
  }

  List<CloudSyncEvent> pending() =>
      _outbox.values.map(CloudSyncEvent.fromJson).toList()..sort(
        (left, right) => left.deviceSequence.compareTo(right.deviceSequence),
      );

  Future<void> acknowledge(
    Iterable<String> eventIds,
    int nextCheckpoint,
  ) async {
    final accepted = eventIds.toSet();
    for (final key in _outbox.keys.toList()) {
      final value = _outbox.get(key);
      if (value is Map && accepted.contains(value['eventId'])) {
        await _outbox.delete(key);
      }
    }
    await _prefs.put(PrefKeys.cloudCheckpoint, nextCheckpoint);
  }

  Future<void> applyRemote(List<dynamic> changes) async {
    for (final raw in changes) {
      final change = Map<String, dynamic>.from(raw as Map);
      final entityId = change['entityId'] as String;
      final separator = entityId.indexOf(':');
      if (separator <= 0) continue;
      final boxName = entityId.substring(0, separator);
      dynamic key;
      try {
        key = jsonDecode(
          utf8.decode(base64Url.decode(entityId.substring(separator + 1))),
        );
      } on FormatException {
        continue;
      }
      if (!_staticBoxes.contains(boxName) &&
          !(await _playlists.getPlaylists()).any(
            (playlist) => playlist.playlistId == boxName,
          )) {
        continue;
      }
      if (boxName == BoxNames.appPrefs &&
          _excludedPreferenceKeys.contains(key)) {
        continue;
      }
      final box = Hive.isBoxOpen(boxName)
          ? Hive.box(boxName)
          : await Hive.openBox(boxName);
      if (change['operation'] == 'delete') {
        await box.delete(key);
        await _state.delete('fingerprint:$entityId');
      } else {
        final payload = change['payload'];
        await box.put(key, payload);
        await _state.put(
          'fingerprint:$entityId',
          stableFingerprint(canonicalJson(payload)),
        );
      }
    }
  }

  Future<void> _enqueue(
    String entityId,
    String operation,
    Object? payload,
  ) async {
    final sequence =
        (_prefs.get(PrefKeys.cloudDeviceSequence) as int? ?? 0) + 1;
    await _prefs.put(PrefKeys.cloudDeviceSequence, sequence);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final event = CloudSyncEvent(
      eventId: _uuid(),
      deviceSequence: sequence,
      hlcPhysicalMs: now,
      hlcLogical: 0,
      entityType: 'hive-entry',
      entityId: entityId,
      operation: operation,
      payload: payload,
    );
    await _outbox.put(sequence, event.toJson());
  }

  Object? _sanitize(Object? value) {
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final normalizedKey = key.toLowerCase().replaceAll('_', '');
        if (_excludedPayloadKeys.contains(normalizedKey)) {
          continue;
        }
        result[key] = _sanitize(entry.value);
      }
      return result;
    }
    if (value is Iterable) return value.map(_sanitize).toList();
    return value;
  }

  static const _excludedPayloadKeys = <String>{
    'url',
    'streaminfo',
    'visitorid',
    'filepath',
    'localpath',
    'downloadpath',
    'accesstoken',
    'refreshtoken',
    'clientsecret',
    'password',
    'authorization',
  };

  String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
