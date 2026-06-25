# Release Candidate Manual Testing: Core Playback

Use this checklist before cutting a release candidate. The focus is normal playback stability for online and offline music, including queue behavior, transport controls, repeat/shuffle, background playback, and the selectable Classic/Preloaded playback modes.

## Release Candidate Pass Criteria

The release candidate is acceptable only if all critical playback paths meet these criteria:

- Playback starts reliably from song, playlist, album, artist, and downloaded-library sources.
- Online and offline playback work in Classic mode.
- Preloaded mode does not break normal playback when enabled.
- Next, previous, pause, resume, seek, repeat-one, queue loop, and shuffle behave consistently.
- Downloaded local files play offline without network access.
- Missing local files fail gracefully or fall back online when possible.
- Background and notification controls stay synchronized with the app UI.
- No stuck spinner, silent playback, wrong-track playback, overlapping audio, premature track cut-off, or app crash occurs.

## Test Matrix

Run at least the critical scenarios across this matrix:

| Scenario | Classic Online | Classic Offline | Preloaded Online | Preloaded Offline |
| --- | --- | --- | --- | --- |
| Single song playback | Required | Required | Required | Required |
| Playlist playback | Required | Required | Required | Required |
| Album playback | Required | Required | Required | Required |
| Artist/library playback | Required | Required | Required | Required |
| Next/previous | Required | Required | Required | Required |
| Pause/resume | Required | Required | Required | Required |
| Seeking | Required | Required | Required | Required |
| Repeat-one | Required | Required | Required | Required |
| Queue loop | Required | Required | Required | Required |
| Shuffle | Required | Required | Required | Required |
| Background/notification controls | Required | Required | Required | Required |
| Missing local file handling | Required | Required | Required | Required |

## Test Data Setup

Prepare this content before testing:

- One online-only song that is not downloaded.
- One downloaded/offline song.
- One playlist with exactly 1 track.
- One playlist with exactly 2 tracks.
- One playlist with 10+ tracks.
- One album with multiple tracks.
- One artist page with multiple songs.
- One downloaded playlist or local library list with multiple songs.
- One intentionally broken downloaded song where the local file has been deleted or moved.
- At least one long song, preferably over 5 minutes.
- At least one short song, preferably under 90 seconds.

Recommended device states:

- Fresh app launch.
- App already running in foreground.
- App in background.
- Screen locked.
- Online network available.
- Airplane mode/offline.
- Weak/intermittent network if possible.

## Playback Mode Setup

### Classic Mode

1. Open Settings.
2. Set Playback mode to `Classic`.
3. Confirm the preload range control is hidden or disabled.
4. Restart playback from a fresh song.

Expected:

- Playback uses the stable one-song source flow.
- No preload log errors are required for normal operation.
- Online and offline playback behave like the existing stable player.

### Preloaded Mode

1. Open Settings.
2. Set Playback mode to `Preloaded`.
3. Set preload range to `1` first.
4. Repeat selected tests with preload range `2` or higher if time allows.

Expected:

- Normal playback still works.
- Preload only applies to network HTTP/HTTPS sources.
- Downloaded local files are skipped by preload without log spam or crashes.
- No wrong song starts because of stale preloaded data.

## A. Online Playback Start

### A1. Start From Search or Song List

Steps:

1. Ensure device is online.
2. Search for a song that is not downloaded.
3. Tap the song.
4. Wait for playback to start.

Expected:

- Correct selected song starts.
- Play button does not spin forever.
- Progress starts near `0:00`.
- Title, artist, artwork, duration, and current queue highlight match the selected song.
- No previous song continues playing underneath.

### A2. Start From Playlist

Steps:

1. Open a playlist with 10+ online songs.
2. Tap a middle song.
3. Open the queue/up-next view.

Expected:

- The tapped middle song starts, not the first song unless the first was tapped.
- Queue contains the playlist items in the expected order.
- Next/previous are relative to the tapped song.
- Pressing next does not restart the same song.

### A3. Start From Album

Steps:

1. Open an album.
2. Tap the album play button.
3. Stop and then tap an individual album track.

Expected:

- Album play button starts the first album track.
- Individual track tap starts that exact track.
- Next/previous follow album order.
- Metadata and artwork update correctly.

### A4. Start From Artist

