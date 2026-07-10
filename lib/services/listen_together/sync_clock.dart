import 'session_message.dart';

class ClockOffsetSample {
  const ClockOffsetSample({required this.offsetMs, required this.rttMs});

  final int offsetMs;
  final int rttMs;
}

/// Pure clock-synchronization math for Listen Together, kept free of any
/// plugin/IO dependencies so it can be unit-tested in isolation.
class SyncClock {
  const SyncClock._();

  /// Estimate `hostClock - localClock` (ms) from a hello/helloAck round-trip.
  ///
  /// * [helloClientTimeMs] — our local clock when we sent `hello`.
  /// * [hostTimeMs] — the host's clock when it produced `helloAck`.
  /// * [ackReceivedMs] — our local clock when the `helloAck` arrived.
  ///
  /// Assumes symmetric latency: the host's clock at our "now" is
  /// `hostTimeMs + rtt/2`, so the offset is that minus our "now".
  static int estimateOffsetMs({
    required int helloClientTimeMs,
    required int hostTimeMs,
    required int ackReceivedMs,
  }) {
    return estimateOffsetSample(
      helloClientTimeMs: helloClientTimeMs,
      hostTimeMs: hostTimeMs,
      ackReceivedMs: ackReceivedMs,
    ).offsetMs;
  }

  static ClockOffsetSample estimateOffsetSample({
    required int helloClientTimeMs,
    required int hostTimeMs,
    required int ackReceivedMs,
  }) {
    final rtt = ackReceivedMs - helloClientTimeMs;
    final safeRtt = rtt < 0 ? 0 : rtt;
    return ClockOffsetSample(
      offsetMs: hostTimeMs + (safeRtt ~/ 2) - ackReceivedMs,
      rttMs: safeRtt,
    );
  }

  /// Project the position a guest should currently be at for [snap], given the
  /// estimated [clockOffsetMs] and the guest's current [nowMs].
  ///
  /// While playing, the elapsed time since the host produced the snapshot is
  /// added to its position; while paused, the snapshot position is authoritative.
  static int expectedPositionMs(
    PlaybackSnapshot snap, {
    required int clockOffsetMs,
    required int nowMs,
  }) {
    if (!snap.playing) return snap.positionMs;
    final elapsed = (nowMs + clockOffsetMs) - snap.hostTimestampMs;
    return snap.positionMs + (elapsed < 0 ? 0 : elapsed);
  }
}
