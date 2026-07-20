import 'dart:convert';
import 'dart:developer' as developer;

import 'crash_diagnostics_service.dart';

enum PlaybackTransitionCategory { tap, skip, queueTransition, resume }

enum PlaybackSourceCategory {
  pending,
  local,
  preloaded,
  resolver,
  lockCaching,
  network,
}

enum PlaybackStartMilestone {
  action,
  sourceSelection,
  responseHeaders,
  firstEncodedByte,
  playerReady,
  positivePlaybackPosition,
}

typedef PlaybackTimingSink = void Function(PlaybackTimingSample sample);

class PlaybackTimingSample {
  const PlaybackTimingSample({
    required this.transition,
    required this.source,
    required this.milestone,
    required this.elapsedMicroseconds,
  });

  final PlaybackTransitionCategory transition;
  final PlaybackSourceCategory source;
  final PlaybackStartMilestone milestone;
  final int elapsedMicroseconds;

  Map<String, Object> toJson() => {
    'event': 'playback_start',
    'transition': _transitionLabel(transition),
    'source': _sourceLabel(source),
    'milestone': _milestoneLabel(milestone),
    'elapsed_us': elapsedMicroseconds,
  };
}

class PlaybackStartTrace {
  PlaybackStartTrace({
    required this.transition,
    PlaybackTimingSink? sink,
    int Function()? elapsedMicroseconds,
  }) : _sink = sink ?? _recordTimingSample {
    final stopwatch = Stopwatch()..start();
    _elapsedMicroseconds =
        elapsedMicroseconds ?? () => stopwatch.elapsedMicroseconds;
    _record(PlaybackStartMilestone.action);
  }

  final PlaybackTransitionCategory transition;
  final PlaybackTimingSink _sink;
  late final int Function() _elapsedMicroseconds;
  final Set<PlaybackStartMilestone> _recorded = {};
  PlaybackSourceCategory _source = PlaybackSourceCategory.pending;
  bool _playerIsReady = false;
  bool _completed = false;

  PlaybackSourceCategory get source => _source;

  void sourceSelected(PlaybackSourceCategory source) {
    if (_completed) return;
    _source = source;
    _record(PlaybackStartMilestone.sourceSelection);
  }

  void responseHeaders({PlaybackSourceCategory? source}) {
    _record(PlaybackStartMilestone.responseHeaders, sourceOverride: source);
  }

  void firstEncodedByte({PlaybackSourceCategory? source}) {
    _record(PlaybackStartMilestone.firstEncodedByte, sourceOverride: source);
  }

  void playerReady() {
    if (_completed ||
        !_recorded.contains(PlaybackStartMilestone.sourceSelection)) {
      return;
    }
    _playerIsReady = true;
    _record(PlaybackStartMilestone.playerReady);
  }

  void positivePlaybackPosition() {
    if (_completed || !_playerIsReady) return;
    _record(PlaybackStartMilestone.positivePlaybackPosition);
    _completed = true;
  }

  void _record(
    PlaybackStartMilestone milestone, {
    PlaybackSourceCategory? sourceOverride,
  }) {
    if (_completed || !_recorded.add(milestone)) return;
    _sink(
      PlaybackTimingSample(
        transition: transition,
        source: sourceOverride ?? _source,
        milestone: milestone,
        elapsedMicroseconds: _elapsedMicroseconds(),
      ),
    );
  }
}

void _recordTimingSample(PlaybackTimingSample sample) {
  final encoded = jsonEncode(sample.toJson());
  developer.log(encoded, name: 'harmony.playback_latency');
  CrashDiagnosticsService.instance.record('playback-latency', encoded);
}

String _transitionLabel(PlaybackTransitionCategory category) =>
    switch (category) {
      PlaybackTransitionCategory.tap => 'tap',
      PlaybackTransitionCategory.skip => 'skip',
      PlaybackTransitionCategory.queueTransition => 'queue_transition',
      PlaybackTransitionCategory.resume => 'resume',
    };

String _sourceLabel(PlaybackSourceCategory category) => switch (category) {
  PlaybackSourceCategory.pending => 'pending',
  PlaybackSourceCategory.local => 'local',
  PlaybackSourceCategory.preloaded => 'preloaded',
  PlaybackSourceCategory.resolver => 'resolver',
  PlaybackSourceCategory.lockCaching => 'lock_caching',
  PlaybackSourceCategory.network => 'network',
};

String _milestoneLabel(PlaybackStartMilestone milestone) => switch (milestone) {
  PlaybackStartMilestone.action => 'action',
  PlaybackStartMilestone.sourceSelection => 'source_selection',
  PlaybackStartMilestone.responseHeaders => 'response_headers',
  PlaybackStartMilestone.firstEncodedByte => 'first_encoded_byte',
  PlaybackStartMilestone.playerReady => 'player_ready',
  PlaybackStartMilestone.positivePlaybackPosition =>
    'positive_playback_position',
};
