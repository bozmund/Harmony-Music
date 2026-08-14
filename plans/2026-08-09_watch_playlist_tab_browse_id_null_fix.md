# Fix the real cause of the unfilled "similar songs" queue

## Context

Your Windows run captured the actual failure, and it is **not** the `.first` bug I fixed earlier in
this session. That one was real (a valid response with no playlist id threw `StateError`), but it is
not what you were hitting. The log names the true culprit:

```
[Player]: watch queue lookup failed for zbtUyRkiU6s (attempt 1 of 5):
  NoSuchMethodError: The method '[]' was called on null.
  Receiver: null
  Tried calling: []("browseEndpoint")
#1  getTabBrowseId (package:harmonymusic/services/nav_parser.dart:480:71)
#2  MusicServices.getWatchPlaylist (package:harmonymusic/services/music_service.dart:341:25)
```

[`getTabBrowseId`](lib/services/nav_parser.dart:476) reads a tab's browse id like this:

```dart
if (!watchNextRenderer['tabs'][tabId]['tabRenderer'].containsKey('unselectable')) {
  return watchNextRenderer['tabs'][tabId]['tabRenderer']['endpoint']['browseEndpoint']['browseId'];
}
```

It treats "not marked `unselectable`" as proof that `endpoint` exists. For this track it isn't:
`['endpoint']` returns null, and `null['browseEndpoint']` throws. Because the throw happens at
[music_service.dart:340-341](lib/services/music_service.dart:340) — *before* any track is parsed —
the whole `getWatchPlaylist` call dies and every track in a perfectly good response is discarded.

That explains exactly what you described. It is deterministic per song (a track whose lyrics or
related tab carries no endpoint), which is why some songs fill the queue and others never do, and why
it only affects online playback — offline library playback goes through `playPlayListSong`, which
never makes this call.

The log also shows a second, smaller problem I introduced: the retry loop treated this as transient
and burned all five attempts (1s + 2s + 4s + 8s ≈ 15 s) on a failure that can never succeed, twice in
one session. The "Finding similar songs…" row spins for 15 s and then gives up, which is worse than
failing immediately.

Intended outcome: tapping a song fills the queue for these tracks too, and a genuinely unparseable
response fails fast instead of spinning.

---

## The fix

### 1. Make `getTabBrowseId` null-safe — this is the actual bug

`lib/services/nav_parser.dart`

Rewrite [`getTabBrowseId`](lib/services/nav_parser.dart:476) to use the existing
[`nav()`](lib/services/nav_parser.dart:638) helper, which already walks a path and returns null on
any missing hop instead of throwing:

- Resolve `['tabs', tabId, 'tabRenderer']` through `nav`; return null if it is not a `Map` or it
  contains `unselectable`.
- Resolve `['endpoint', 'browseEndpoint', 'browseId']` through `nav` and return it.
- Widen the parameter from `Map<String, dynamic>` to `dynamic`, so a null or unexpectedly-shaped
  `watchNextRenderer` also yields null rather than throwing at the call site.

A missing browse id is an ordinary answer here: both callers assign it to optional fields
(`lyricsBrowseId`, `relatedBrowseId`). Only the `onlyRelated` early-return at
[music_service.dart:342](lib/services/music_service.dart:342) reads them, and it already returns them
as nullable.

### 2. Never let the decorative fields take the tracks down with them

`lib/services/music_service.dart`

Even with the above fixed, the lyrics/related lookup sits upstream of all track parsing and can still
abort the call if the response shape shifts again. Wrap the two `getTabBrowseId` calls at
[lines 340-341](lib/services/music_service.dart:340) so a failure leaves them null and parsing
continues. This is the same principle as the `watchPanelPlaylistId` guard already added below it —
an optional field must never be able to discard the queue.

### 3. Stop retrying failures that cannot succeed

`lib/ui/player/player_controller.dart`

[`_fetchWatchQueue`](lib/ui/player/player_controller.dart:1854) currently retries every exception.
Split them:

- **Transient** — `DioException`, `SocketException`, `TimeoutException`. Keep the existing backoff
  retry; this is what it was built for.
- **Deterministic** — anything else (`NoSuchMethodError`, `TypeError`, `StateError`,
  `FormatException`): a parsing failure against a response we already received. Log it once with the
  stack trace and return null immediately.

Fifteen seconds of backoff cannot change how a document parses. Failing fast also clears
`isQueueExpanding` straight away, so the indicator stops promising something that is not coming.

---

## Tests

**Unit — `test/watch_panel_playlist_id_test.dart`** (extend; it already covers this family of
parser guards):

1. A tab with no `endpoint` and no `unselectable` yields null instead of throwing — the exact shape
   from your log, and the regression test for the reported bug.
2. A tab marked `unselectable` yields null.
3. A well-formed tab yields its browse id.
4. A null or malformed `watchNextRenderer` yields null.

**Unit — new, for the retry policy.** Assert that `_fetchWatchQueue` retries a `DioException` and
does **not** retry a `StateError`/`NoSuchMethodError`. The existing
`test/player_controller_queue_order_test.dart` parses controller source text, so a source-level guard
fits its conventions; a behavioural test would need a `PlayerController` instance, which that file
deliberately avoids.

**Integration — `integration_test/player_behavior_test.dart`.** The `_FlakyWatchQueueService` fake
added earlier throws `StateError`, which under this change becomes non-retryable. Two updates:

- Give the fake a selectable error type so the existing retry tests
  ("a failed watch-playlist lookup is retried", "the queue shows it is still filling", "a newer tap
  cancels an in-flight retry loop") keep throwing a *transient* error and still exercise the backoff.
- Add a case asserting a parse-shaped error is **not** retried: exactly one call, the song still
  plays, and the indicator clears promptly rather than after 15 s.

---

## Verification

1. **Unit suite** (mine to run) — currently 574 passing, must stay green:
   ```bash
   .flutter/bin/flutter.bat test
   ```

2. **Integration suite** on the `claude_integration_test` AVD (mine to run):
   ```bash
   .flutter/bin/flutter.bat test integration_test/all_tests.dart -d emulator-5554
   ```
   Baseline to compare against: **+57 passed, 1 skipped, 15 failed**. Those 15 are pre-existing —
   verified identical on a clean worktree at `HEAD` — and all fail on the MiniPlayer because
   `getAutoOpenPlayer()` defaults to true on this 411dp AVD. Note this needs the Android Studio JBR
   workaround: Gradle 8.14.3 cannot parse its version string, so set `flutter config --jdk-dir` to
   JDK 21 or the build fails before any test runs.

3. **The real check is yours, on Windows.** Play `zbtUyRkiU6s` ("Djuskavacc") — the exact track from
   your log, and the one that reproduces this deterministically. Expected: the queue fills with
   similar songs, and `watch queue lookup failed` no longer appears. Tap a few other songs from Home
   and from search as well. If any still fails, the log line now carries the parse error and stack
   trace, and it will appear **once** rather than five times — send it over and I can name the next
   shape mismatch the same way this one was found.
