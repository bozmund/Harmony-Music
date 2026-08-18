# Fix #66 — stream resolution can hang forever and wedge the player

## Context

[Issue #66](https://github.com/bozmund/Harmony-Music/issues/66) reports "The Songcord (Cover)"
(`pXjcTIo5R0Q`) never playing. The attached diagnostics show the player wedged rather than failing:

```
isSongLoading: true            sourceSwitchInProgress: true
processingState: "idle"        playListChildren: 0
errorCode: null                errorMessage: null
mediaItem.extras: hasUrlExtra: false
currentSongUrlState: { isEmpty: false, scheme: "", host: "", pathLength: 137 }
positionMs: 83059              durationMs: 183841   (media item duration is 156000)
```

Those five facts locate the hang precisely inside the `playByIndex` custom action
([audio_handler.dart:1823-2006](lib/services/audio_handler.dart:1823)):

| Evidence | What it rules in / out |
|---|---|
| `playListChildren: 0`, player `idle` | [line 1866](lib/services/audio_handler.dart:1866) `_clearCurrentSourceForReplacement()` **did** run — the old source is gone |
| `hasUrlExtra: false` | [line 1904](lib/services/audio_handler.dart:1904), the only place `extras['url']` is assigned, **never** ran |
| `sourceSwitchInProgress: true` | the abandon-returns at [1872](lib/services/audio_handler.dart:1872)/[1882](lib/services/audio_handler.dart:1882) did **not** run — they call `_endSourceSwitch()` |
| `errorCode: null` | the unplayable path at [1886](lib/services/audio_handler.dart:1886) (sets 404) and the `catch` at [1995](lib/services/audio_handler.dart:1995) (sets 500) both did **not** run |

Everything after 1866 and before 1904 is one statement:

```dart
1869  var streamInfo = await futureStreamInfo;   // unbounded
```

**Stream resolution hung and never settled.** The old source was already torn down, so the player sits
`idle` with an empty playlist, `isSongLoading` stuck true, and no error ever surfaced — a spinner that
runs forever. The stale `positionMs`/`durationMs` are the previous song's, and the 137-character
scheme-less `currentSongUrl` is likewise a leftover, since 1904 never assigned a new one.

**Why the await can never settle.** There is no `.timeout()` anywhere in `audio_handler.dart`. The
chain is `_sourceInfoForPlayback` → `_streamInfoForSong` → `checkNGetUrl` →
[`_raceOnlineResolvers`](lib/services/audio_handler.dart:2709), which completes its completer only when
one branch succeeds **or** `failures == 2`. Its two branches are the Harmony Resolver and
`_resolveLocalOnline` (the app fetching directly via youtube_explode in `Isolate.run`). The direct
fetch has no read timeout, so a half-open socket neither returns nor throws — `failed()` is never
called, `failures` never reaches 2, and the completer is never completed. One stalled socket wedges
playback permanently.

This is exactly the gap in the fallback you described: not downloaded → Resolver and the app's own
fetch race → whichever wins plays. That chain is correct and already implemented. It just cannot fail
over when a branch hangs instead of failing.

Intended outcome: a stalled resolve fails over to the other source, and can never leave the player
spinning with no error.

---

## The fix

### 1. Let a stalled branch lose the race — `_raceOnlineResolvers`

`lib/services/audio_handler.dart`, [`_resolveLocalOnline`](lib/services/audio_handler.dart:2774) (and
the matching `_openResolver` await inside the race).

Bound each branch so a hang is treated as that branch failing, rather than as silence:

- Wrap `_resolveLocalOnline`'s `Isolate.run(...)` in `.timeout(...)`, catching `TimeoutException` and
  returning `HMStreamingData(playable: false, statusMSG: ...)`.
- The race's existing `catch (_) { failed(); }` blocks then do the rest for free: `failed()` fires, and
  if the Resolver has already answered the song simply plays from it.

This is the change that actually recovers playback — it is what makes the race a race again.

**Suggested bound: 20s for the direct fetch.** Deliberately longer than a healthy extraction and
shorter than the Resolver's own `ingestionPollTimeout` of 30s
([resolver_playback_client.dart:65-67](lib/services/resolver/resolver_playback_client.dart:65)), so a
legitimate cold ingestion still wins rather than being cut off.

### 2. Never let the player wedge — bound the resolve at the call site

Add `.timeout(...)` to `await futureStreamInfo` ([1869](lib/services/audio_handler.dart:1869)) and the
retry ([1876](lib/services/audio_handler.dart:1876)) in `playByIndex`, and to the equivalents at
[2065](lib/services/audio_handler.dart:2065)/[2071](lib/services/audio_handler.dart:2071) in
`setSourceNPlay`.

No new error handling is needed: a `TimeoutException` falls into the existing `catch`
([1995](lib/services/audio_handler.dart:1995) / [2137](lib/services/audio_handler.dart:2137)), which
already calls `_handleSourcePlaybackFailure` — that clears `isSongLoading`, calls `_endSourceSwitch()`,
sets an errorCode and surfaces a `playError`. Reuse it rather than writing a second failure path.

**Suggested bound: 60s.** A pure backstop that must sit above every inner timeout, including the
Resolver's 30s ingestion poll, so it only ever fires when something is genuinely stuck.

### 3. Stop the abandon-returns leaking the spinner

Four early returns clear the switch flag but leave `isSongLoading` true forever —
[1872](lib/services/audio_handler.dart:1872), [1882](lib/services/audio_handler.dart:1882),
[1938](lib/services/audio_handler.dart:1938), [1975](lib/services/audio_handler.dart:1975), plus
[2067](lib/services/audio_handler.dart:2067)/[2120](lib/services/audio_handler.dart:2120) in
`setSourceNPlay`. `_endSourceSwitch()` ([1159](lib/services/audio_handler.dart:1159)) deliberately
touches only the switch flags.

These fire when a newer tap supersedes an in-flight one, so they are reachable in ordinary use. Add
`isSongLoading = false;` to each. Cheap, and it closes the same class of stuck spinner from a
different direction.

---

## Tests

`test/audio_handler_source_swap_test.dart` already asserts on this action's structure, and
`test/cached_audio_file_presence_test.dart` documents the "sits in `loading` indefinitely" symptom.
Both use source-level assertions because the real path needs a platform audio player and a populated
Hive box, neither of which exists under `flutter test` — follow that convention.

Add:

1. **The resolve is bounded.** Assert the `playByIndex` and `setSourceNPlay` bodies contain `.timeout(`
   around the stream-info awaits. This is the regression test for #66 — today's code passes every
   other assertion in these files while still hanging.
2. **A stalled direct fetch counts as a failure.** Assert `_resolveLocalOnline` bounds its
   `Isolate.run` and returns a non-playable result on timeout, so `_raceOnlineResolvers` can complete
   from the Resolver alone.
3. **Abandoned requests clear the spinner.** Assert every `_endSourceSwitch(); return;` in both actions
   is preceded by `isSongLoading = false`.

---

## Verification

1. **Unit tests** (mine to run) — 588 passing today, must stay green plus the new cases:
   ```bash
   .flutter/bin/flutter.bat test
   ```

2. **Integration suite** on the `claude_integration_test` AVD (mine to run). Baseline is **+61 passed,
   1 skipped, 15 failed**; those 15 are pre-existing and unrelated — verified identical on a clean
   worktree at `HEAD`, all failing on the MiniPlayer because `getAutoOpenPlayer()` defaults true on
   that 411dp device. Needs the JDK workaround, since Gradle 8.14.3 cannot parse Android Studio's
   bundled JBR version string:
   ```bash
   .flutter/bin/flutter.bat test integration_test/all_tests.dart -d emulator-5554
   ```

3. **The real check is yours.** The hang needs a stalled socket, which I cannot reproduce on demand —
   so the honest test is that normal playback is unaffected, and that if it ever recurs the app now
   reports an error and stays usable instead of spinning. Play a mix of songs, including
   `pXjcTIo5R0Q`. If a resolve does stall, the log will show `playByIndex` failing through
   `_handleSourcePlaybackFailure` rather than going quiet.

---

## Deliberately not in this change

**The missing-downloaded-file hole.** The app-internal download branch
([audio_handler.dart:2580](lib/services/audio_handler.dart:2580)) returns `playable: true` without
checking the file exists, while the external-storage branch below it and the cached-song branch above
it both do. A vanished download therefore hands just_audio a path to nothing, which — per the comment
at [2470-2474](lib/services/audio_handler.dart:2470) — also hangs in `loading` forever. It is a real
bug and a close cousin of this one, but it is **not** what #66 hit (that dump has an empty playlist;
this variant would show `playListChildren: 1`). Worth its own small PR.