Steps:

1. Open an artist page.
2. Start playback from the artist songs list.
3. Start playback from an artist album if available.

Expected:

- Correct source queue is created.
- Current track is highlighted correctly.
- Next/previous remain within the expected artist or album queue.

## B. Offline and Downloaded Playback

### B1. Offline Single Downloaded Song

Steps:

1. Download a song.
2. Enable airplane mode.
3. Open the downloaded song from Library/Downloads.
4. Start playback.

Expected:

- Downloaded song starts without network.
- No stream lookup blocks local playback.
- Seeking, pause, and resume work.
- No preload error tries to HTTP-fetch a local `/data/...` or `file://...` path.

### B2. Offline Downloaded Queue

Steps:

1. Prepare a downloaded playlist or multi-song downloaded list.
2. Enable airplane mode.
3. Start the first downloaded song.
4. Press next through at least 3 songs.
5. Press previous.

Expected:

- Each downloaded song starts from local storage.
- Next/previous update metadata and artwork.
- No wrong queue index appears.
- No stuck loading spinner.

### B3. Offline Downloaded Album

Steps:

1. Download multiple songs from the same album, or use a local album-like list.
2. Enable airplane mode.
3. Start album playback.
4. Let one transition happen naturally.

Expected:

- Ordered playback works offline.
- Track transition does not require network.
- Duration/progress remain correct.

### B4. App Restart While Offline

Steps:

1. Start downloaded playback while online.
2. Pause playback.
3. Enable airplane mode.
4. Kill and reopen the app.
5. Resume or start a downloaded song.

Expected:

- App opens without requiring network for local playback.
- Downloaded content remains playable.
- Restore-session behavior, if enabled, does not get stuck on unavailable online sources.

## C. Transport Controls

### C1. Pause and Resume

Test from:

- Main player.
- Mini player.
- Gesture player, if enabled.
- Notification controls.
- Lock screen controls.

Steps:

1. Start playback.
2. Pause.
3. Wait 3 seconds.
4. Resume.

Expected:

- Audio pauses immediately.
- Resume continues from the same position.
- UI and notification play/pause states match actual audio.
- No duplicate audio starts.

### C2. Next

Steps:

1. Start a multi-song online queue.
2. Press next during normal playback.
3. Press next while paused.
4. Press next repeatedly 5 times.
5. Repeat in offline downloaded queue.

Expected:

- Correct next queue item plays.
- Old song does not restart.
- Button does not spin forever.
- Metadata, artwork, queue index, and notification update.
- Rapid presses do not crash or wedge playback.

### C3. Previous

Steps:

1. Start a multi-song queue.
2. Press previous within the first 5 seconds of a track.
3. Press previous after more than 5 seconds of playback.
4. Press previous repeatedly at the start of the queue.

Expected:

- App follows its expected rule: restart current track after several seconds, otherwise move to previous track.
- No invalid queue index.
- No crash at queue boundaries.

### C4. Seek

Steps:

1. Start an online song.
2. Seek forward.
3. Seek backward.
4. Seek near the end and let the song finish.
5. Seek while paused, then resume.
6. Repeat with a downloaded song offline.

Expected:

- Playback resumes from the requested position.
- Seeking near the end does not prematurely crash or skip incorrectly.
- Progress UI catches up quickly.
- No silent playback state.

## D. Repeat and Queue Loop

### D1. Repeat Off Natural Completion

Steps:

1. Disable repeat-one.
2. Disable queue loop if available.
3. Play the final song in a queue.
4. Let it finish naturally.

Expected:

- Playback reaches completion without cutting off early.
- App either pauses/stops at the end or follows the designed final-track behavior.
- No crash.

### D2. Repeat-One Online

Steps:

1. Start an online song.
2. Enable repeat-one.
3. Let the song finish naturally.
4. Repeat by seeking to 5 seconds before the end and waiting.
5. Press next while repeat-one is still enabled.

Expected:

- Song plays to the true end; it does not stop 1 second early.
- Same song repeats using native loop behavior.
- No crash or stuck spinner.
- Manual next behavior follows app rules and does not corrupt queue state.

### D3. Repeat-One Offline

Steps:

1. Start a downloaded song offline.
2. Enable repeat-one.
3. Let the song finish naturally twice.
4. Seek near the end and wait.

