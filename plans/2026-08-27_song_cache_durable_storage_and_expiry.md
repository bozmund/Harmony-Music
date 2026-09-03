# Song cache: durable storage with age-based expiry

## Context

Cached song audio is written to `getTemporaryDirectory()/cachedSongs/*.mp3`
(`lib/services/audio_handler.dart:379`). On Windows that is `%TEMP%`, which Storage Sense empties
behind the app's back; on Android it is the OS-reclaimable cache dir. The Hive metadata survives, so
entries are left pointing at files that no longer exist.

Two consequences, the second much worse than the first:

1. Every stale entry costs a full re-resolve at playback time. A single Windows log showed this on
   four consecutive preloads — `Cached audio for <id> is missing from disk`.
2. **Songs vanish from the user's library.** `lib/ui/screens/Library/library_controller.dart:78`
   builds the Songs list by scanning that same directory, so an OS cleanup silently removes entries
   the user can see.

The setting itself promises otherwise — *"Caching songs while playing for future/offline playback"*
(`cacheSongsDes`). Storing that in a directory the OS is free to wipe contradicts the feature's own
description.

The directory is also computed independently in three places, all via `getTemporaryDirectory()`:
`audio_handler.dart:379`, `library_controller.dart:78`, and `library_controller.dart:314`. Any move
has to fix all three, so the first step is to stop duplicating it.

**Decision (confirmed):** durable location, bounded by **age-based expiry** rather than a size cap —
cached audio not played in 30 days is deleted. Accepted trade-off: a rarely played favourite can
still disappear, and there is no hard ceiling on total size.

## Approach

### 1. One place that knows where the cache lives

Add a single `songCacheDirectory()` helper (alongside the existing utilities in `lib/utils/`)
returning `getApplicationSupportDirectory()/cachedSongs` — the same durable root downloads already
use (`getApplicationSupportDirectory()/Music`, `audio_handler.dart:1346`).

Replace all three `getTemporaryDirectory()` song-cache call sites with it. Leave the other
`getTemporaryDirectory()` users alone (backup restore, update installers, playlist import) — those
are genuinely temporary.

### 2. Migrate what is already cached

On startup, move any files from the old `<temp>/cachedSongs` into the new directory, then remove the
old directory. Idempotent, and cheap when it is already empty. Without this, everything currently
cached disappears from the Songs list the moment this ships — the exact failure being fixed.

### 3. Age-based expiry in the existing housekeeping

`lib/utils/house_keeping.dart` already runs at startup with `SongCacheRepository` in hand and is the
natural home; add `removeExpiredCachedAudio` beside the existing
`removeExpiredSongsUrlFromDb` / `removeThinCachedSongs` / `removeDownloadsWithoutLocalFile` passes.

- Constant `cachedAudioMaxAge = Duration(days: 30)`, exposed like the existing
  `thinCachePurgeVersion` so tests can drive it.
- Delete `*.mp3` whose `File.stat().modified` is older than the cutoff, plus the `.part` / `.mime`
  sidecars `LockCachingAudioSource` leaves behind (`library_controller.dart:81` already knows to
  filter those two extensions).
- For each file removed, call `songCacheRepository.deleteCachedSong(songId)` so Hive and the library
  stay consistent instead of re-creating the dangling-entry problem this plan exists to fix.
- Log a single summary line, matching the style of `removeThinCachedSongs`.

### 4. Make "age" mean *last played*, not *first cached*

`LockCachingAudioSource` writes the file once, so mtime alone would expire a song 30 days after it
was cached no matter how often it is played. Last-access time is not usable — NTFS has
`NtfsDisableLastAccessUpdate` on by default.

Instead, touch the file on every cache hit with `File.setLastModified(DateTime.now())`. Both read
paths already stat the file, so this adds no extra I/O round trip:

- `_cachedStreamInfoForSong` (`audio_handler.dart:1305`) — the preload path
- `checkNGetUrl` (`audio_handler.dart:2572`) — the main playback path

This deliberately needs no schema change and works for files cached before this lands.

## Files

- `lib/utils/` — new `songCacheDirectory()` helper
- `lib/services/audio_handler.dart` — use the helper; touch mtime at the two cache-hit sites
- `lib/ui/screens/Library/library_controller.dart` — use the helper at both sites
- `lib/utils/house_keeping.dart` — migration + `removeExpiredCachedAudio`

No new settings and no new localization keys; expiry is a constant for now.

## Verification

**Automated**

- `flutter test` — full suite green (635 currently).
- New tests for the pure parts, following the convention in `test/` (see
  `test/playback_session_persistence_test.dart` for the source-level style, and note
  `removeThinCachedSongs` is already exercised with a seeded purge version):
  - a file older than `cachedAudioMaxAge` is deleted and its Hive entry dropped with it
  - a file newer than the cutoff survives
  - `.part` and `.mime` sidecars go with their `.mp3`
  - migration moves files out of the old directory and is a no-op on a second run
  - both cache-hit paths call `setLastModified`, so a played song does not age out

**Manual**

1. Play a song with Cache Songs on, confirm the file appears under
   `%APPDATA%\com.anandnet\harmonymusic_dev\cachedSongs\` and **not** in `%TEMP%`.
2. Confirm anything already cached in `%TEMP%` moved across on first launch and still shows in Songs.
3. Run Storage Sense (or clear `%TEMP%` by hand) and confirm the library is now unaffected — this is
   the reported bug.
4. Back-date a cached file's mtime by more than 30 days, restart, confirm it is gone from disk and
   from Songs; play another cached song and confirm it survives a restart.
