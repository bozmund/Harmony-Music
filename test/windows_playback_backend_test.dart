import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registers MediaKit before creating the audio service on desktop', () {
    // The call itself moved behind DesktopAudioPlatform when desktop-only
    // symbols were split into a native/stub pair, so `main.dart` names the
    // facade and only the native half touches JustAudioMediaKit. The ordering
    // this test exists to protect is unchanged.
    final source = File('lib/main.dart').readAsStringSync();
    final registration = source.indexOf('DesktopAudioPlatform.register()');
    final audioService = source.indexOf('initAudioService(');

    expect(registration, greaterThanOrEqualTo(0));
    expect(audioService, greaterThan(registration));
    expect(
      File('lib/services/desktop_audio_platform_native.dart').readAsStringSync(),
      contains('JustAudioMediaKit.registerWith()'),
    );
  });

  test('normal playback stop pauses while lifecycle stop remains real', () {
    final commands = File(
      'lib/services/playback_command_service.dart',
    ).readAsStringSync();
    final handler = File('lib/services/audio_handler.dart').readAsStringSync();

    expect(commands, contains('Future<void> stop() => pause();'));
    final taskRemoved = handler.indexOf('Future<void> onTaskRemoved()');
    final handlerStop = handler.indexOf('Future<void> stop() async');
    expect(taskRemoved, greaterThanOrEqualTo(0));
    expect(handlerStop, greaterThan(taskRemoved));
    expect(handler.substring(handlerStop), contains('await _player.stop();'));
  });

  test(
    'Windows adapter initializes an output endpoint before loading media',
    () {
      final adapter = File(
        'third_party/just_audio_media_kit/lib/mediakit_player.dart',
      ).readAsStringSync();
      final initialize = adapter.indexOf(
        'Future<void> initializeAudioOutput()',
      );
      final selectDefault = adapter.indexOf(
        'await _player.setAudioDevice(AudioDevice.auto());',
        initialize,
      );
      final openSource = adapter.indexOf('await _player.open(');

      expect(initialize, greaterThanOrEqualTo(0));
      expect(selectDefault, greaterThan(initialize));
      expect(openSource, greaterThan(selectDefault));
      expect(adapter, contains("setProperty('cache-on-disk', 'no')"));
      expect(
        'await _player.setAudioDevice(AudioDevice.auto());'.allMatches(adapter),
        hasLength(1),
      );
      expect(adapter, contains('play: false'));
    },
  );

  test('Windows adapter loads the full source after platform recreation', () {
    final adapter = File(
      'third_party/just_audio_media_kit/lib/mediakit_player.dart',
    ).readAsStringSync();
    final load = adapter.indexOf('Future<LoadResponse> load(');
    final requestSource = adapter.indexOf(
      '_flattenSources(request.audioSourceMessage)',
      load,
    );
    final open = adapter.indexOf(
      'await _openSources(index: _currentIndex, play: false);',
      load,
    );

    expect(load, greaterThanOrEqualTo(0));
    expect(requestSource, greaterThan(load));
    expect(open, greaterThan(requestSource));
  });

  test('Windows adapter defers restore seek until audio is ready', () {
    final adapter = File(
      'third_party/just_audio_media_kit/lib/mediakit_player.dart',
    ).readAsStringSync();

    expect(adapter, contains('bool _audioReady = false;'));
    expect(adapter, contains('Duration? _pendingSeek;'));
    expect(adapter, contains('if (_audioReady)'));
    expect(adapter, contains('unawaited(_applySeek(pendingSeek));'));
  });

  test('Windows adapter applies a zero seek to the native player', () {
    final adapter = File(
      'third_party/just_audio_media_kit/lib/mediakit_player.dart',
    ).readAsStringSync();
    final seekStart = adapter.indexOf('Future<SeekResponse> seek(');
    final seekEnd = adapter.indexOf('Future<void> _applySeek(', seekStart);
    final seek = adapter.substring(seekStart, seekEnd);

    expect(seek, contains('if (_audioReady)'));
    expect(seek, contains('await _applySeek(_position);'));
    expect(
      seek.indexOf('await _applySeek(_position);'),
      lessThan(seek.indexOf('_position == Duration.zero')),
    );
  });

  test('Windows SMTC is initialized before controllers use it', () {
    final main = File('lib/main.dart').readAsStringSync();
    final initialize = main.indexOf(
      'await DesktopAudioPlatform.initializeWindowsMediaControls()',
    );
    final audioService = main.indexOf('initAudioService(');

    expect(initialize, greaterThanOrEqualTo(0));
    expect(audioService, greaterThan(initialize));
    // No `await` in the needle: the native side is an arrow body returning the
    // future, and the await lives at the call site above.
    expect(
      File('lib/services/desktop_audio_platform_native.dart').readAsStringSync(),
      contains('SMTCWindows.initialize()'),
    );
  });

  test('Windows audio backend records endpoint diagnostics', () {
    final handler = File('lib/services/audio_handler.dart').readAsStringSync();
    final desktop = File(
      'lib/services/desktop_audio_platform_native.dart',
    ).readAsStringSync();
    final adapter = File(
      'third_party/just_audio_media_kit/lib/mediakit_player.dart',
    ).readAsStringSync();

    // The callback is wired on the native side; the handler still owns what is
    // done with it, which is why only the first expectation moved.
    expect(desktop, contains('JustAudioMediaKit.diagnosticCallback'));
    expect(handler, contains('windows-audio/\$category'));
    // `audio-device` and `audio-params` reach the callback as mpv *warnings*.
    // The library defaults to `error`, so dropping this line silently empties
    // the diagnostics — which is exactly what happened once already.
    expect(desktop, contains('JustAudioMediaKit.mpvLogLevel'));
    expect(desktop, contains('MPVLogLevel.warn'));
    expect(adapter, contains("'audio-device'"));
    expect(adapter, contains("'audio-params'"));
  });

  test('Windows player keeps loading state until decoded audio is ready', () {
    final adapter = File(
      'third_party/just_audio_media_kit/lib/mediakit_player.dart',
    ).readAsStringSync();
    final miniPlayer = File(
      'lib/ui/player/components/mini_player.dart',
    ).readAsStringSync();

    expect(adapter, contains('bool _sourceLoading = false;'));
    expect(adapter, contains('_sourceLoading = true;'));
    expect(adapter, contains('_sourceLoading = false;'));
    expect(adapter, contains('await _waitForDecodedAudio();'));
    expect(adapter, contains('sourceReadyCompleter.complete();'));
    expect(miniPlayer, contains('CircleAvatar('));
    expect(miniPlayer, contains('animation: playerController.volume'));
    expect(miniPlayer, contains("'\$volume%'"));
  });

  test('Windows source changes keep the initialized output endpoint warm', () {
    final handler = File('lib/services/audio_handler.dart').readAsStringSync();
    final adapter = File(
      'third_party/just_audio_media_kit/lib/mediakit_player.dart',
    ).readAsStringSync();

    expect(handler, contains('RuntimePlatform.isDesktop'));
    expect(handler, contains('await _player.pause();'));
    expect(handler, contains('_clearCurrentSourceForReplacement();'));
    expect(adapter, contains('if (_sources.isEmpty)'));
    expect(adapter, contains('await _player.pause();'));
  });

  test('fresh Windows sources are opened once by load', () {
    final adapter = File(
      'third_party/just_audio_media_kit/lib/mediakit_player.dart',
    ).readAsStringSync();

    expect(adapter, contains('final wasEmpty = _sources.isEmpty;'));
    expect(adapter, contains('if (wasEmpty) {'));
    expect(adapter, contains('return ConcatenatingInsertAllResponse();'));
    expect(adapter, contains('await _openSources(index: _currentIndex'));
  });
}