Expected:

- Local file loops cleanly.
- No network call is required.
- No preload errors occur for local file paths.

### D4. Queue Loop

Steps:

1. Enable queue loop/repeat-all.
2. Start the final track in a multi-song queue.
3. Let it finish naturally.
4. Press next on the final track.
5. Press previous on the first track.

Expected:

- Final track advances to first track.
- First track previous behavior matches the queue-loop design.
- Queue order remains stable unless shuffle is enabled.

## E. Shuffle

### E1. Shuffle Before Playback

Steps:

1. Enable shuffle.
2. Start a playlist with 10+ songs.
3. Press next several times.

Expected:

- Current selected song is respected.
- Upcoming tracks follow shuffled order.
- No duplicate repeats before the shuffled set is exhausted, unless expected by design.

### E2. Shuffle During Playback

Steps:

1. Start ordered playlist playback.
2. Enable shuffle while playing.
3. Press next and previous multiple times.
4. Disable shuffle.

Expected:

- Current track remains stable when shuffle toggles.
- Next follows shuffled order while enabled.
- Disabling shuffle restores expected ordered behavior from current context.

### E3. Shuffle With Repeat-One

Steps:

1. Enable shuffle.
2. Enable repeat-one.
3. Let current song finish.
4. Press next.

Expected:

- Natural completion repeats the current song.
- Manual next moves according to app rules.
- Shuffle queue is not corrupted.

## F. Queue Operations

### F1. Enqueue Song

Steps:

1. Start a queue.
2. Use song action to enqueue a different song.
3. Open queue.

Expected:

- New song appears at the end or expected queue location.
- Current song continues uninterrupted.

### F2. Play Next

Steps:

1. Start a multi-song queue.
2. Use Play Next on a song not currently playing.
3. Press next.

Expected:

- Selected song plays next.
- Existing queue order remains otherwise intact.

### F3. Remove From Queue

Steps:

1. Start a queue with 5+ songs.
2. Remove an upcoming song.
3. Remove a previous song.
4. Remove current song if UI supports it.

Expected:

- Queue index stays valid.
- Current playback continues or transitions according to app rules.
- No crash.

### F4. Reorder Queue

Steps:

1. Start a queue with 5+ songs.
2. Reorder upcoming songs.
3. Press next multiple times.

Expected:

- Playback follows the reordered queue.
- Current track remains stable during reorder.

### F5. Single-Track Queue

Steps:

1. Play a one-song playlist.
2. Press next.
3. Press previous.
4. Toggle repeat-one and queue loop.

Expected:

- App handles one-item boundaries without crashing.
- Repeat-one loops the same track.
- Queue loop behavior is clear and stable.

## G. Missing Local File Handling

### G1. Missing Local File While Online

Steps:

1. Download a song.
2. Delete or move its local file outside the app.
3. Keep network online.
4. Try to play the song.

Expected:

- App detects missing local file.
- App falls back to online streaming if available.
- UI does not get stuck in loading.
- Error message is shown if fallback fails.

### G2. Missing Local File While Offline

Steps:

1. Download a song.
2. Delete or move its local file.
3. Enable airplane mode.
4. Try to play the song.

Expected:

- App fails gracefully.
- No crash.
- Playback state does not remain incorrectly playing.
- User can still play other downloaded songs afterward.

### G3. Missing Local File in Middle of Queue

Steps:

1. Create a downloaded queue with at least 3 songs.
2. Delete the local file for the second song.
3. Start the first song.
4. Press next or let transition happen.

Expected:

- Missing file is handled gracefully.
- Queue index and UI remain consistent.
- Third song remains playable after the failure.

## H. Background and Notification Controls

### H1. Background Playback

Steps:

1. Start playback.
2. Send app to background.
3. Wait 30 seconds.
4. Return to app.

Expected:

- Audio continues unless background playback is disabled by settings.
- UI syncs to actual playback state on return.
- Progress is accurate.

### H2. Notification Controls

Steps:

1. Start playback.
2. Use notification controls for play, pause, next, and previous.
3. Reopen app.

Expected:

- Controls affect playback immediately.
- App UI reflects notification actions.
- Metadata and artwork are correct.

### H3. Lock Screen Controls

Steps:

