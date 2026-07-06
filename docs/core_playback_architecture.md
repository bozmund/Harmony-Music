# Core Playback Architecture

This document explains the most important playback path in Harmony Music. It is
intended for engineers changing `MyAudioHandler`, `PlayerController`, queue
behavior, preloading, caching, or end-of-song handling.

Playback is deliberately centered around one owner:

- `MyAudioHandler` owns the real audio engine, active queue, active source,
  source resolution, completion behavior, and Audio Service state.
- `PlayerController` owns UI-facing state, progress display, lyrics, favorite
  side effects, queue panel behavior, and app navigation side effects.
- Repositories own persisted data such as settings, session restore, cached
  stream metadata, downloads, library, and playlists.

The core rule is simple: `MyAudioHandler` is the source of truth for actual
playback. UI code should observe it and request commands, not infer playback
state independently.

## Main Components

### `MyAudioHandler`

`MyAudioHandler` extends `BaseAudioHandler` and wraps a `just_audio`
`AudioPlayer`.

It is responsible for:

- Creating and configuring the `AudioPlayer`.
- Publishing `AudioService.playbackState`, `mediaItem`, `queue`, and custom
  events.
- Resolving stream data through cache/download/network services.
- Creating the correct `AudioSource` for online, cached, downloaded, and
  preloaded-prefix playback.
- Managing `currentIndex`, queue loop, repeat-one, shuffle, and queue mutation.
- Handling source swaps and natural end-of-song advancement.
- Recording crash/playback diagnostics.
- Saving playback sessions.

Only the handler should call `_player.play()`, `_player.pause()`,
`_player.stop()`, `_player.seek()`, `_playList.add()`, or `_playList.clear()`
for the active player.

### `PlayerController`

`PlayerController` listens to `AudioHandler` streams and translates them into
UI state.

It is responsible for:

- `buttonState`
- visible `currentSong`
- visible queue and queue display order
- current/buffered/total progress
- lyrics state
- favorite status
- radio continuation
- sleep timer
- player panel behavior
- desktop volume/equalizer calls
- playback debug snapshots

It should send commands through `AudioHandler` or `PlaybackCommandService`.
It should not mutate the real audio source directly.

### `PlaybackCommandService`

This service is the command facade used by controllers. It keeps UI code from
knowing every custom action name on the handler. Prefer adding command methods
here when a UI feature needs a new playback command.

### `PlaybackPreloadService`

This service manages Android-only preloaded-prefix behavior. It never owns the
active queue or active song. It only prepares nearby stream data and temporary
prefix files that `MyAudioHandler` may consume when building the active source.

See `docs/player_preloading.md` for the detailed preload subsystem.

## Startup And Initialization

`initAudioService(...)` creates `MyAudioHandler` with explicit repository
dependencies and then registers it with `AudioService.init(...)`.

`MyAudioHandler._init()` performs playback setup:

1. Creates the temporary cache directory.
2. Creates and initializes `PlaybackPreloadService`.
3. Sets an empty `ConcatenatingAudioSource` on the player.
4. Registers playback listeners:
   - playback event stream
   - processing state stream
   - final-position fallback stream
   - sequence state stream
   - duration stream
   - Android audio session ID stream where applicable
5. Restores persisted settings:
   - skip silence
   - repeat-one
   - shuffle
   - queue loop
   - loudness normalization

The active player uses a one-song playlist. Even when the queue contains many
songs, `_playList` normally contains exactly one active source. Queue movement
is implemented by swapping this one active source, not by loading the whole
queue into `just_audio`.

## Queue Model

The queue is exposed through `AudioHandler.queue`. The current item is tracked
with `currentIndex`.

Important queue fields:

- `queue.value`: full logical playback queue.
- `currentIndex`: index into `queue.value`.
- `mediaItem.value`: currently visible/active item.
- `_queueBeforeShuffle`: copy of the queue before visible shuffle, used to
  restore order when shuffle is disabled.

### Queue Loop

Queue loop is controlled by `queueLoopModeEnabled`.

`_getNextSongIndex()` returns:

- `currentIndex + 1` when there is a next item.
- `0` when current item is the last item and queue loop is enabled.
- `currentIndex` when current item is the last item and queue loop is disabled.

`skipToNext()` uses that result:

