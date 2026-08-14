import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart' show Key;

import '../../data/repositories/cloud_sync_repository.dart';
import '../../ui/player/player_controller.dart';
import '../../ui/screens/Library/library_controller.dart';
import '../../ui/screens/Playlist/playlist_screen_controller.dart';
import '../../utils/helper.dart';
import '../constant.dart';
import 'cloud_playback_gateway.dart';
import 'harmony_cloud_client.dart';
import 'playback_socket_client.dart';

class CloudSyncCoordinator implements CloudPlaybackGateway {
  CloudSyncCoordinator(this._repository, this._client, {PlaybackSocketTransport? socket})
    : _socket = socket;

  final CloudSyncRepository _repository;
  final HarmonyCloudClient _client;
  // Nullable: sockets are a live-push nicety, not something every construction
  // site (tests included) needs to wire up. Without one, this coordinator is
  // exactly what it was before — poll-and-debounce only.
  final PlaybackSocketTransport? _socket;
  Future<void>? _activeSync;
  Timer? _debounce;
  Timer? _poll;
  StreamSubscription<void>? _localChanges;
  StreamSubscription<Map<String, dynamic>>? _remoteChanges;

  /// How often an idle device asks for what other devices have written, when
  /// nothing told it sooner.
  ///
  /// Sync used to run only at app start, so a device left open never learned
  /// about anything: a song liked on the phone stayed invisible on the desktop
  /// until it was restarted. A pull with nothing to send is a single small
  /// request, so this is cheap enough to run while the app is open — and it is
  /// the fallback for a missed or dropped `libraryChanged` push (see
  /// `_onRemoteFrame`), not just the whole mechanism.
  static const _pollInterval = Duration(minutes: 1);

  bool get enabled => _repository.enabled;
  String get deviceId => _repository.deviceId;
  bool get needsOptIn => !_repository.optInAnswered;

  /// Persists the opt-in and mirrors it to the server's per-device pause flag.
  ///
  /// Resuming is not optional: pausing is remembered server-side and nothing
  /// else clears it — `devices/register` does not — so a device that ever had
  /// sync switched off (including answering "Not now" to the opt-in prompt)
  /// stays paused, and every later `/sync` is rejected with `sync_paused`.
  Future<void> setEnabled(bool value) async {
    await _repository.setEnabled(value);
    if (!value) {
      unawaited(_client.pause(_repository.deviceId, true));
      return;
    }
    try {
      // The pause endpoint only knows registered devices, so a first-run
      // enable has to register before it can clear the flag.
      await registerCurrentDevice();
      await _client.pause(_repository.deviceId, false);
    } catch (error) {
      printERROR('Cloud sync resume failed: $error', tag: LogTags.cloudSync);
    }
  }

  /// Drops the library belonging to the previously signed-in account. Stops
  /// watching first so the wipe is not mistaken for local edits and re-uploaded
  /// into the new account.
  Future<void> forgetAccountLibrary() async {
    await stop();
    await _repository.forgetAccountLibrary();
  }

  Future<void> registerCurrentDevice() async {
    final deviceId = _repository.deviceId;
    await _client.registerDevice(
      deviceId: deviceId,
      name: _deviceName(),
      platform: _platformName(),
      appVersion: BuildInfo.version.isEmpty ? 'unknown' : BuildInfo.version,
    );
    unawaited(_client.updatePlaybackPresence(deviceId));
  }

  /// Begins pushing local edits and pulling remote ones. Safe to call again;
  /// re-running simply replaces the existing watchers.
  Future<void> start() async {
    await stop();
    if (!enabled) return;
    _localChanges = await _repository.watchLocalChanges(schedule);
    _poll = Timer.periodic(_pollInterval, (_) => unawaited(synchronize()));
    _remoteChanges = _socket?.frames.listen(_onRemoteFrame);
  }

  Future<void> stop() async {
    _debounce?.cancel();
    _debounce = null;
    _poll?.cancel();
    _poll = null;
    await _localChanges?.cancel();
    _localChanges = null;
    await _remoteChanges?.cancel();
    _remoteChanges = null;
  }

  /// Another device's edit just landed on the server — pull it now instead of
  /// waiting on the next poll tick, which could be up to a minute away.
  ///
  /// No debounce here: the frame itself already is one, since the server only
  /// broadcasts once per sync that actually changed something, and
  /// `synchronize()` coalesces overlapping calls on its own (`_activeSync`), so
  /// a burst of pushes costs at most one extra round trip, never a pile-up.
  void _onRemoteFrame(Map<String, dynamic> frame) {
    if (frame['type'] != 'libraryChanged') return;
    unawaited(synchronize());
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
    // Callers fire this and forget, so a rejected sync used to surface only as
    // an uncaught zone error while the outbox silently grew forever. The
    // server explains every refusal in a `code` field; log it.
    final operation = _synchronizeCore().catchError(_reportSyncFailure);
    _activeSync = operation;
    return operation.whenComplete(() {
      if (identical(_activeSync, operation)) _activeSync = null;
    });
  }

  void _reportSyncFailure(Object error) {
    if (error is DioException) {
      final response = error.response;
      printERROR(
        'Cloud sync rejected: status=${response?.statusCode} '
        'body=${response?.data} url=${error.requestOptions.uri}',
        tag: LogTags.cloudSync,
      );
      return;
    }
    printERROR('Cloud sync failed: $error', tag: LogTags.cloudSync);
  }

