# Devices sheet: decide transfer vs sync on actual playback, not session ownership

## Context

Remote control works. But after stopping a song on Windows, the phone's "Play on device" sheet still
shows Windows as **"Playing here"**, so tapping it syncs instead of transferring the phone's queue.
The only way out today is to walk over to Windows and tap its own row to end the session — going to
the *destination* device to make it accept a transfer is backwards.

**Root cause.** The sheet decides using `CloudPlaybackDevice.isAudioTarget`, which the server derives
purely from the newest open `PlaybackSession`'s `TargetDeviceId`
(`Harmony-Cloud/src/Harmony.Cloud.Api/Program.cs:158`). A device that plays once claims the session
via `_claimSessionForLocalPlayback` and stays the target until the session is explicitly ended —
stopping or pausing does **not** end it. So `isAudioTarget` means *"owns the session"*, never *"is
playing right now"*, and the sheet has been reading it as the latter.

The receiver cannot fill the gap: `_applySession` bails at `if (!_isEngaged) return;`
(`lib/services/cloud/cloud_playback_receiver.dart:434`), so a phone that has not joined discards
every snapshot and never learns the target's playback state.

**Decision (confirmed):** tap joins only while the target is *actually playing audio*. Paused or
stopped means tap transfers. Trade-off accepted: grabbing a paused Windows as a remote now means
pressing play on Windows first.

## Approach

Client-only. **No Harmony-Cloud change and no deploy** — everything needed already exists:

- `GET /playback/session` is account-scoped, requires no engagement, and returns `Playing` plus
  `TargetDeviceId` (`Program.cs:261`)
- `CloudPlaybackSession` already models `playing` and `targetDeviceId`
  (`lib/services/cloud/harmony_cloud_client.dart:52`)
- `playbackSession()` already exists at `lib/services/cloud/cloud_sync_coordinator.dart:190`

### 1. Expose the session to the sheet

`lib/app/providers/auth_providers.dart` — add a `playbackSession()` accessor beside the existing
`playbackDevices()` (line 156), delegating to `_cloud.playbackSession()`. Mirrors the existing shape
exactly.

### 2. Fetch both, and decide from both

`lib/ui/widgets/cloud_devices_sheet.dart` — `_loadDevices` currently assigns a bare
`Future<List<CloudPlaybackDevice>>`. Fetch devices and session together with `Future.wait` into a
small private holder, and widen the `FutureBuilder` to match.

Derive one predicate and route every decision through it:

```dart
/// Whether this row is a device we can subscribe to *right now*.
///
/// isAudioTarget only means the device owns the session, which outlives the
/// playback that created it. Joining a device that stopped is not a thing;
/// transferring to it is.
bool _isPlayingTarget(CloudPlaybackDevice device, CloudPlaybackSession? session) =>
    device.isAudioTarget &&
    device.presence == 'online' &&
    session != null &&
    session.targetDeviceId == device.deviceId &&
    session.playing;
```

`presence == 'online'` is load-bearing: a killed app leaves `Playing` true on the session with no
socket behind it, and that must not read as joinable.

Replace the three current `device.isAudioTarget` uses with `_isPlayingTarget(...)`:

- **row tap** — playing target → `_join`, otherwise → `_handoff`
- **subtitle** — playing target → `"Playing here - Control this device"`, otherwise the normal
  `_presenceLabel(...)`, so an idle target reads like any other transfer destination
- **blue icon/title styling** — same predicate, so the colour stops claiming playback that ended

### 3. Handoff with nothing to hand off

`_handoff` returns early and silently when `currentSong.value == null`. Tapping an idle target now
routes here, so a phone with no queue would appear to do nothing. Show a snackbar instead — reuse the
existing `snackbar(...)` helper already imported in this file.

## Files

- `lib/ui/widgets/cloud_devices_sheet.dart` — the predicate and the three call sites
- `lib/app/providers/auth_providers.dart` — one accessor

No server change, no new localization keys (`playingHere` and `controlThisDevice` already exist).

## Verification

**Automated**

- `flutter test` — full suite must stay green (627 currently).
- Add source-level assertions following the convention already used in
  `test/player_controller_queue_order_test.dart` and `test/cloud_song_loading_feedback_test.dart`:
  the sheet routes to `_join` only under `_isPlayingTarget`, and `_isPlayingTarget` requires both
  `session.playing` and `presence == 'online'`.

**Manual — the reported bug is case 2**

1. Play on Windows → phone row reads "Playing here - Control this device"; tapping syncs.
   *(Existing behaviour must not regress.)*
2. **Stop or pause on Windows → phone row reverts to its normal presence label; tapping transfers
   the phone's queue.** No longer requires ending the session from Windows.
3. Close the Windows app entirely → row shows background/unavailable and offers no join.
4. Phone with an empty queue taps an idle Windows → gets a message rather than silence.