- If the index changes, it calls `customAction("playByIndex", {"index": index})`.
- If the index does not change but queue loop is enabled, it restarts the
  current item.
- If the index does not change and queue loop is disabled, it seeks to zero and
  pauses.

This means natural completion and manual next share the same queue advancement
rules.

### Previous

`skipToPrevious()` behaves like a normal music player:

- If position is over five seconds, it seeks to the start of the current song.
- Otherwise it moves to the previous queue item if one exists.
- If there is no previous item, it seeks to zero.

### Shuffle

Shuffle mutates the visible queue order while keeping the current item at the
front of the shuffled order. The original order is kept in `_queueBeforeShuffle`
so disabling shuffle can restore it.

When changing shuffle behavior, keep these invariants:

- The current media item must remain visible as the active song.
- `currentIndex` must point to that item after mutation.
- `queue.add(...)` and `mediaItem.add(...)` must stay consistent.
- Preload windows must be rescheduled after queue order changes.

## Starting Playback

There are two main source-start commands.

### `playByIndex`

Used when selecting a song inside an existing queue.

Flow:

1. Read target `songIndex` from extras.
2. Set `currentIndex`.
3. Capture whether there is an existing source.
4. Increment `_playbackGeneration`.
5. Reset any prepared next source.
6. If a source already exists, mark source switch in progress.
7. Set `isSongLoading = true`.
8. Publish the selected `mediaItem` immediately.
9. Publish a loading playback state with current/buffered position reset to
   zero.
10. Resolve stream info.
11. Stop and clear the old one-song source.
12. Ignore stale work if a newer request changed `_playbackGeneration`.
13. Retry with a fresh URL if stream info is not playable.
14. Save the selected URL into `currentSongUrl` and the media item extras.
15. Add the new `AudioSource`.
16. Apply loudness normalization when enabled and supported.
17. Load the source, seek to zero, and request playback, or restore session
    position.
18. Set `isSongLoading = false`.
19. Emit a ready/playing snapshot.
20. End source switch after a short deferred window.
21. Schedule preload for nearby songs.

The early `mediaItem.add(currentSong)` is intentional. It lets the UI update
title, artwork, queue highlight, and lyrics immediately while source resolution
continues.

### `setSourceNPlay`

Used when starting a standalone song or replacing the queue with one item.

It follows the same source resolution and source-swap rules as `playByIndex`,
but it sets:

- `currentIndex = 0`
- `queue = [currMed]`

## Source Resolution

The handler resolves source information in this order:

1. Prepared preloaded stream info, when applicable.
2. Downloaded/offline stream info.
3. Cached song stream info.
4. Existing local URL in `MediaItem.extras["url"]`.
5. Network stream lookup via `checkNGetUrl(...)`.

The goal is to avoid network work when a local source is already available.

### Downloaded And Cached Sources

Downloaded and cached songs can produce local `file://...` URLs. These should
not be sent through preload or network-only assumptions.

When local metadata is incomplete, the handler builds a minimal playable audio
record with conservative defaults. This keeps offline playback from failing just
because stream metadata is missing.

### Online Sources

Online source URLs are resolved through stream services and cached metadata.
If initial stream info is not playable, playback retries once with
`generateNewUrl: true`.

If retry also fails:

- `currentSongUrl` is cleared.
- `isSongLoading` is set false.
- preload is rescheduled/cleared as appropriate.
- a `playError` custom event is emitted.
- playback state moves to `AudioProcessingState.error`.

The app does not auto-skip failed songs. That preserves user intent and makes
errors visible.

## Audio Source Creation

`_createAudioSource(MediaItem mediaItem)` chooses the active source:

1. If a preloaded prefix source is available, use it.
2. If cache mode applies, use `LockCachingAudioSource`.
3. Otherwise use `AudioSource.uri`.

`isPlayingUsingLockCachingSource` records whether the active source uses locked
caching. Some network recovery behavior depends on this flag.

Never expose raw signed playback URLs in diagnostics or UI. Diagnostics should
show URL shape only, such as scheme, host, path length, and query parameter
count.

## Playback State Publishing

The app publishes two related but different states:

- `just_audio` state: the real `_player` state.
- `AudioService.playbackState`: the public state consumed by UI,
  notifications, background controls, and platform integrations.

