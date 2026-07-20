import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/playback_start_trace.dart';

void main() {
  test('records monotonic categorical playback milestones', () {
    final samples = <PlaybackTimingSample>[];
    var elapsedMicroseconds = 0;
    final trace = PlaybackStartTrace(
      transition: PlaybackTransitionCategory.queueTransition,
      sink: samples.add,
      elapsedMicroseconds: () => elapsedMicroseconds,
    );

    elapsedMicroseconds = 10;
    trace.sourceSelected(PlaybackSourceCategory.preloaded);
    elapsedMicroseconds = 20;
    trace.responseHeaders();
    elapsedMicroseconds = 30;
    trace.firstEncodedByte();
    elapsedMicroseconds = 40;
    trace.positivePlaybackPosition();
    expect(
      samples.map((sample) => sample.milestone),
      isNot(contains(PlaybackStartMilestone.positivePlaybackPosition)),
    );
    elapsedMicroseconds = 50;
    trace.playerReady();
    elapsedMicroseconds = 60;
    trace.positivePlaybackPosition();

    expect(
      samples.map((sample) => sample.milestone),
      PlaybackStartMilestone.values,
    );
    expect(
      samples.map((sample) => sample.elapsedMicroseconds),
      orderedEquals([0, 10, 20, 30, 50, 60]),
    );
    expect(samples.last.toJson(), {
      'event': 'playback_start',
      'transition': 'queue_transition',
      'source': 'preloaded',
      'milestone': 'positive_playback_position',
      'elapsed_us': 60,
    });
  });

  test('resolver candidate timings contain no request identifiers', () {
    final samples = <PlaybackTimingSample>[];
    final trace = PlaybackStartTrace(
      transition: PlaybackTransitionCategory.tap,
      sink: samples.add,
      elapsedMicroseconds: () => 1,
    );

    trace.responseHeaders(source: PlaybackSourceCategory.resolver);
    trace.firstEncodedByte(source: PlaybackSourceCategory.resolver);

    for (final sample in samples) {
      expect(
        sample.toJson().keys,
        unorderedEquals([
          'event',
          'transition',
          'source',
          'milestone',
          'elapsed_us',
        ]),
      );
    }
  });
}
