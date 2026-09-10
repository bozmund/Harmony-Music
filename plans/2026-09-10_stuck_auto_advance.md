# Stop a stuck song-to-song advance from killing auto-advance for good

**Devices:** Android

## Context

Issue #82: a song played to its last millisecond, then the player sat in `completed` and the next of
fifty queued tracks never started. `_handlePlaybackCompleted` holds `_completionInProgress` while it
awaits the whole advance to the next song, and that advance had no bound. Every recovery path - the
completion watchdog, the end-position fallback, the stall watchdog - stands down while the latch is
up, so one advance that never settled stopped auto-advance permanently.

The advance is now bounded at 75s. After that the latch is released and the completion watchdog
retries; playByIndex's generation check makes the stale attempt stand down if it ever wakes.
Diagnostics gain `completionStartedAt`.

The stuck state cannot be triggered on demand. What this changes is that, if it happens, playback
resumes within about 75 seconds instead of never. The checks below confirm nothing around it broke.

## Manual verification

- Let a song finish on its own: the next one in the queue starts, with no stuck spinner and no silence.
- At the end of the queue with queue loop on, the last song finishing wraps round to the first.
- With repeat-one on, a finishing song restarts once, cleanly, without replaying its first second.
- Skip next and previous by hand a few times: each moves one track and starts playing.
- Open the diagnostics dump while a song plays: `completionStartedAt` is present and `null`.
