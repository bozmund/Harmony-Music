# Harmony Music — clean-up and correctness pass

## Context

Online playback broke when YouTube began gating stream URLs behind a proof-of-origin
token. The fix landed earlier in this session: a `VISIONOS` innertube client added to the
vendored fork ([youtube_api_client.dart](third_party/youtube_explode_dart/lib/src/videos/youtube_api_client.dart)),
requested first by [stream_service.dart](lib/services/stream_service.dart). Verified on
device — `pXjcTIo5R0Q` loads in both `AudioSource.uri` and `LockCachingAudioSource`.

That leaves the repo in a messy state, and two audits surfaced real defects alongside it:

- The working tree mixes this session's playback work with an in-progress
  `DesktopAudioPlatform` refactor. **Decision: finish both, ship as one PR.**
- The QuickJS/EJS solver is dormant and now provably dead code. **Decision: remove it.**
- 3 unit tests and 15 integration tests fail. **Decision: fix both sets.**
- Several confirmed bugs, listed in Tier B/C below for approval before any are touched.

Intended outcome: a green suite, no dead dependencies, and the confirmed defects either
fixed or explicitly deferred — with the tree in a state that can be reviewed as one change.

---

## Tier A — already decided

### A1. Remove `flutter_js` and the QuickJS solver

Confirmed unused at runtime: `_localSignatureDecipheringEnabled` is a `static const false`,
so the tree shaker constant-folds the solver branch away. It still ships ~1.0 MB of
`libfastdev_quickjs_runtime.so` per ABI, registers a plugin on every cold start, and is the
source of the Kotlin-Gradle-Plugin deprecation warning (`flutter_js` pins KGP 1.7.20 / AGP
7.3.1). Unlike `auth0_flutter`, `file_picker`, `nsd_android` in that same warning, it is not
load-bearing.

- Delete [js_challenge_solver.dart](lib/services/js_challenge_solver.dart) and
  `flutter_js: ^0.8.7` from [pubspec.yaml:66](pubspec.yaml)
- Drop the `ejsModuleSource` parameter from `StreamProvider.fetch`
  ([stream_service.dart](lib/services/stream_service.dart)) and `getStreamInfo`
  ([background_task.dart](lib/services/background_task.dart)) — `getStreamInfo`'s nullable
  `token` collapses back to required
- Delete `_ejsModules`, `_ejsModuleSource()`, `_localSignatureDecipheringEnabled`; simplify
  `_resolveLocalOnline` to the unconditional `Isolate.run` branch
- Delete [test/js_challenge_solver_test.dart](test/js_challenge_solver_test.dart) (its
  assertions become vacuous) and strip the `ejsModules` arm from
  [song_resolve_live_test.dart](integration_test/song_resolve_live_test.dart)
- `BaseEJSSolver` stays unused in the vendored fork — costs nothing

### A2. Windows tests + two regressions in the refactor

All three failures are **stale test targets**, not lost behaviour — the code moved into
[desktop_audio_platform_native.dart](lib/services/desktop_audio_platform_native.dart) behind
the new `facade / native / stub` conditional-export triad. But the refactor did drop two
things:

**Regression 1 — `mpvLogLevel` silently lost.** `JustAudioMediaKit.mpvLogLevel =
MPVLogLevel.warn` existed at `HEAD:lib/services/audio_handler.dart:188`; the new
`DesktopAudioPlatform.configure` sets `title`, `protocolWhitelist` and `diagnosticCallback`
but not this. Library default is `MPVLogLevel.error`, so Windows no longer emits the
warning-level mpv logs that feed the `audio-device`/`audio-params` diagnostics —
i.e. the very thing the failing test suite exists to cover. Restore it inside `configure()`.

**Regression 2 — leftover implementation import.**
[audio_handler.dart:47-48](lib/services/audio_handler.dart) still has
`import "package:media_kit/src/player/platform_player.dart" show MPVLogLevel;`, and
`MPVLogLevel` has no other reference in `lib/`. A private `media_kit` implementation import
in a file meant to be platform-neutral defeats the refactor's purpose. Delete it (the symbol
moves to the native file with regression 1).

