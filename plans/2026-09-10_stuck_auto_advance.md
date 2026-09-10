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
completion watchdog retries. The stuck state cannot be triggered on demand, so the last check covers
what to do if it shows up.

## Manual verification

- Tap a not-downloaded song a few places down the queue: the spinner stays until you hear it.
- Press next several times quickly, then lock the phone: the lock-screen controls stay.
- Drag a song near its end and let it finish: the next one starts.
- If a song ends and nothing plays, wait 90 seconds: it should continue by itself. Send a report either way.
