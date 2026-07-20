# Fix: playback state lost when Android kills the app during a phone call

## Context

A real-user bug report (Croatian): she played 3 songs, an incoming call paused playback, the app was killed during the call. Symptoms: (a) playback did **not** auto-resume after the call, (b) the media notification stayed frozen with stale songs, (c) reopening the app restored the **first** song of the queue instead of the third.

Verified root causes:

1. **Kill + no resume + stale notification:** `AudioServiceConfig` at [lib/services/audio_handler.dart:83-84](lib/services/audio_handler.dart) sets `androidNotificationOngoing: true, androidStopForegroundOnPause: true`. On the call-induced pause, the vendored `AudioService.java` `exitPlayingState()` (third_party/audio_service/android/src/main/java/com/ryanheise/audioservice/AudioService.java:715-719) demotes the service out of foreground → prime OOM-kill target during the call. Process death destroys just_audio's in-memory `_playInterrupted` resume flag (interruption handling is fully delegated to just_audio defaults; there is no app-level audio_session code), and leaves a zombie notification.
2. **Wrong song on restore:** session (queue/index/position) is saved **only** on lifecycle events — `AppLifecycleState.paused/detached` (lib/main.dart:237,239), gated `onTaskRemoved` (audio_handler.dart:1951-1958), desktop tray. Never on track change. Auto-advance updates in-memory `currentIndex` (playByIndex case, audio_handler.dart:1387) without persisting, so a hard kill restores the last durable snapshot — index 0. The restore path itself (`PlayerController._restorePrevSession()` lib/ui/player/player_controller.dart:701-718 → playByIndex `restoreSession` branch audio_handler.dart:1479-1488) is correct; **no changes there**.

User explicitly chose the **full fix** (both parts) after discussing the tradeoff.

## Step 0 — plan convention

Per CLAUDE.md: before implementing, save this accepted plan as a timestamped Markdown file in repo-root `plans/` and add it to `plans/index.md`.

## Part A — persist session on track change, pause, and periodically

All in `lib/services/audio_handler.dart` + small repository addition.

**A1. New fields** (near `currentIndex`, ~line 107): `Timer? _sessionSaveDebounce; Timer? _periodicPositionSaveTimer; bool _suppressSessionSave = false; bool _wasPlayingForSessionSave = false;`

**A2. New `_listenForSessionPersistence()`**, called from `_init()` right after `_listenForDurationChanges()` (line 242):

