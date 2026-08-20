import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/stream_service.dart';

Audio _audio(int itag, Codec codec, int bitrate) => Audio(
  itag: itag,
  audioCodec: codec,
  bitrate: bitrate,
  duration: 199845,
  loudnessDb: 0,
  url: 'https://example.invalid/$itag',
  size: 1000,
);

/// The selectors used to choose by position in the manifest, not by
/// preference. youtube_explode 2.3.7 listed formats mp4a-last so that happened
/// to yield mp4a; 3.1.0 lists them opus-last, and the same code silently began
/// returning opus for every song — which the app then cached to a `.mp3` path.
/// These tests pin the choice to the codec, in both orders.
void main() {
  _clientSelection();
  _cacheStaleness();
  _playbackCorrectness();

  const mp4aFirst = [139, 140, 249, 251];
  const opusFirst = [251, 249, 140, 139];

  StreamProvider providerFor(List<int> order) => StreamProvider(
    playable: true,
    audioFormats: [
      for (final itag in order)
        _audio(
          itag,
          itag == 140 || itag == 139 ? Codec.mp4a : Codec.opus,
          switch (itag) { 140 => 148042, 251 => 147692, 249 => 59426, _ => 55151 },
        ),
    ],
  );

  for (final order in [mp4aFirst, opusFirst]) {
    final label = order.first == 139 ? 'mp4a-first' : 'opus-first';

    test('highest quality is mp4a 140 regardless of order ($label)', () {
      expect(providerFor(order).highestQualityAudio!.itag, 140);
    });

    test('low quality is mp4a 139 regardless of order ($label)', () {
      expect(providerFor(order).lowQualityAudio!.itag, 139);
    });

    test('codec-specific selectors stay on their codec ($label)', () {
      final provider = providerFor(order);
      expect(provider.highestBitrateMp4aAudio!.itag, 140);
      expect(provider.highestBitrateOpusAudio!.itag, 251);
    });
  }

  test('falls back to what is offered when a preferred itag is absent', () {
    final onlyOpus = StreamProvider(
      playable: true,
      audioFormats: [_audio(251, Codec.opus, 147692)],
    );
    expect(onlyOpus.highestQualityAudio!.itag, 251);
    expect(onlyOpus.highestBitrateMp4aAudio!.itag, 251);
  });

  test('no formats yields no selection rather than throwing', () {
    final empty = StreamProvider(playable: false, audioFormats: const []);
    expect(empty.highestQualityAudio, isNull);
  });
}

/// The client choice is the difference between playable and 403.
void _clientSelection() {
  final service = File('lib/services/stream_service.dart').readAsStringSync();
  final fork = File(
    'third_party/youtube_explode_dart/lib/src/videos/youtube_api_client.dart',
  ).readAsStringSync();

  test('extraction asks for the VISIONOS client first', () {
    // Every other client's URLs are proof-of-origin gated: they extract fine,
    // then 403 any open-ended read, which is exactly what a player issues.
    // VISIONOS is the one that still serves whole files — and needs no JS
    // player, so extraction stays off the UI thread.
    expect(fork, contains("'clientName': 'VISIONOS'"));
    expect(service, contains('YoutubeApiClient.visionos'));

    // Exactly one client. getManifest has no early exit: it runs every client
    // in the list, each with a 5-attempt retry, so adding a gated one as a
    // "fallback" just pays for a doomed round trip on every song.
    expect(
      service.contains('YoutubeApiClient.androidSdkless'),
      isFalse,
      reason: 'a gated client can only return URLs that do not play',
    );
    expect(
      RegExp(r'YoutubeApiClient\.\w+').allMatches(service).length,
      1,
      reason: 'every extra client costs a full resolve per song',
    );
  });
}