`_notifyAudioHandlerAboutPlaybackEvents()` listens to
`_player.playbackEventStream` and publishes:

- controls
- compact Android notification controls
- processing state
- repeat mode
- shuffle mode
- playing flag
- position
- buffered position
- speed
- queue index

Source switching has special handling. While swapping sources, the public
`playing` flag can remain true if the previous source was playing, so Android
controls keep their pause action. The processing state must still be
`loading` while `isSongLoading` is true, and public current/buffered position
must stay at zero until the new source starts. After `AudioPlayer.load()` and
the start seek complete, the handler requests playback through
`_startPlayerPlayback()`, clears `isSongLoading`, and emits the ready/playing
source-start snapshot. Do not `await _player.play()` in source-start paths:
that future can remain pending while the song is playing, which would leave the
UI stuck in loading even though audio has already started.

The UI mirrors this with a song-id handoff marker in `PlayerController`.
When a new media item arrives, `_pendingPlaybackStartSongId` is set, progress is
reset to zero, and the play button shows loading. Stale position and buffered
ticks are ignored until the handler reports ready/playing near the start of the
same song. This prevents old end-of-song progress from twitching into the new
song and prevents the loading spinner from getting stuck after the real source
start event arrives.

Use `_emitPlaybackSnapshot(...)` when code needs to publish an immediate
explicit state, such as pause, stop, successful source start, or source failure.

## End-Of-Song Completion

Natural completion is the most sensitive part of playback. It must satisfy
three competing goals:

- Advance when the song really ends.
- Never get stuck if `just_audio` misses or delays a terminal event.
- Never skip early because decoder duration is shorter than media metadata.

The handler uses multiple completion signals.

### Primary Completion Signals

1. `playbackEventStream`
   - If `event.processingState == ProcessingState.completed`, schedule
     completion handling.

2. `processingStateStream`
   - If state is `ProcessingState.completed`, schedule completion handling.

3. Position fallback stream
   - A position stream checks whether playback reached the expected end.
   - It also prepares the next source near the end.

4. Completion watchdog
   - A periodic fallback runs while playback is expected to be active.
   - It catches cases where the real player is completed but public state is
     stale at ready/playing.

### Completion Scheduling

All completion signals call `_scheduleCompletionHandling(...)` rather than
calling `_handlePlaybackCompleted(...)` directly.

Scheduling is deferred with `scheduleMicrotask(...)` to avoid doing source swaps
inside synchronous player stream callbacks.

Guards:

- `_completionHandlingScheduled` prevents duplicate queued work.
- `_completionInProgress` prevents concurrent handling.
- `_completionHandlingAllowEndPosition` preserves whether a fallback was allowed
  to use end-position logic.

### Completion Handling

`_handlePlaybackCompleted(...)` returns without action if:

- completion is already in progress, or
- the player is not completed and the caller did not explicitly allow
  end-position fallback, or
- the caller allowed end-position fallback but `_isAtEndPosition()` is false.

If `isSongLoading` is true, completion is retried shortly. This avoids advancing
while a source swap is halfway through.

Once handling starts:

- If repeat-one is enabled, `_repeatCurrentSongFromStart()` restarts the current
  one-song source.
- Otherwise, `skipToNext()` applies normal queue rules.

### Completion Watchdog

The watchdog exists because a real-world failure showed this state:

```json
{
  "audioHandler": {
    "processingState": "ready",
    "playing": true
  },
  "audioHandlerInternal": {
    "playerProcessingState": "completed",
    "playerPlaying": true,
    "isAtEndPosition": true
  }
}
```

In that state, public Audio Service state is stale, the UI can keep counting
past the song duration, and normal stream listeners may not advance the queue.

The watchdog:

- starts when playback starts or a playback event reports `playing = true`
- stops on pause, stop, and dispose
- runs every 250 ms
- does nothing while loading, source switching, or already handling completion
- schedules normal completion when safe

It does not replace the normal completion listeners. It only catches missed
terminal events.

### Early Completion Deferral

Some sources report a decoded/player duration shorter than the media item
duration. For example, a media item may be `3:12`, while `_player.duration` is
around `3:11`.

If the watchdog immediately trusts `ProcessingState.completed`, the app can
advance early. To prevent that, watchdog completion uses
`_shouldHonorCompletedStateNow()`.

That method:

