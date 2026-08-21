import 'harmony_cloud_client.dart';

/// Cloud operations used by cross-device playback.
///
/// Kept separate from library synchronization so two deterministic device
/// endpoints can be connected in integration tests without a live server.
abstract interface class CloudPlaybackGateway {
  String get deviceId;

  /// Whether this device advertises what it is playing, so another device can
  /// subscribe to it as a remote. Exposed here rather than injecting the
  /// preferences repository, matching how [deviceId] is reached.
  bool get shareNowPlaying;

  Future<CloudPlaybackSession?> playbackSession();

  Future<String> startPlaybackSession({
    required String targetDeviceId,
    required Map<String, Object?> state,
  });

  /// Declares this device the audio target for what it is already playing.
  /// Null when the server refuses — another device owns the session, or the
  /// server predates the endpoint.
  Future<String?> claimPlaybackSession({required Map<String, Object?> state});

  Future<void> switchPlaybackTarget({
    required String targetDeviceId,
    required Map<String, Object?> state,
  });

  Future<void> sendSessionCommand({
    required String targetDeviceId,
    required String type,
    required Map<String, Object?> payload,
  });

  Future<void> updatePlaybackSessionState(Map<String, Object?> state);

  Future<void> endPlaybackSession();

  Future<List<CloudPlaybackCommand>> pendingPlaybackCommands();

  Future<void> acknowledgePlaybackCommand({
    required String commandId,
    required bool applied,
  });
}
