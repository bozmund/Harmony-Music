import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/background_task.dart';
import 'package:harmonymusic/services/stream_service.dart';
import 'package:integration_test/integration_test.dart';

/// Resolves a real song against the real network, with nothing mocked.
///
/// Issue #66 reported "The Songcord (Cover)" never playing, and the diagnostics
/// showed the player wedged mid-resolve rather than failing: the previous source
/// was already torn down, the playlist was empty, `isSongLoading` was stuck true
/// and no error was ever raised. The cause was an unbounded await —
/// `_resolveLocalOnline` runs youtube_explode in an isolate, and its HTTP client
/// sets no read timeout, so a half-open socket neither returns nor throws.
///
/// Every other test in this suite mocks the network through `FakeMusicService`,
/// which is exactly why none of them could see this. This one drives the real
/// extraction path — the same `getStreamInfo`, dispatched the same way
/// `_resolveLocalOnline` dispatches it — so a song that genuinely cannot be
/// resolved says so, out loud, instead of presenting as a spinner.
///
/// **Opt-in**, following `resolver_phone_test.dart`: it needs live network and a
/// video that still exists, so it is skipped unless a song id is supplied. Run it
/// with:
///
/// ```bash
/// flutter test integration_test/song_resolve_live_test.dart -d <device> \
///   --dart-define=LIVE_RESOLVE_SONG_ID=pXjcTIo5R0Q
/// ```
///
/// Add `--dart-define=LIVE_RESOLVE_CONTROL_ID=<id>` with a song known to work to
/// tell "this song is broken" apart from "extraction is broken for everything".
/// Requests the first two bytes of a stream URL. Reports the HTTP status
/// rather than asserting, so a 403 reads as "deciphering is wrong" instead of
/// an unexplained test failure.
String _describe(Map<String, dynamic> json) {
  String one(String key) {
    final a = json[key] as Map?;
    if (a == null) return '$key=<none>';
    final url = (a['url'] as String?) ?? '';
    return '$key{itag=${a['itag']} codec=${a['audioCodec']} '
        'bitrate=${a['bitrate']} size=${a['size']} '
        'durMs=${a['approxDurationMs']} loudness=${a['loudnessDb']} '
        'host=${url.isEmpty ? '<none>' : Uri.parse(url).host}}';
  }

  return '${one('highQualityAudio')} ${one('lowQualityAudio')}';
}