Then retarget the assertions in
[windows_playback_backend_test.dart](test/windows_playback_backend_test.dart):

| test | change |
|---|---|
| registers MediaKit before audio service | needle → `DesktopAudioPlatform.register()` in `main.dart`; add assertion that the native file contains `JustAudioMediaKit.registerWith()` |
| SMTC initialized before controllers | needle → `await DesktopAudioPlatform.initializeWindowsMediaControls()`; assert native file contains `SMTCWindows.initialize()` (no `await` — it's an arrow body) |
| endpoint diagnostics | move only the `JustAudioMediaKit.diagnosticCallback` expectation to the native file; leave `'windows-audio/$category'` on `audio_handler.dart` and the two `mediakit_player.dart` ones alone |

Add `JustAudioMediaKit.mpvLogLevel` to the diagnostics test so regression 1 cannot recur.
Extend [web_platform_boundaries_test.dart](test/web_platform_boundaries_test.dart) to cover
the `desktop_audio_platform` and `windows_audio_service` triads — it currently covers 3 of 5.

### A3. The 15 `player behavior` integration failures

`getAutoOpenPlayer()` defaults true ([hive_settings_repository.dart:206](lib/data/repositories/hive_settings_repository.dart)),
so on a 411dp emulator the full player takes over and `find.byType(MiniPlayer)` finds
nothing. Not a product bug — a test-determinism one.

Seed `autoOpenPlayer = false` via the existing `seedHive` hook in `bootTestApp`
([harness.dart](integration_test/support/harness.dart)) so layout is deterministic across
screen sizes. Keep one test that explicitly exercises the auto-open path, reusing the
device-agnostic either-route pattern already at
[player_behavior_test.dart:1028](integration_test/player_behavior_test.dart).

---

## Tier B — confirmed bugs, recommended (approve before I touch these)

### B1. A deleted download hangs the player forever

`checkNGetUrl`'s app-internal download branch returns `playable: true` after a **string**
test, with no filesystem check:

```dart
if (path.contains(supportMusicPath)) {
  return streamInfo;          // no File(path).exists()
}
```

The sibling branches both check: the cached-song branch deletes the stale entry and
re-resolves, and the external-storage branch falls back with `offlineReplacementUrl: true`.
The code's own comment says what happens when they don't:

> *Handing just_audio a missing file does not raise — it sits in `loading` forever, which
> looks exactly like a hung handoff.*

Reachable via OS storage cleanup, manual deletion, or a restored backup whose paths were
rewritten without verification. Result: frozen spinner, no error, no online fallback.
The same short-circuit exists in the preload path (`_downloadedStreamInfoForSong`).

**Fix:** call the existing `_localSourceFileExists` helper
([audio_handler.dart:1300](lib/services/audio_handler.dart)) in both places, falling back to
online resolution the way the external branch already does.

### B2. Loudness normalization is a flat −5 dB cut that eats the volume slider

Worse than the "silent no-op" I described earlier. `_normalizeVolume` computes
`10^((-5 - loudnessDb)/20)`; with `loudnessDb == 0.0` that is **0.562 on every track** —
identical attenuation for all songs, i.e. zero normalization plus a permanent volume cut.

And `loudnessDb` is 0.0 almost always: the fork reads it off each *format* entry, but
InnerTube carries it per *video* at `playerConfig/audioConfig/loudnessDb` — for which
`PlayerResponse` has no accessor at all. Every Resolver-sourced song hardcodes `0`, and
release builds force `ResolverSourceMode.both`, so the Resolver often wins the race.

It also silently overwrites the user's setting: `customAction('setVolume')` writes the same
`_player.setVolume`, and `_normalizeVolume` runs on every track start — so the slider lasts
until the next song, then snaps to 0.562.

Mitigating: default off, Android-only.

**Fix (three parts):** treat missing loudness as *unknown* and skip normalization entirely
rather than applying −5 dB; add a `playerConfig/audioConfig/loudnessDb` accessor to
`PlayerResponse` and thread it into `_StreamInfo`; make `_normalizeVolume` scale relative to
the user's stored volume instead of assigning absolute.

### B3. `resolver://` URLs can reach just_audio verbatim

`_createAudioSource` looks up `_resolverSources[mediaItem.id]`, and on a **miss falls
through** to `AudioSource.uri(Uri.parse('resolver://...'))` — an unsupported scheme handed to
ExoPlayer. Reachable: `_resetResolverSources()` wipes the whole map and runs at the top of
both `_resolveWithResolver` and `_raceOnlineResolvers`, including from the preload path — so
preparing song B disposes song A's not-yet-consumed source. No `else`, no log.

**Fix:** treat a miss as a resolution failure (re-resolve or surface a playback error), and
log it.

### B4. `HMStreamingData.fromJson` throws on a playable response with no audio

`StreamProvider.fetch` returns `playable: true` whenever `getManifest` succeeds, even with
`res.audioOnly` empty; `hmStreamingData` then emits `"lowQualityAudio": null` and
`fromJson` throws `NoSuchMethodError`. Swallowed into `failed()` inside the race, but
propagates uncaught in `ResolverSourceMode.existingOnly` (`_resolveLocalOnline` catches only
`TimeoutException`).

**Fix:** return `playable: false` with a real status when no audio formats are present.

---

## Tier C — confirmed, lower priority (fix only if you want them in this pass)

- **C1.** `ResolverAudioSource` leaked when `_startPreparingNextSource` discards a result —
  the source stays in `_resolverSources` undisposed until the next reset, holding a live HTTP
  body reader.
- **C2.** `Isolate.run(...).timeout(20s)` completes the future but does not kill the isolate;
  with no read timeout in the HTTP client, a half-open socket leaks one isolate per skipped
  slow song.
- **C3.** The stale-cache branch recurses into `checkNGetUrl` **without**
  `offlineReplacementUrl: true`, relying on `deleteCachedSong` having taken effect — infinite
  recursion if that delete fails. The three download branches all pass the flag correctly.
- **C4.** `catch (_)` in `_resolveWithResolver` and both race arms collapses every failure
  into `'resolverPlaybackFailed'` with no log — this is why diagnosing the 403 took as long
  as it did.
- **C5.** Cached/download branches never call `setQualityIndex`; harmless only because they
  set high and low quality to the same `Audio` instance. Latent trap.

---

## Verification

1. **Unit suite** — must be fully green, no pre-existing failures left:
   ```bash
   .flutter/bin/flutter.bat test
   ```
   Baseline is 609 passing / 3 failing; target 609+ passing / 0 failing.

2. **Integration suite** on the `claude_integration_test` AVD — baseline +61/15 failed;
   target 76 passing / 0 failed:
   ```bash
   .flutter/bin/flutter.bat test integration_test/all_tests.dart -d emulator-5554
   ```

3. **Live playback**, opt-in, proves the VISIONOS path end to end with no solver:
   ```bash
   .flutter/bin/flutter.bat test integration_test/song_playback_live_test.dart -d emulator-5554 --dart-define=LIVE_PLAYBACK_SONG_ID=pXjcTIo5R0Q
   ```

4. **APK check after removing `flutter_js`** — confirm `libfastdev_quickjs_runtime.so` is
   gone from `build/app/intermediates/merged_native_libs/` and that the KGP warning no longer
   lists `flutter_js`.

5. **Yours, on real devices** — Android playback with the Resolver off (proves the phone path
   standalone), Windows playback and SMTC controls (the refactor + `mpvLogLevel` restore),
   and volume behaviour if B2 is approved: set the slider mid-song, change track, confirm it
   holds.

---

## Out of scope

Backend work (Resolver, Cloud, Platform) is explicitly excluded, including the 234 tracks
failed with `backup_fingerprint_mismatch` and the 15 stale `yt_dlp_failed` records awaiting
retry in the admin console.