1. Start playback.
2. Lock device.
3. Use lock-screen controls for pause/resume/next/previous.
4. Unlock device.

Expected:

- Lock-screen controls work.
- App state matches actual playback after unlock.
- No duplicate commands are processed.

### H4. Background Network Changes

Steps:

1. Start online playback.
2. Send app to background.
3. Disable network.
4. Return to app and press next.

Expected:

- Current buffered playback behaves reasonably.
- Next either loads if possible or fails gracefully.
- App does not crash or stay in permanent loading.

## I. Classic vs Preloaded Mode Regression

### I1. Switching Modes

Steps:

1. Start playback in Classic mode.
2. Switch to Preloaded mode.
3. Start a new online playlist.
4. Switch back to Classic mode.
5. Start another online playlist.

Expected:

- Mode changes apply without app restart.
- Playback remains stable after each mode change.
- Classic mode clears/ignores preload state.

### I2. Preloaded Online Queue

Steps:

1. Enable Preloaded mode with range `1`.
2. Start an online playlist.
3. Wait at least 15 seconds.
4. Press next.
5. Let one natural transition occur.

Expected:

- Correct next song plays.
- No wrong preloaded track starts.
- No stale metadata/artwork.
- No overlapping audio.

### I3. Preloaded Offline Queue

Steps:

1. Enable Preloaded mode.
2. Enable airplane mode.
3. Start downloaded queue playback.
4. Press next several times.

Expected:

- Downloaded songs play normally.
- Preload skips local paths.
- Console does not spam `No host specified in URI` for local files.

### I4. Preloaded Repeat-One

Steps:

1. Enable Preloaded mode.
2. Start online playback.
3. Enable repeat-one.
4. Let song finish naturally.

Expected:

- Song repeats cleanly.
- It does not stop early.
- Preload does not interfere with repeat-one.

## J. Connectivity Transitions

### J1. Online to Offline During Stream

Steps:

1. Start online streaming playback.
2. Disable network mid-song.
3. Wait for buffering behavior.
4. Try seek and next.

Expected:

- App handles buffering/failure gracefully.
- No crash.
- Error state is recoverable.

### J2. Offline to Online

Steps:

1. Start downloaded playback offline.
2. Re-enable network.
3. Play an online-only song.

Expected:

- Online playback works again without app restart.
- Queue and metadata update correctly.

### J3. Weak Network

Steps:

1. Simulate weak or intermittent network if possible.
2. Start online playback.
3. Press next/previous.
4. Seek near the end.

Expected:

- Loading state is visible when needed.
- App does not enter permanent spinner state.
- User can recover by selecting another track.

## K. UI Synchronization

Check during all relevant scenarios:

- Main player shows correct play/pause state.
- Mini player shows correct song and progress.
- Queue current-track highlight is correct.
- Notification metadata matches app metadata.
- Artwork changes when track changes.
- Duration is eventually correct.
- Progress does not jump backward unexpectedly except when repeat-one restarts.
- Favorite/lyrics/recent-played side effects do not block playback.

## L. Failure Signals to Treat as Release Blockers

Block the release candidate if any of these occur:

- Playback starts the wrong song.
- Next restarts the same song when a next track exists.
- Online repeat-one stops before the end or crashes.
- Play button spinner never stops after selecting a playable song.
- Old song keeps playing after selecting a new song.
- Two songs play at the same time.
- Offline downloaded song requires network to play.
- Local file preload logs `No host specified in URI` repeatedly.
- Notification controls desynchronize from the app UI.
- Queue index becomes invalid or crashes at boundaries.
- App crashes during normal transport controls.

## M. Suggested Smoke Pass Before Every Build Upload

If there is limited time, run this minimum smoke pass:

1. Classic mode, online playlist: play middle song, next, previous, seek, pause/resume.
2. Classic mode, online repeat-one: let song finish naturally.
3. Classic mode, offline downloaded queue: play, next twice, seek, pause/resume.
4. Preloaded mode, online playlist: play, wait 15 seconds, next, natural transition.
5. Preloaded mode, offline downloaded queue: play and next twice; verify no local-path preload errors.
6. Background: start playback, lock screen, pause/resume/next from notification.
7. Missing local file online: verify fallback or clear failure.
8. Missing local file offline: verify graceful error and recovery.