  Future<List<CloudPlaybackDevice>> playbackDevices() =>
      _client.playbackDevices(_repository.deviceId);

  Future<void> removePlaybackDevice(String deviceId) =>
      _client.removePlaybackDevice(deviceId);

  Future<bool> handoffPlayback({
    required String targetDeviceId,
    required Map<String, Object?> payload,
  }) => _client.submitPlaybackCommand(
    sourceDeviceId: _repository.deviceId,
    targetDeviceId: targetDeviceId,
    type: 'handoff',
    payload: payload,
  );

  Future<bool> sendPlaybackCommand({
    required String targetDeviceId,
    required String type,
    required Map<String, Object?> payload,
  }) => _client.submitPlaybackCommand(
    sourceDeviceId: _repository.deviceId,
    targetDeviceId: targetDeviceId,
    type: type,
    payload: payload,
  );

  Future<CloudPlaybackSession?> playbackSession() => _client.playbackSession();

  Future<String> startPlaybackSession({
    required String targetDeviceId,
    required Map<String, Object?> state,
  }) => _client.startPlaybackSession(
    sourceDeviceId: _repository.deviceId,
    targetDeviceId: targetDeviceId,
    state: state,
  );

  Future<void> sendSessionCommand({
    required String targetDeviceId,
    required String type,
    required Map<String, Object?> payload,
  }) => _client.sendSessionCommand(
    sourceDeviceId: _repository.deviceId,
    targetDeviceId: targetDeviceId,
    type: type,
    payload: payload,
  );

  Future<void> updatePlaybackSessionState(Map<String, Object?> state) => _client
      .updatePlaybackSessionState(deviceId: _repository.deviceId, state: state);

  Future<void> switchPlaybackTarget({
    required String targetDeviceId,
    required Map<String, Object?> state,
  }) => _client.switchPlaybackTarget(
    sourceDeviceId: _repository.deviceId,
    targetDeviceId: targetDeviceId,
    state: state,
  );

  Future<void> endPlaybackSession() => _client.endPlaybackSession();

  Future<void> registerFcmToken(String token) =>
      _client.registerFcmToken(deviceId: _repository.deviceId, token: token);

  Future<List<CloudPlaybackCommand>> pendingPlaybackCommands() =>
      _client.pendingPlaybackCommands(_repository.deviceId);

  Future<void> acknowledgePlaybackCommand({
    required String commandId,
    required bool applied,
  }) => _client.acknowledgePlaybackCommand(
    commandId: commandId,
    deviceId: _repository.deviceId,
    applied: applied,
  );

  /// Reloads the library screens fed by the boxes a sync just wrote.
  ///
  /// Applying a remote change writes straight into Hive, but the library
  /// controllers hold their lists in memory and only read on open — so an album
  /// added on another device arrived and stayed invisible until the screen was
  /// rebuilt. Each controller is refreshed only when its own box changed, so a
  /// sync that touched nothing on screen costs nothing.
  void _refreshLibraryViews(Set<String> boxes) {
    if (boxes.isEmpty) return;
    if (boxes.contains(BoxNames.libraryAlbums)) {
      unawaited(LibraryAlbumsControllerRegistry.current?.refreshLib());
    }
    if (boxes.contains(BoxNames.libraryArtists)) {
      unawaited(LibraryArtistsControllerRegistry.current?.refreshLib());
    }
    if (boxes.contains(BoxNames.libraryPlaylists) ||
        boxes.contains(BoxNames.blacklistedPlaylist)) {
      unawaited(LibraryPlaylistsControllerRegistry.current?.refreshLib());
    }
    // Favourites and recently-played are rendered by the playlist screen keyed
    // on their box name, as are the per-playlist song boxes. Only the one whose
    // box changed is re-read, and only if it is currently open.
    for (final boxName in boxes) {
      final screen = PlaylistScreenControllerRegistry.maybeOf(
        Key(boxName).hashCode.toString(),
      );
      unawaited(screen?.fetchSongsFromDatabase(boxName));
    }
    // The Favourites list above is the only thing that watched this box —
    // the heart icon on the mini-player, full player, and an open song-info
    // sheet all read `PlayerController.isCurrentSongFav`, which nothing here
    // touched. A liked song pulled in from another device stayed shown as
    // unliked until the current song changed for an unrelated reason.
    if (boxes.contains(BoxNames.libFav)) {
      unawaited(PlayerControllerRegistry.current?.refreshFavoriteStatus());
    }
  }

  Future<void> _synchronizeCore() async {
    final deviceId = _repository.deviceId;
    await registerCurrentDevice();
    final pending = await _repository.scan();
    final response = await _client.sync(
      deviceId: deviceId,
      checkpoint: _repository.checkpoint,
      events: pending.take(500).toList(),
    );
    final changes = response['changes'];
    if (changes is List) {
      _refreshLibraryViews(await _repository.applyRemote(changes));
    }
    final accepted = response['acceptedEventIds'];
    await _repository.acknowledge(
      accepted is List ? accepted.map((id) => id.toString()) : const [],
      response['checkpoint'] as int? ?? _repository.checkpoint,
    );
  }

  String _deviceName() {
    if (Platform.isWindows) return 'Harmony Windows';
    if (Platform.isAndroid) return 'Harmony Android';
    return 'Harmony device';
  }

  String _platformName() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}