1. Computes the expected end duration.
2. Uses the longer of `_player.duration` and `mediaItem.duration`.
3. If current position has reached that expected duration, completion is honored.
4. If the player completed early, records when the early completion was first
   detected.
5. Waits the remaining expected time plus `_fallbackCompletionGrace`.

`_fallbackCompletionGrace` exists because UI progress is displayed in seconds
and stream/timer ticks are coarse. Without a small grace, a song can visibly
switch while the UI still shows the previous second.

The deferral is reset when:

- watchdog stops
- source/prepared-next state is reset
- the player is no longer in early completed state

### Expected End Position

`_isAtEndPosition(...)` uses `_expectedEndDuration()`.

`_expectedEndDuration()` returns:

- `mediaItem.duration` if player duration is unknown
- `_player.duration` if media duration is unknown
- the longer of both when both exist

This is intentionally conservative. It is better to wait a little longer than
to cut off the end of a song.

## Pre-End Preparation

Near the end of a song, `_prepareNextSourceWhenNearEnd(...)` may start resolving
the next song's stream info before the current song completes.

Important constraints:

- It does not publish a new media item.
- It does not stop the current player.
- It does not add a new active source.
- It is invalidated by `_playbackGeneration`.
- It is invalidated if the expected next song no longer matches the queue.

When the next song is actually selected, `playByIndex` can consume prepared
stream info through `_takePreparedStreamInfoFor(...)`.

This reduces transition latency without changing the active playback source
early.

## Source Switching And Stale Request Protection

Source swaps are asynchronous. During stream resolution the user may tap another
song, press next, or change the queue. To prevent stale async work from
overwriting the latest intent, the handler uses `_playbackGeneration`.

Every new source-start request increments `_playbackGeneration`.

After each awaited stream-resolution step, the handler checks:

- request generation still matches `_playbackGeneration`
- requested index still equals `currentIndex`

If not, stale work exits without changing playback.

This is one of the most important safety rules in the player.

## Pause, Stop, And Dispose

### Pause

Pause:

- calls `_player.pause()`
- sets `isSongLoading = false`
- records diagnostics
- emits a non-loading, non-playing playback snapshot
- clears preload files
- stops the completion watchdog

### Stop

Stop:

- calls `_player.stop()`
- sets `isSongLoading = false`
- clears preload files
- stops the completion watchdog
- records diagnostics
- emits idle/non-playing state
- calls `super.stop()`

### Dispose

Dispose custom action:

- stops the completion watchdog
- clears preload files
- disposes the player
- calls `super.stop()`

Always cancel timers and async fallback mechanisms on stop/dispose paths.

## Session Save And Restore

The handler saves:

- queue
- current index
- current position
- current media item/session details as implemented by the playback session
  repository

Restore uses queue plus index plus position. On non-desktop platforms, restored
playback loads the source and seeks to the saved position without automatically
starting normal playback unless the restore path requests it.

When changing restore behavior, verify:

- restored media item matches queue index
- restored position does not trigger immediate false completion
- source switch flags are cleared
- playback snapshot is non-loading after restore

## Diagnostics

The app has a selectable playback debug snapshot in the song info dialog when
opened from the player.

The snapshot includes:

- UI/controller state
- public Audio Handler state
- internal handler/player state
- current queue length and index
- player processing state
- Audio Service processing state
- completion flags
- watchdog state
- early completion deferral state
- pending UI source-start state
- preload state
- source URL shape, without raw signed URL values

Use this snapshot when investigating:

- song stops at the end
- song skips early
- queue does not advance
- UI shows playing but no audio plays
- notification state differs from app state
- progress exceeds duration
- wrong song appears after rapid taps

Do not add raw auth tokens, cookies, visitor IDs, or signed stream URLs to this
debug output.

## Logging And Crash Diagnostics

The handler records important playback milestones through
`CrashDiagnosticsService`, including:

- source started
- pause
- stop
- completion
- source playback failure

These logs should identify song ID, current index, queue length, position, and
failure reason where useful. They should not include raw stream URLs or secrets.

## Testing Strategy

Playback behavior is protected mainly by source-level regression tests in
`test/audio_handler_source_swap_test.dart`.

Those tests intentionally assert that important code paths and invariants remain
present:

