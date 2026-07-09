import 'session_message.dart';

/// Narrow hook the [PlayerController] consults so it can hand control actions
/// to an active "Listen Together" session without depending on the whole
/// controller (which would create a construction cycle).
///
/// When the local device is a guest, playback intents (play/pause/next/seek/…)
/// must be forwarded to the host instead of being executed locally. The host
/// executes them and re-broadcasts state, keeping a single writer.
abstract class ListenTogetherGate {
  /// True when this device is currently a guest in a session and should defer
  /// control to the host.
  bool get isGuest;

  /// Forward a control request to the host.
  void sendCommand(SessionCommand command);
}
