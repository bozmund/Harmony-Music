import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A tapped song that has to be fetched from the network showed its spinner
/// for 87ms, then the button said "playing" through five seconds of silence.
///
/// During a playing source switch the handler reports ready + playing on
/// purpose, so Android keeps the lock-screen card instead of flashing a
/// connecting state on every track change. The controller read that as the new
/// song having started. The fix leaves the media session alone and gives the
/// controller the handler's own loading flag through a separate event.
void main() {
  late String handler;
  late String controller;

  setUpAll(() {
    handler = File('lib/services/audio_handler.dart').readAsStringSync();
    controller = File(
      'lib/ui/player/player_controller.dart',
    ).readAsStringSync();
  });

  group('the handler says when it is loading', () {
    test('every assignment to isSongLoading is broadcast', () {
      // A setter, not events placed by hand: the flag is assigned in about
      // fifteen places across the success and error paths, and a hand-placed
      // event would sooner or later miss one and strand the spinner.
      expect(handler, contains('bool get isSongLoading => _isSongLoading;'));
      final setter = _block(handler, 'set isSongLoading(bool value) {');
      expect(setter, contains('if (_isSongLoading == value) return;'));
      expect(
        setter,
        contains(
          "customEvent.add({'eventType': 'sourceLoading', 'loading': value});",
        ),
      );
    });

    test('the lock-screen design is untouched', () {
      // The fix must not change what Android sees during a switch: reporting
      // loading there would flash a connecting state on every song change.
      final events = _block(
        handler,
        'void _notifyAudioHandlerAboutPlaybackEvents() {',
      );
      final preserved = events.indexOf(
        'processingState: preservingMediaSession',
      );
      final loading = events.indexOf(': isSongLoading', preserved);
      expect(preserved, greaterThan(-1));
      expect(loading, greaterThan(preserved));
    });
  });

  group('the controller waits for it', () {
    test('the sourceLoading event is mirrored', () {
      final events = _block(controller, 'void _listenForCustomEvents() {');
      expect(events, contains("event['eventType'] == 'sourceLoading'"));
      expect(
        events,
        contains("_handlerLoadingSource = event['loading'] == true;"),
      );
    });

    test('a position tick cannot end the spinner while the handler loads', () {
      final position = _block(
        controller,
        'void _listenForChangesInPosition() {',
      );
      final guard = position.indexOf('if (_handlerLoadingSource ||');
      final clear = position.indexOf('_clearPendingSourceStart();');
      expect(guard, greaterThan(-1));
      expect(clear, greaterThan(guard));
    });

    test('a ready-paused report cannot end it either', () {
      final paused = _block(
        controller,
        'bool _isReadyPausedPendingSource(PlaybackState playbackState) {',
      );
      expect(paused, contains('!_handlerLoadingSource &&'));
    });

    test('the flag shows up in the log and the diagnostics dump', () {
      // So the next report of a missing spinner answers itself.
      expect(controller, contains(r"'handlerLoading=$_handlerLoadingSource '"));
      expect(
        controller,
        contains("'handlerLoadingSource': _handlerLoadingSource,"),
      );
    });
  });
}

/// The declaration starting at [signature], up to its matching closing brace.
String _block(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, greaterThan(-1), reason: 'missing $signature');
  final open = source.indexOf('{', start);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  return source.substring(start);
}