- one-song source flow
- source failure recovery
- non-loading playback snapshots after successful source starts
- repeat-one using native loop mode
- pause and stop emitting immediate non-playing snapshots
- shuffle queue restoration
- completion listeners and final-position fallback
- completion watchdog behavior
- early completed-state deferral
- pre-end source preparation without early switching
- source switch loading and notification stability
- player controller source-handoff loading/progress guards
- offline source resolution before network lookup
- stale playback request rejection
- Android buffer bounds
- artwork downscaling
- queue-end behavior
- incomplete downloaded metadata fallback

Manual playback coverage lives in
`docs/release_candidate_playback_manual_testing.md`.

When changing playback, run at minimum:

```powershell
.\.flutter\bin\flutter.bat test test/audio_handler_source_swap_test.dart
.\.flutter\bin\flutter.bat analyze
```

For changes that affect UI-visible state, also run focused widget/controller
tests that cover `PlayerController`, queue ordering, and song info diagnostics.

## Change Safety Rules

Use these rules when modifying playback:

1. Keep `MyAudioHandler` as the owner of the real player.
2. Keep `PlayerController` UI-facing and command-oriented.
3. Publish selected media immediately, but guard actual source swaps with
   `_playbackGeneration`.
4. Do not call source-swap code directly from synchronous player stream
   callbacks.
5. Preserve `_completionInProgress` and `_completionHandlingScheduled` guards.
6. Treat `_player.duration` as potentially shorter than `mediaItem.duration`.
7. Prefer waiting slightly longer over cutting off audio.
8. Never expose raw stream URLs in diagnostics.
9. Clear timers/watchdogs on pause, stop, and dispose.
10. Reschedule or clear preload windows after queue, shuffle, loop, or playback
    state changes.

## Common Failure Modes

### Public State Ready, Internal Player Completed

Symptom:

- UI says playing.
- Public Audio Handler state says ready.
- Internal player state says completed.
- Progress may exceed total duration.

Cause:

- Terminal event was missed or public state was stale.

Expected protection:

- Completion watchdog detects internal completed state.
- Early completion deferral prevents premature skip.
- Normal completion path advances through `skipToNext()`.

### Song Skips Before Visible End

Symptom:

- Song says `3:12`.
- Next song starts while UI shows `3:10` or `3:11`.

Cause:

- Decoder/player duration shorter than media metadata.
- Fallback completion trusted player completion too early.

Expected protection:

- `_expectedEndDuration()` chooses the longer duration.
- `_shouldHonorCompletedStateNow()` waits remaining time plus grace.

### Song Does Not Advance At End

Symptom:

- Song reaches end and stays stuck.
- Internal player may be completed.

Expected protection:

- playback event listener
- processing state listener
- position fallback
- completion watchdog

If all fail, inspect debug snapshot fields:

- `playerProcessingState`
- `processingState`
- `isAtEndPosition`
- `completionWatchdogActive`
- `completionInProgress`
- `completionHandlingScheduled`
- `isSongLoading`
- `sourceSwitchInProgress`
- `currentIndex`
- `queueLength`
- `queueLoopModeEnabled`

### Wrong Song Starts After Rapid Taps

Symptom:

- User taps song A, then song B.
- Song A starts after B was selected.

Expected protection:

- `_playbackGeneration`
- index checks after awaited stream resolution
- prepared-next source validation

### Local Download Tries Network Or Preload

Symptom:

- Downloaded song fails offline.
- Logs show network/preload errors for local path.

Expected protection:

- offline source lookup before network lookup
- local URL detection
- preload service skipping invalid local network assumptions

## Glossary

- **Audio Service state**: public playback state exposed to UI, notification,
  and background controls.
- **Player state**: actual `just_audio` internal state.
- **One-song source flow**: active `ConcatenatingAudioSource` contains only the
  current song source.
- **Queue loop**: when enabled, natural completion of the last queue item moves
  to index `0`.
- **Repeat-one**: native `just_audio` `LoopMode.one`; restarts current source.
- **Preloaded prefix**: temporary partial file used to start a network song
  faster.
- **Completion watchdog**: periodic fallback that detects missed end-of-song
  completion.
- **Early completion deferral**: logic that waits when player completion occurs
  before the media item's expected duration.
- **Playback generation**: monotonically increasing token that rejects stale
  async source resolution work.