Future<String> _serves(String? url) async {
  if (url == null || url.isEmpty) return '<no url>';
  try {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    // Deliberately open-ended, matching what a player issues. An earlier
    // version sent `Range: bytes=0-1` to keep the probe cheap and reported a
    // confident HTTP 206 for URLs that were in fact unplayable: without a
    // proof-of-origin token YouTube serves only a small prefix from offset 0
    // and 403s everything else, so a two-byte probe is the one request shape
    // that always passes. A green here must mean the stream is actually
    // readable.
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close().timeout(const Duration(seconds: 15));
    var body = 0;
    await for (final chunk in res) {
      body += chunk.length;
      if (body > 2000000) break;
    }
    client.close(force: true);
    return 'HTTP ${res.statusCode}, $body bytes';
  } catch (error) {
    return 'request failed: $error';
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const songId = String.fromEnvironment('LIVE_RESOLVE_SONG_ID');
  const controlId = String.fromEnvironment('LIVE_RESOLVE_CONTROL_ID');

  /// Mirrors `AudioHandler._resolveLocalOnline` exactly, including where the
  /// work runs, so what this measures is what playback actually does. With EJS
  /// including the isolate hop.
  Future<
    ({
      bool settled,
      bool playable,
      String status,
      Duration took,
      String serves,
      String detail,
    })
  >
  resolve(
    String id,
    Duration bound,
  ) async {
    final token = RootIsolateToken.instance!;
    final clock = Stopwatch()..start();
    try {
      final json = await Isolate.run(
        () => getStreamInfo(id, token),
      ).timeout(bound);
      clock.stop();
      return (
        settled: true,
        playable: json['playable'] == true,
        status: json['statusMSG']?.toString() ?? '<none>',
        took: clock.elapsed,
        // A resolved URL is not a playable one. If the n-parameter transform
        // is wrong the URL still comes back well-formed and `playable: true`,
        // and YouTube only rejects it when bytes are actually requested —
        // which surfaces as an opaque ExoPlayer "(0) Source error". Asking for
        // two bytes is what tells those two cases apart.
        serves: await _serves(json['highQualityAudio']?['url'] as String?),
        detail: _describe(json),
      );
    } on TimeoutException {
      clock.stop();
      return (
        settled: false,
        playable: false,
        status: 'no response within ${bound.inSeconds}s',
        took: clock.elapsed,
       serves: '<not reached>',
        detail: '<not reached>',
      );
    } catch (error) {
      clock.stop();
      return (
        settled: true,
        playable: false,
        status: 'threw ${error.runtimeType}: $error',
        took: clock.elapsed,
       serves: '<not reached>',
        detail: '<not reached>',
      );
    }
  }

  // Matches AudioHandler._localExtractionTimeout, the bound this fix introduced.
  const bound = Duration(seconds: 20);

  testWidgets('the reported song resolves against the live network', (
    tester,
  ) async {
    if (songId.isEmpty) {
      markTestSkipped(
        'Set --dart-define=LIVE_RESOLVE_SONG_ID=<videoId> to run this against '
        'the real network (issue #66 used pXjcTIo5R0Q).',
      );
      return;
    }

    // Drive the real production path: without the EJS bundle no solver is
    // built, and this would only prove that the song resolves from a client
    // whose URLs need no deciphering — saying nothing about QuickJS.
    if (controlId.isNotEmpty) {
      final control = await resolve(controlId, bound);
      // ignore: avoid_print
      print(
        'LIVE RESOLVE control  $controlId: settled=${control.settled} '
        'playable=${control.playable} status=${control.status} '
        'took=${control.took.inMilliseconds}ms serves=${control.serves}',
      );
      // ignore: avoid_print
      print('LIVE RESOLVE control  streams: ${control.detail}');
      expect(
        control.playable,
        isTrue,
        reason:
            'the control song did not resolve either, so this run says nothing '
            'about $songId — extraction is broken for everything right now '
            '(status: ${control.status})',
      );
    }

    final result = await resolve(songId, bound);
    // ignore: avoid_print
    print(
      'LIVE RESOLVE target   $songId: settled=${result.settled} '
      'playable=${result.playable} status=${result.status} '
      'took=${result.took.inMilliseconds}ms serves=${result.serves}',
    );
    // ignore: avoid_print
    print('LIVE RESOLVE target   streams: ${result.detail}');

    // The full format list, which hmStreamingData narrows to two. Worth seeing
    // whole: the app still has an mp4a-specific selector and caches to a .mp3
    // path, so an all-opus manifest is a behaviour change, not just a detail.
    final all = await StreamProvider.fetch(songId);
    // ignore: avoid_print
    print(
      'LIVE RESOLVE target   all formats: '
      '${all.audioFormats?.map((a) => '${a.itag}/${a.audioCodec.name}@${a.bitrate}').join(' ') ?? '<none>'}',
    );

    // Resolving the same song twice is the cheap check that the solver and its
    // caches actually survive `YoutubeExplode.close()`. When they did not, the
    // second pass cost as much as the first and times crept up every run until
    // extraction exceeded its bound.
    final again = await resolve(songId, bound);
    // ignore: avoid_print
    print(
      'LIVE RESOLVE target   $songId (2nd): playable=${again.playable} '
      'status=${again.status} took=${again.took.inMilliseconds}ms '
      'serves=${again.serves}',
    );

    // The #66 property, and the one this fix is really about: whatever the
    // answer is, there must BE an answer. An unsettled resolve is what left the
    // player spinning forever with the old source already gone.
    expect(
      result.settled,
      isTrue,
      reason:
          'extraction for $songId did not settle within ${bound.inSeconds}s. '
          'This is the issue #66 failure mode: before the fix this await was '
          'unbounded, so playback hung here permanently. The fix makes this '
          'forfeit the race so the Resolver can still serve the song.',
    );

    // Reported separately: a song that resolves to "not playable" is a real
    // answer and must not be confused with the hang above.
    expect(
      result.playable,
      isTrue,
      reason:
          'extraction answered for $songId but reported it unplayable '
          '(status: ${result.status}). Playback falls back to the Resolver in '
          'this case; if the Resolver has it, the song still plays.',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