/// Expiry alone does not make a cached URL usable.
void _cacheStaleness() {
  final handler = File('lib/services/audio_handler.dart').readAsStringSync();

  test('cached stream URLs are invalidated when the client changes', () {
    // Gated URLs kept a valid `expire` stamp while becoming unplayable, so the
    // cache served them, ExoPlayer 403'd, and playback only recovered on the
    // retry — one wasted load per previously-played song.
    expect(handler, contains('_cachedUrlStillPlayable'));
    expect(handler, contains("_streamClientName = 'VISIONOS'"));

    final guard = handler.substring(
      handler.indexOf('if (streamInfoJson != null && !generateNewUrl)'),
      handler.indexOf('Got cached Url'),
    );
    expect(
      guard,
      contains('_cachedUrlStillPlayable'),
      reason: 'the client check must gate the cache hit, not just exist',
    );
    expect(guard, contains('isExpired'), reason: 'expiry check still required');
  });

  test('the cache client name matches what extraction actually requests', () {
    // These drifting apart would invalidate every entry forever, or none.
    final service = File('lib/services/stream_service.dart').readAsStringSync();
    expect(service, contains('YoutubeApiClient.visionos'));
    expect(handler, contains("'VISIONOS'"));
  });
}

/// Playback-path defects found by audit, each with a concrete failure mode.
void _playbackCorrectness() {
  final handler = File('lib/services/audio_handler.dart').readAsStringSync();
  final service = File('lib/services/stream_service.dart').readAsStringSync();

  test('a download inside app storage is still checked for existence', () {
    // The branch used to `return streamInfo` on a string path test alone. A
    // vanished file then reached just_audio, which does not raise on a missing
    // path — it parks in `loading` forever, indistinguishable from a hang.
    final branch = handler.substring(
      handler.indexOf('if (path.contains(supportMusicPath))'),
      handler.indexOf('//check file access and if file exist in storage'),
    );
    expect(branch, contains('_localSourceFileExists'));
    expect(
      branch,
      contains('offlineReplacementUrl: true'),
      reason: 'a missing download must fall back to online resolution',
    );
  });

  test('the preload path checks app-storage downloads too', () {
    final preload = handler.substring(
      handler.indexOf('final isInSupportDir = path.contains'),
      handler.indexOf('final streamInfoJson = song["streamInfo"]'),
    );
    expect(preload, contains('_localSourceFileExists'));
  });

  test('missing loudness data skips normalization instead of attenuating', () {
    // 0 is the "unknown" sentinel every placeholder writes. Treating it as a
    // real reading applied 10^(-5/20) = 0.56 to every track: no normalization,
    // just a permanent volume cut.
    final fn = handler.substring(
      handler.indexOf('Future<void> _normalizeVolume('),
      handler.indexOf('Future<void> saveSessionData('),
    );
    expect(fn, contains('if (currentLoudnessDb == 0)'));
    expect(fn, contains('return;'));
    // Must compose with the user's volume, not overwrite it, and must only
    // attenuate — otherwise a user at 50% gets pushed towards 100%.
    expect(fn, contains('_settingsRepository.getVolume()'));
    expect(fn, contains('min('));
  });

  test('loudness is read from the video-level playerConfig', () {
    // Reading it off a format entry returned null for every stream, which is
    // what made the sentinel the normal case.
    final fork = File(
      'third_party/youtube_explode_dart/lib/src/reverse_engineering/player/player_response.dart',
    ).readAsStringSync();
    expect(fork, contains('playerConfig/audioConfig/loudnessDb'));
  });

  test('a missing resolver source never reaches the player as a URI', () {
    // Falling through handed just_audio `resolver:///<id>`, a scheme no
    // platform player understands.
    final block = handler.substring(
      handler.indexOf("if (url.startsWith('resolver://'))"),
      handler.indexOf('final cacheSongsEnabled ='),
    );
    expect(block, contains('throw StateError'));
  });

  test('an empty format list is not reported as playable', () {
    // playable:true with no formats made HMStreamingData.fromJson dereference
    // a null lowQualityAudio.
    final at = service.indexOf('if (audio.isEmpty)');
    expect(at, greaterThan(-1));
    // Bounded by length, not by a newline-sensitive needle: this file is
    // stored with CRLF endings.
    final guard = service.substring(at, at + 600);
    expect(guard, contains('playable: false'));
  });
}
