# Spinner vanishes on network songs; next song sometimes never starts (#82)

**Devices:** Android

## Context

Two playback fixes on this branch.

**Spinner.** Tapping a song that had to be fetched from the network showed the spinner for 87ms,
then the button said "playing" through five seconds of silence. During a playing source switch the
handler reports ready + playing on purpose, so Android keeps the lock-screen card instead of
flashing a connecting state on every track change; the player controller read that as the new song
having started. The media session is left exactly as it was. `isSongLoading` in the handler is now
a setter that broadcasts a `sourceLoading` event, and the controller refuses to end the spinner
while the handler says it is still loading.

**Stuck advance (#82).** A song played to its last millisecond, then the player sat in `completed`
and the next of fifty queued tracks never started. `_handlePlaybackCompleted` holds
`_completionInProgress` while it awaits the whole advance, which had no bound, and every recovery
path stands down while that latch is up. The advance is now bounded at 75s, after which the
completion watchdog retries. The stuck state cannot be triggered on demand, so Test 4 covers what to
do if it shows up.

## Manual verification

- What this build fixes: tapping a song that has to be downloaded showed the spinner for a split second, then pause over silence. Also, a song could end and the next one never start (#82).
- Setup: queue 4-5 online songs you have NOT downloaded, so each one has to be fetched. Queue loop on, repeat-one off.
- Test 1, spinner: while a song plays, tap a different not-downloaded song. PASS: the spinner stays until you actually hear the new song. FAIL: it vanishes at once and the button shows pause over silence.
- Test 2, quick skips: press next 4-5 times fast, then lock the phone. PASS: the lock-screen controls stay and the last song plays. FAIL: the controls disappear or flicker to a connecting state.
- Test 3, song end: drag a song to its last ~10 seconds and let it finish. PASS: the next song starts within a few seconds; after the last one it wraps to the first. FAIL: silence at the end.
- Test 4, if a song ends and nothing plays: wait 90 seconds without touching anything. PASS: the next song starts by itself. Either way, send a bug report - it now carries the log.
