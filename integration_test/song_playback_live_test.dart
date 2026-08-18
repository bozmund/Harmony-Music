import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/stream_service.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// Resolving a URL and *playing* it are different claims.
///
/// `song_resolve_live_test.dart` proves extraction returns a URL that serves
/// bytes to `dart:io` — and it does, HTTP 206. The device still failed with an
/// opaque `(0) Source error` from ExoPlayer, which that test cannot see because
/// it never hands the URL to a player. This one does, through the same two
/// source types `_createAudioSource` builds, so ExoPlayer states its actual
/// objection somewhere I can iterate on instead of on Jan's phone.
///
/// **Opt-in**, like its sibling:
///
/// ```bash
/// flutter test integration_test/song_playback_live_test.dart -d emulator-5554 \
///   --dart-define=LIVE_PLAYBACK_SONG_ID=In6_WWlt5LE
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const songId = String.fromEnvironment('LIVE_PLAYBACK_SONG_ID');

  Future<String> tryLoad(String label, AudioSource source) async {
    final player = AudioPlayer();
    final clock = Stopwatch()..start();
    try {
      final duration = await player
          .setAudioSource(source)
          .timeout(const Duration(seconds: 30));
      clock.stop();
      return '$label: OK duration=$duration in ${clock.elapsedMilliseconds}ms';
    } catch (error) {
      clock.stop();
      return '$label: ${error.runtimeType}: $error '
          '(after ${clock.elapsedMilliseconds}ms)';
    } finally {
      await player.dispose();
    }
  }

  testWidgets('a resolved song actually loads in the player', (tester) async {
    if (songId.isEmpty) {
      markTestSkipped(
        'Set --dart-define=LIVE_PLAYBACK_SONG_ID=<videoId> to run this against '
        'the real network and the real player.',
      );
      return;
    }

    // No EJS modules on purpose: the VISIONOS client needs no signature
    // deciphering, so production runs with the solver off and extraction on a
    // background isolate. Passing modules here would test a path the app no
    // longer takes — and the one that ANR'd the UI thread.
    final provider = await StreamProvider.fetch(songId);
    expect(provider.playable, isTrue, reason: 'extraction: ${provider.statusMSG}');

    final audio = provider.highestQualityAudio!;
    // ignore: avoid_print
    print('LIVE PLAY chose itag=${audio.itag} codec=${audio.audioCodec.name} '
        'size=${audio.size} durMs=${audio.duration}');

    final item = MediaItem(id: songId, title: 'live playback probe');
    final uri = Uri.parse(audio.url);

    // The player 403s a URL that answers a ranged dart:io probe with 206, so
    // compare request shapes directly before blaming the player. Also dump the
    // URL's query keys: which innertube client issued it, and whether it
    // carries a proof-of-origin token, decides whether this is fixable here.
    // ignore: avoid_print
    print('LIVE PLAY url params: ${uri.queryParameters.keys.toList()..sort()}');
    // ignore: avoid_print
    print('LIVE PLAY url c=${uri.queryParameters['c']} '
        'pot=${uri.queryParameters.containsKey('pot')} '
        'expire=${uri.queryParameters['expire']}');

    for (final probe in <({String label, Map<String, String> headers})>[
      (label: 'no headers', headers: {}),
      (label: 'range 0-1', headers: {HttpHeaders.rangeHeader: 'bytes=0-1'}),
      (label: 'range 0-', headers: {HttpHeaders.rangeHeader: 'bytes=0-'}),
      (
        label: 'exoplayer-ish UA',
        headers: {
          HttpHeaders.userAgentHeader:
              'Mozilla/5.0 (Linux; Android 14) ExoPlayerLib/2.18.1',
        },
      ),
    ]) {
      final client = HttpClient();
      try {
        final req = await client.getUrl(uri);
        probe.headers.forEach(req.headers.set);
        final res = await req.close().timeout(const Duration(seconds: 20));
        final bytes = await res.fold<int>(0, (n, c) => n + c.length);
        // ignore: avoid_print
        print('LIVE PLAY probe ${probe.label}: HTTP ${res.statusCode} '
            '($bytes bytes)');
      } catch (error) {
        // ignore: avoid_print
        print('LIVE PLAY probe ${probe.label}: failed $error');
      } finally {
        client.close(force: true);
      }
    }

    // Plain streaming, the `AudioSource.uri` branch.
    // ignore: avoid_print
    print('LIVE PLAY ${await tryLoad('AudioSource.uri', AudioSource.uri(uri, tag: item))}');

    // The LockCaching branch, including the `.mp3` cache filename the app uses
    // regardless of the actual container.
    final dir = await getApplicationDocumentsDirectory();
    final cacheFile = File('${dir.path}/live_probe_$songId.mp3');
    if (await cacheFile.exists()) await cacheFile.delete();
    // ignore: experimental_member_use
    final caching = LockCachingAudioSource(uri, cacheFile: cacheFile, tag: item);
    // ignore: avoid_print
    print('LIVE PLAY ${await tryLoad('LockCachingAudioSource(.mp3)', caching)}');
    if (await cacheFile.exists()) await cacheFile.delete();

    // Also try the other codec, to tell "this URL is bad" apart from "this
    // container is what ExoPlayer is refusing".
    final other = provider.audioFormats!.firstWhere(
      (a) => a.audioCodec != audio.audioCodec,
      orElse: () => audio,
    );
    if (other.itag != audio.itag) {
      // ignore: avoid_print
      print('LIVE PLAY ${await tryLoad('AudioSource.uri itag=${other.itag}/${other.audioCodec.name}', AudioSource.uri(Uri.parse(other.url), tag: item))}');
    }
  });
}
