# Phone joins playback already running on Windows

## Context

Cross-device playback today only ever *pushes*. You open "Play on a device", tap another
device, and this device hands its queue over. There is no way to go the other direction:
Windows is already playing, you pick up your phone, and you want the phone to subscribe to
that session and act as its remote — audio staying on Windows.

In Jan's words: *"like when phone transfers playing to windows in 'Playing on a device' but
without any transfer — the windows should just hand the queue to phone, like the phone
subscribes."*

Decisions taken:

- **Audio stays put.** The joining device mirrors and controls; it plays nothing itself.
- **Two actions per device row.** Tapping a row keeps today's meaning — *send my queue
  there*. A new second button on the row means *receive what is playing there*.
- **Do nothing if the joining device is already playing.** No prompt, no takeover.
- **The Harmony-Cloud change is in scope**, because the feature cannot work without it.
- **A new, separate preference** gates publishing — deliberately not folded into cloud
  sync, because a future "broadcast what I'm playing to friends" feature will read the same
  toggle.

## Why a backend change is unavoidable

There is a chicken-and-egg in the session model:

1. **A device playing on its own publishes nothing.** Every publish path opens with
   `if (!_isAudioTarget) return;` (`cloud_playback_receiver.dart`, `_scheduleStatePublish`
   and `_publishSessionState`), and `_isAudioTarget` only becomes true by *accepting a
   handoff*. The server drops progress frames from a non-target too.
2. **A device cannot open a session for itself.**
   `Harmony-Cloud/src/Harmony.Cloud.Api/Program.cs:280-282` rejects
   `SourceDeviceId == TargetDeviceId`, and `POST /playback/session/state` 404s unless a
   session already exists naming you as target.

So there is no session to join, and no way for Windows to create one. The existing handoff
cannot be reused in reverse — it pushes the caller's queue outward, overwriting what
Windows is playing.

## What already works and must not be rebuilt

The controller half exists and is correct. Once a device is "engaged",
`CloudPlaybackReceiver._applySession` (`cloud_playback_receiver.dart:433-451`) already does
the whole job:

```dart
if (!_isEngaged) return;
if (targetDeviceId != _cloud.deviceId) {
  _isAudioTarget = false;
  _stopProgressPublishing();
  _commands.startRemoteControl(targetDeviceId);
  await _mirrorQueue(state, positionMs, durationMs, playing);
  return;
}
```

`_mirrorQueue` rebuilds the queue from `queueIds` and backfills metadata; `applyRemoteQueue`
/ `applyRemoteProgress` drive every observable the player reads, with `_remoteAnchor`
extrapolating between the 2s progress frames. The server already pushes a `sessionSnapshot`
on socket connect, carrying `positionMs`/`playing` precisely so — per its own doc comment —
*"a device joining mid-session must be able to start at the right position."*

**No `PlayerController` changes are expected.**

## The work

### 1. Harmony-Cloud — let a device claim itself as target

New `POST v1/playback/session/claim` in
[Program.cs](../../MyRepositories/Harmony-Cloud/src/Harmony.Cloud.Api/Program.cs), modelled
closely on `/playback/session/start` (line 276) but with one device id: the caller is both
source and target. Keep `PlaybackSessionState.IsValid` / `PlaybackPayload.IsPortable`
validation and the existing device-belongs-to-account check.

Two behaviours to get right, both visible in `session/start`:

- It ends all live sessions (`foreach (var previous in old) previous.EndedAt = now;`). A
  claim must **not** stomp an active handoff session — if one exists with a different
  target, the claim should be refused rather than silently taking over.
- It broadcasts a snapshot `exceptDeviceId: request.DeviceId`, which is what wakes the
  phone. Keep that.

### 2. App — publish while playing locally

New preference, following `cloudSyncEnabled`'s existing shape rather than the general
settings repo, since the toggle sits beside it:

- `PrefKeys` entry in [constant.dart](lib/services/constant.dart)
- getter/setter in [cloud_sync_repository.dart](lib/data/repositories/cloud_sync_repository.dart)
  (next to `enabled` / `optInAnswered`)
- surfaced through `authController` like `setCloudSyncEnabled`, rendered in
  [settings_screen.dart](lib/ui/screens/Settings/settings_screen.dart) under the existing
  device-control section
- **default off**, name it for the broader purpose (e.g. "Share what I'm playing") so the
  friends-broadcast feature can reuse it verbatim

In `CloudPlaybackReceiver`, when local playback starts and the preference is on and no
session exists, call the claim endpoint and set `_isAudioTarget = true`. That single flag
turns on `_scheduleStatePublish` and `_startProgressPublishing` unchanged — this is why the
publishing side needs almost no new code.

### 3. App — join from the devices sheet

[cloud_devices_sheet.dart](lib/ui/widgets/cloud_devices_sheet.dart) gains a trailing
"receive" button on rows for *other* devices, shown only when that device is currently the
audio target and **this** device has no current song (`player.currentSong.value == null`).
It calls `PlaybackCommandService.startRemoteControl(device.deviceId)`, which flips
`_isEngaged` true so the snapshot and progress frames already arriving get accepted.

Check whether the unused `switchSharedTarget`
([playback_command_service.dart:162](lib/services/playback_command_service.dart)) fits
before adding a new method — it currently has no caller.

Two existing rough edges in this file worth fixing while there: the tap handler returns
early when this device has no current song (`:249-251`), and the `'Playing here'` subtitle
is hard-coded rather than localized.

## Verification

- **Unit:** `flutter test` — 619 passing today, must stay green.
- **Integration:** extend
  [remote_playback_test.dart](integration_test/remote_playback_test.dart), which already
  simulates two devices in-process through `_PlaybackBridge` / `_BridgeGateway` /
  `_BridgeSocket`. Build a second `CloudPlaybackReceiver` on `bridge.gateway('android')`,
  seed a live session owned by `'windows'`, and assert the phone reports
  `isMirroringRemotePlayback` with a mirrored queue and advancing progress. Add a case
  asserting the receive button does nothing while the phone has its own current song.
  Instantiate the android socket **before** the first broadcast — `_BridgeSocket.addFrame`
  only fans out to sockets already created.
- **Cloud:** add a test for `session/claim` covering the refusal-when-a-handoff-session-exists
  case, alongside the existing playback endpoint tests.
- **Manual (Jan):** play on Windows, open the phone, tap receive, then confirm
  play/pause/skip/seek from the phone drive Windows' audio and the phone stays silent.
  Also confirm nothing is offered while the phone is playing its own music.

## Localization

Every new string goes in **both** `lib/l10n/app_en.arb` and `lib/l10n/app_hr.arb` with
identical `@key` placeholder blocks — `test/localization_sync_test.dart` enforces
byte-identical declarations and fails the build otherwise. Then `flutter gen-l10n`, and
commit the regenerated `app_localizations*.dart`. Accessor is `context.l10n.myKey`.

## Sequencing

The Cloud change must deploy before the app side does anything useful, so: Cloud PR first,
deployed and verified, then the app PR. The app's receive button should degrade quietly if
the endpoint is missing rather than throwing.