- `mediaItem.distinct((a,b) => a?.id == b?.id).listen(...)` → track change (auto-advance, skip, shuffle, setSourceNPlay) → `_scheduleSessionSave(positionOverride: Duration.zero)` (new song starts at 0; `_player.position` is unreliable mid source-switch).
- `_player.playingStream.listen(...)` → on playing→not-playing transition (tracked via `_wasPlayingForSessionSave`), save with live position — **this is the critical hook**: a phone-call pause comes from just_audio's internal handler calling `_player.pause()` directly and never reaches the handler's `pause()` override. Skip when `_sourceSwitchInProgress || isSongLoading` (the `_player.stop()` inside playByIndex would otherwise save the old song's position). Also call `_syncPeriodicPositionSaves(playing)`.
- `queue.listen(...)` → debounced full save on queue mutations (reorder, play-next, clear) so periodic index/position saves never point into a stale queue.

`_scheduleSessionSave({Duration? positionOverride})`: return early if `_suppressSessionSave` or `currentIndex is! int` (never fabricate index 0 — that's the original bug); 800 ms debounce timer → `unawaited(saveSessionData(positionOverride: ...))` with the guards re-checked inside the timer callback.

`_syncPeriodicPositionSaves(bool playing)`: while playing, a 30 s `Timer.periodic` calling the new lightweight `savePosition(index, positionMs)` (two int puts — no queue re-serialization); guarded by `_suppressSessionSave`, `currentIndex is! int`, `_player.playing`, and `getRestorePlaybackSession()`. Cancel + null the timer when not playing.

**A3. `saveSessionData()`** (line 1904): add optional `{Duration? positionOverride}`; position = `positionOverride?.inMilliseconds ?? _player.position.inMilliseconds`. Existing call sites unchanged (keep `currentIndex ?? 0` semantics for explicit lifecycle saves; the new automatic triggers are protected by the `is! int` guard).

**A4. Restore-clobber protection** in the `playByIndex` case (line 1385): after reading `restoreSession` (line 1390), set `_suppressSessionSave = true` when restoring; add `finally { if (restoreSession) _suppressSessionSave = false; }` to the case's existing try/catch (early `return`s route through `finally`). This stops the `mediaItem.add(currentSong)` at line 1402 from clobbering the saved position with 0 during startup restore. The `addQueueItems` during restore fires the queue listener while `currentIndex` is still null — already blocked by the `is! int` guard.

**A5. Cleanup** in customAction `'dispose'` (line 1378): cancel both timers.

**A6. Repository**: add `Future<void> savePosition({required int index, required int position});` to [lib/domain/repositories/playback_session_repository.dart](lib/domain/repositories/playback_session_repository.dart) and implement in [lib/data/repositories/hive_playback_session_repository.dart](lib/data/repositories/hive_playback_session_repository.dart) (two `box.put`s for 'index'/'position', **no** 'queue' write). `Hive.openBox` on an open box returns the cached instance, so no box caching needed.

## Part B — keep the service foreground while paused

**B1.** [lib/services/audio_handler.dart:83-84](lib/services/audio_handler.dart): flip **both** flags together (vendored `AudioServiceConfig` assert at third_party/audio_service/lib/audio_service.dart:3524-3527 requires it — flipping only one crashes debug builds):

```dart
androidNotificationOngoing: false,
androidStopForegroundOnPause: false,
```

Effect: service stays a `mediaPlayback` foreground service through the whole call → not an OOM target, notification stays live, just_audio's in-memory `_playInterrupted` survives → built-in auto-resume after the call works. No AndroidManifest change needed (`foregroundServiceType="mediaPlayback"` already declared).

**B2. Wakelock patch** in vendored `third_party/audio_service/android/src/main/java/com/ryanheise/audioservice/AudioService.java:715-719` — without it the PARTIAL_WAKE_LOCK acquired in `enterPlayingState()` stays held forever while paused:

```java
private void exitPlayingState() {
    if (config.androidStopForegroundOnPause) {
        exitForegroundState();
    } else {
        releaseWakeLock();
    }
}
```

`enterPlayingState()` re-acquires on resume — symmetric and safe.

**User-visible tradeoff (accepted):** while *paused* on Android ≤ 13 the notification can't be swiped away (foreground pinning); Android 14+ allows swiping media notifications anyway. While playing, no change. "Stop playback on swipe away" setting still clears everything.

## Out of scope

- No auto-restart of playback after actual process death (not feasible on modern Android; goals A+B are the fix).
- **Do not touch:** lib/ui/player/player_controller.dart (restore path correct), lib/main.dart (lifecycle saves stay as belt-and-suspenders), any Listen Together code (in-progress on this branch).

## Tests

Convention: `MyAudioHandler` can't be instantiated in `flutter test` (real `AudioPlayer` platform channels), so handler behavior is pinned by **source-inspection tests** (see `_caseBlock`/`_methodBlock` helpers in [test/audio_handler_source_swap_test.dart](test/audio_handler_source_swap_test.dart)); repositories are tested behaviorally against temp-dir Hive (pattern: test/song_cache_repository_test.dart).

1. **New `test/playback_session_persistence_test.dart`** (source-inspection): `_init` calls `_listenForSessionPersistence()`; the listener body contains the mediaItem `distinct`, `playingStream`, `queue.listen` hooks and the `_sourceSwitchInProgress`/`isSongLoading` guard; `_scheduleSessionSave` contains the `currentIndex is! int` + `_suppressSessionSave` guards and the debounce; the playByIndex case sets `_suppressSessionSave = true` and clears it in a `finally`; the periodic saver contains `Duration(seconds: 30)` and `savePosition(`; `initAudioService` contains both `false` config flags (pins the assert coupling).
2. **New `test/playback_session_repository_test.dart`** (behavioral): temp-dir Hive; `saveSession` round-trips queue/index/position; `savePosition` updates index/position **without clobbering the stored queue**; `getIndex`/`getPosition` null on empty box.
3. Run via `harmony-flutter-dart` MCP (`timeout_ms: 600000`): `flutter analyze --no-pub` and `flutter test` (full suite — the existing source-swap test must still pass after the playByIndex edits).

## Manual on-device verification (done by Jan — I never run the app or adb)

Precondition: "Restore playback session" setting ON; cold rebuild before testing (per usual workflow).

1. **Wrong-song fix:** queue 5+ songs, background the app during song 1, let it auto-advance to song 3, force-stop the app (system settings or swipe with stop-on-swipe OFF), reopen → must restore **song 3**, position within ~30 s.
2. **Call resume:** play a song, receive a real call → playback pauses on ring, **auto-resumes** when the call ends; notification never goes stale.
3. **Kill during call:** play song 3, receive a call, kill the process during the call, end call, reopen → song 3 at pre-call position (auto-resume after real process death is *not* expected — by design).
4. **Notification tradeoff:** pause → on Android ≤ 13 notification stays until playback stops / app swiped away (with stop-on-swipe ON).
5. **Restore no-clobber:** restore a session, do NOT press play, kill, reopen → same song + position again (not 0).
6. **Regression sweep:** skip/shuffle/reorder/play-next/clear-queue then kill + reopen; Windows desktop smoke (tray quit still saves).

## Risks

- Hive writes: debounced (≤1 per 800 ms, only on real changes); periodic saves are two int puts / 30 s — negligible.
- Restore race: covered by `_suppressSessionSave` (with `finally`) + `is! int` guard; restore reads Hive *before* playByIndex runs.
- Sub-second window between index change and debounced save: a kill there restores the previous song — strictly better than today.
- Vendored-package edits (`AudioService.java`) must be re-applied if audio_service is ever re-vendored; add a brief note in the plan doc saved to `plans/`.
