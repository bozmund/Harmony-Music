# Next song never starts after one ends (#82)

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

The stuck state cannot be triggered on demand. Tests 1-3 confirm normal song changes still work,
since this touches the code that runs every time a song ends. Test 4 is what to do if the bug does
show up.

## Manual verification

- What this fixes: sometimes a song ends and the next one never starts - the player sits silent at the end forever (#82). Now it recovers on its own within about 75 seconds.
- Setup: queue 4-5 online songs you have NOT downloaded, queue loop on, repeat-one off. To save time, drag each song to its last ~10 seconds instead of waiting it out.
- Test 1, normal change: let a song end by itself. PASS: within a few seconds the next song plays and title and artwork change. FAIL: silence, or the play button stays on a spinner.
- Test 2, end of queue: drag the LAST song near its end and let it finish. PASS: playback wraps to the first song in the queue. FAIL: it stops, or replays the same song.
- Test 3, repeat-one: turn repeat-one on and let a song end. PASS: the same song restarts from 0:00 once, first second not doubled. Turn repeat-one off after.
- Test 4, if it ever gets stuck: a song ends and nothing plays. Wait 90 seconds without touching anything. PASS: the next song starts by itself. Either way, send a bug report.
