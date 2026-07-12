# Plan: Guest queue-adds + Party mode, built-in playlist artwork, Ford repeat-state bug

## Context

Three user requests for Harmony Music (Flutter, Riverpod + ChangeNotifier, audio_service + just_audio):

1. **Listen Together — guest song requests (auto-add) + "party mode".** The existing Listen Together feature (lib/services/listen_together/) syncs playback across phones on the same LAN. The user wants guests to add songs to the shared queue from their own phone's browse/search UI (auto-added, no host approval), and a new mode for when the host's phone is plugged into a car/speaker: only the host plays audio; guests act as remotes (add to queue + transport controls), their local players untouched.
   - *User's LAN question answered:* the LAN transport needs a shared network — a phone hotspot counts (host or guest can host the hotspot). Without any network, the Bluetooth transport is still a stub (no compatible plugin exists; `flutter_nearby_connections` uses Flutter's removed v1 embedding). State this in the sheet/docs, don't attempt BT now.
2. **Built-in ("base") playlists show first song's artwork.** The starter playlists (Favorites/Liked, Recently played, Downloads, Cached, etc.) currently render fixed icons. They should show their first song's artwork when non-empty and keep the icon look when empty. Same theme: user-created local playlists already derive art (playlist_screen_controller.dart `_updatePlaylistThumbSongBased`) but reset to placeholder when emptied and don't recompute when songs are added via the "Add to playlist" sheet — fix both.
3. **Bug: Ford car forces repeat on BT auto-resume.** Verified root cause: `audio_handler.dart` `setRepeatMode` (≈line 1267) is invoked by the media session when Ford SYNC re-sends its stored repeat state over AVRCP on connect. It sets the player's `LoopMode.one` + `loopModeEnabled` field but (a) never emits a playbackState event, (b) never updates `PlayerController.isLoopModeEnabled` (seeded from settings only at init, player_controller.dart:315), (c) never persists. Result: song loops, car shows repeat ON, app's ∞ icon stays unlit. Other cars don't replay repeat state, hence "only in the Ford".

Constraints for the implementer:
- **Never run the app / adb / emulators.** The user tests on devices. Verify with the repo MCP tools `mcp__harmony-flutter-dart__flutter` / `__dart` (always `timeout_ms: 600000`): `flutter analyze`, `flutter test`, `flutter gen-l10n`.
- Localization = Flutter gen_l10n. Every new key goes in BOTH `lib/l10n/app_en.arb` and `lib/l10n/app_hr.arb` (test/localization_sync_test.dart enforces parity), then regenerate. Access via `context.l10n.<key>`.
- No commits/staging until the user has tested on devices.
- Per CLAUDE.md: after approval, save this plan as a timestamped file in repo `plans/` before implementing.
- Recommended order: WS3 (smallest) → WS2 → WS1 (largest).

## Verified architecture facts (trust these)

- Protocol: `lib/services/listen_together/session_message.dart` — `SessionMessageType {hello, helloAck, queueSync, playbackSync, command, peerList, bye}`; `SessionCommand(action, args)` with constants play/pause/playPause/next/prev/seek/playByIndex/toggleShuffle/toggleLoop. Unknown message types decode as `bye`; unknown command actions are no-ops on old hosts (safe degradation).
- `ListenTogetherController` (lib/services/listen_together/listen_together_controller.dart): host observes PlayerController and broadcasts `queueSync` (via `sessionSafeQueueJson` ≈564, strips local `file` urls) + `playbackSync` heartbeat; guest applies via `PlaybackCommandService`; `_applyCommand` ≈390-427 executes guest commands then `_broadcastPlayback()`. Host auto-rebroadcasts queue on change (`_player.currentQueue.listen` ≈500). Guest sends 5 clock-sync `hello`s in first ~900ms; host replies `helloAck` to each (redundant delivery channel).
- Gate: `listen_together_gate.dart` (`isGuest`, `sendCommand`); `PlayerController._routeToHost` ≈981. Gated: play/pause/playPause/prev/next/seek/seekByIndex/toggleShuffleMode/toggleLoopMode. **NOT gated:** `enqueueSong`(≈813), `enqueueSongList`(≈825), `playNext`(≈857), `pushSongToQueue`(≈693), `playPlayListSong`(≈759).
- All queue-adding UI funnels through those five methods (song_info_bottom_sheet 203/237, song_list_tile 96/115, list_widget 111/122/130, quickpicks_widget 94, playlist_screen 435/463/502/909, album_screen 321/348/565) — gating the methods covers every entry point with zero widget edits.
- `MediaItemBuilder.toJson/fromJson` (lib/models/media_Item_builder.dart:85-99/7): shape `{videoId, title, thumbnails:[{url}], url, duration, ...}`; `artUri` is ALWAYS a network URL (line 32).
- Built-in playlists: synthesized in `library_controller.dart` `initialPlaylists` ≈450-493 (ids LIBRP, LIBFAV, libFavNotDownloaded, libImportDuplicates, libImportReview, SongsCache, SongDownloads) with `Playlist.thumbPlaceholderUrl` (remote PNG; model lib/models/playlist.dart:41-42; `thumbnailUrl` mutable:38). Tiles: `content_list_widget_item.dart` special-cases these ids (61-68) to icon Containers (129-155). Songs per built-in id: same switch as `playlist_album_screen_con_base.dart:97-109` on LibraryRepository. LIBRP is displayed reversed (`playlist_album_screen_con_base.dart:111`).
- User-playlist art: `playlist_screen_controller.dart` `_updatePlaylistThumbSongBased` (378-410) derives + persists via `LibraryPlaylistsControllerRegistry.current?.updatePlaylistIntoDb`; empty branch resets to placeholder (391-395). Gap: `add_to_playlist.dart` add (≈450-457 → `_addLocalMissingSongs` ≈558-580) / remove (≈507-513) never recompute.
- Repeat plumbing: handler `_init()` seeds loop from settings (audio_handler.dart:226-231) on BOTH UI and headless starts; `_notifyAudioHandlerAboutPlaybackEvents` maps repeatMode from `_player.loopMode` (357-361) while `_emitPlaybackSnapshot` maps from the `loopModeEnabled` field (453-455) — unify on the field. `setShuffleMode` (1272-1283) has the identical UI-desync hole (it does emit a snapshot already). In-app toggles persist via `PlaybackCommandService.toggleLoop` (playback_command_service.dart:101-108) — leave unchanged.

---

## WORKSTREAM 3 — Ford/AVRCP repeat desync fix (do first)

**Policy: external `setRepeatMode` does NOT write settings.** AVRCP replays are machine-initiated stale state, not user intent; persisting would let a car permanently flip the user's preference. Cold restart therefore recovers to the user's chosen default. In-app toggles keep persisting (unchanged path). Document with a code comment.

1. `lib/services/audio_handler.dart` `setRepeatMode` (≈1266-1270):
   - Compute `enabled = repeatMode != AudioServiceRepeatMode.none`; if it differs from current `loopModeEnabled`, `printINFO('setRepeatMode -> $repeatMode (media session / external controller)', tag: LogTags.audioHandler)`.
   - Set field + `await _player.setLoopMode(enabled ? LoopMode.one : LoopMode.off)`.
   - Call `_emitPlaybackSnapshot()` at the end (required: `_player.setLoopMode` alone produces no playbackEventStream event; `setShuffleMode` already does this at 1281).
   - Comment: intentionally no settings write (Ford SYNC AVRCP replay must not overwrite user default).
2. Same file, `_notifyAudioHandlerAboutPlaybackEvents` (357-361): replace the `_player.loopMode`-derived repeatMode with `loopModeEnabled ? AudioServiceRepeatMode.one : AudioServiceRepeatMode.none` — single source of truth = the field.
3. `lib/ui/player/player_controller.dart`, inside the `playbackState` listener (`_listenForChangesInPlayerState`, ≈382): edge-detect external changes so the BehaviorSubject's replayed initial state can't clobber the settings-seeded observables:
   - Fields `AudioServiceRepeatMode? _lastSeenRepeatMode; AudioServiceShuffleMode? _lastSeenShuffleMode;`
   - If `_lastSeenRepeatMode != null && repeatMode changed` → set `isLoopModeEnabled.value = (repeatMode != none)`. Always update `_lastSeenRepeatMode`.
   - Symmetric for shuffle; when shuffle flips, mirror the queue-loop coupling from `toggleShuffleMode` (≈942-947): enabling shuffle forces `isQueueLoopModeEnabled = true`; disabling restores `_settingsRepository.getQueueLoopModeEnabled()`.
   - No feedback loop: this listener never calls back into the handler.
4. Tests: none required (thin listener + emit); rely on `flutter analyze` + full `flutter test`.
5. Manual script (user, with the Ford): (a) ∞ off, cold start, confirm off; (b) connect to car with car-repeat stored ON → app ∞ icon NOW lights up, log shows the external setRepeatMode line; (c) turn repeat off from the car → app icon unlights; (d) car sets repeat ON, then cold-start away from car → ∞ off again (not persisted); (e) in-app ∞ toggle still survives restarts; (f) shuffle from head unit follows same pattern.

---

## WORKSTREAM 2 — Built-in playlist artwork from first song

1. New pure helper `lib/utils/playlist_art.dart`:
   `String resolvePlaylistArt({required String currentUrl, required List<MediaItem> songs, required String emptyFallbackUrl})` — empty → `emptyFallbackUrl`; first song's `artUri` null/empty → `currentUrl`; else the artUri string. (Built-ins pass placeholder as fallback → icon look returns when emptied; user playlists pass `currentUrl` → keep last art.)
2. `lib/ui/screens/Library/library_controller.dart` (`LibraryPlaylistsController`):
   - `Future<void> refreshInitialPlaylistThumbs()`: for each `initialPlaylists` entry fetch songs via a switch on playlistId over the existing LibraryRepository APIs (mirror `playlist_album_screen_con_base.dart:97-109`; use `BoxNames` constants); reverse LIBRP to display order; compute `resolvePlaylistArt(..., emptyFallbackUrl: Playlist.thumbPlaceholderUrl)`; mutate `playlist.thumbnailUrl` in place (the static instances are re-spread by `withInitialPlaylistsTail`, so all screens see it; built-ins are never persisted); `notifyListeners()`.
   - Call it in `refreshLib()` (≈534) right after `libraryPlaylists.value = withInitialPlaylistsTail(...)`.
   - `Future<void> recomputeLocalPlaylistThumb(String playlistId)`: built-in id → delegate to `refreshInitialPlaylistThumbs()`; else load playlist + songs from `_playlistRepository`, skip cloud playlists, compute with `emptyFallbackUrl: playlist.thumbnailUrl` (keep art when empty), no-op if `Thumbnail(old).extraHigh == Thumbnail(new).extraHigh` (same guard as playlist_screen_controller.dart:399-401), else `updatePlaylistIntoDb(playlist.copyWith(thumbnailUrl: ...))` (persists + refreshLib).
3. `lib/ui/widgets/content_list_widget_item.dart`: compute `isBuiltInLibraryPlaylist` (the seven ids — replace the string literals with `BoxNames` constants while here) and `builtInHasArt = thumbnailUrl != Playlist.thumbPlaceholderUrl`. Use the ImageWidget branch when `!isBuiltInLibraryPlaylist || builtInHasArt`; keep the icon Container only for empty built-ins. (The "L" badge appearing on built-ins with art is consistent with other local playlists — keep.) Playlist screen header needs no change.
4. Freshness hooks — fire-and-forget `unawaited(LibraryPlaylistsControllerRegistry.current?.refreshInitialPlaylistThumbs() ?? Future.value())` from:
   - `player_controller.dart` `toggleFavourite()` (end) and `_addToRP()` (after `addRecentlyPlayedSong`, ≈1220);
   - `song_info_bottom_sheet.dart` after the `setFavorite` calls (≈557, ≈652).
   - Accepted limitation (comment it): downloads/cache completion refresh on next `refreshLib()`.
5. User-playlist fixes:
   - `playlist_screen_controller.dart` `_updatePlaylistThumbSongBased` (≈379): empty branch → early-return (keep current art) instead of placeholder reset.
   - `add_to_playlist.dart`: after local add (`markSongsAddedToPlaylist`) and local remove (`markSongsRemovedFromPlaylist`), call `recomputeLocalPlaylistThumb(playlistId)` (unawaited).
6. Tests: new `test/playlist_art_test.dart` for `resolvePlaylistArt` (empty→fallback both policies; non-empty→first artUri; missing artUri→currentUrl).
7. Manual script: Favorites/Recently played/Downloads/Cached tiles show first (LIBRP: most recent) song art; empty built-ins keep icons; favoriting from player updates Favorites tile; playing a song updates Recently played; built-in playlist header shows art; "Add to playlist" sheet gives a placeholder playlist its art without opening it; emptying a user playlist keeps its art.

---

## WORKSTREAM 1 — Guest queue-adds (auto) + Party mode

### Design decisions
- **Mode rides on `helloAck`** (`data.mode: "sync"|"party"`), not a new message type — 5 redundant deliveries during clock sync; missing key (old host) = sync = current behavior. Backward compatible both directions.
- **Guest defers `queueSync`/`playbackSync` until mode is known** (host pushes both on peer-join, possibly before first helloAck). Stash latest of each; on first helloAck apply iff sync, else drop. Prevents a party guest's phone from audibly starting at the party.
- **Play-now semantics on a guest (`pushSongToQueue`, `playPlayListSong`) → translate to a single-song `enqueue` of the tapped song + "Added to the shared queue" snackbar, in BOTH modes.** playByIndex is impossible (song not in host queue; party guests aren't mirrored); replacing the host queue is destructive; blocking is friction. Radio-expansion inside pushSongToQueue is skipped — related-song generation stays host-controlled.
- **`seekByIndex` blocked for party guests** (snackbar) — their local queue view isn't mirrored so indices are meaningless; sync-mode routing stays.
- **No new snackbars in `enqueueSong`/`playNext`/`enqueueSongList`** — every call site already toasts on completion; adding one would double-toast. Snackbars only where the guest would otherwise see nothing (`pushSongToQueue`, `playPlayListSong`) + host-side "guest added X".

### Steps
1. **Protocol** — `session_message.dart`:
   - `enum SessionPlaybackMode { sync, party }` with `wireName`/`fromWire(String?)` (unknown/missing → sync).
   - `SessionCommand`: constants `actionEnqueue='enqueue'`, `actionEnqueueList='enqueueList'`, `actionPlayNext='playNext'`; factories `enqueue(Map songJson)` → `{'song': json}`, `enqueueList(List<Map> songsJson)` → `{'songs': [...]}`, `playNextSong(Map songJson)`; accessors `songJson` (null-safe Map) and `songsJson` (List<Map>).
   - `helloAck` factory: optional `String? mode` → `data['mode']`; accessor `sessionModeName`.
2. **Shared payload helpers** — new `lib/services/listen_together/session_payload.dart`: move `sessionSafeQueueJson` body here as `sessionSafeSongJson(MediaItem)` (incl. `_isLocalSourceUrl`), plus `chunkList<T>(List<T>, int)`. Keep the `@visibleForTesting static sessionSafeQueueJson` on the controller as a one-line delegate (existing tests keep passing). Rationale: PlayerController must sanitize without importing ListenTogetherController (avoids construction cycle).
3. **Gate** — `listen_together_gate.dart`: add `bool get isPartyModeGuest;`.
4. **Controller** — `listen_together_controller.dart`:
   - Fields: `_hostMode` (default sync), `_guestMode` (nullable), `_pendingQueueSync`, `_pendingPlaybackSnapshot`; getters `sessionMode` (host→_hostMode, guest→_guestMode) and `isPartyModeGuest` (override). Reset all in `leave()`.
   - `startHosting(kind, {SessionPlaybackMode mode = sync})`; set before wiring.
   - `_onMessage`: `hello` → helloAck now passes `mode: _hostMode.wireName`; `helloAck` → after clock update, if guest && mode unknown: set `_guestMode = fromWire(...)`, apply stashed queue/playback iff sync, clear stash, `notifyListeners()`. `queueSync`/`playbackSync` → if mode unknown: stash; if sync: apply; if party: drop (hard no-op — guest player untouched).
   - `_applyQueueSync`: first line `_player.isRadioModeOn = false;` (guest's stale radio semantics must not fight the mirrored queue).
   - `_applyCommand(command, senderName)` (pass `message.senderName` from call site): new cases enqueue/enqueueList/playNext → `MediaItemBuilder.fromJson` (try/catch + `printERROR`, malformed payloads must not kill the session) → `_player.enqueueSong/enqueueSongList/playNext` → host snackbar `_showGuestAddedSnackbar(senderName, title-or-count)` via `AppNavigator.context` + `snackbar(...)` (pattern: player_controller `toggleQueueLoopMode`). Host executing enqueue on an empty queue auto-starts playback via `playPlayListSong` fallback — desired jukebox behavior. Queue rebroadcast is automatic.
5. **PlayerController routing** (`player_controller.dart`):
   - Helpers: `_isSessionGuest => listenTogetherGate?.isGuest ?? false;` and `_showSessionSnackbar(String)` (AppNavigator.context, skip when null).
   - `enqueueSong`: first line route `SessionCommand.enqueue(sessionSafeSongJson(mediaItem))`.
   - `enqueueSongList`: if guest, send `enqueueList` in chunks of 50 (`chunkList`), return.
   - `playNext`: route `SessionCommand.playNextSong(...)`.
   - `pushSongToQueue`: BEFORE any state mutation — if guest: `mediaItem == null` (radio/playlist-by-id) → `notAvailableInSession` snackbar + return; else route enqueue + `addedToSharedQueue` snackbar + return.
   - `playPlayListSong`: first statement — if guest: route enqueue of `mediaItems[index]` + snackbar + return.
   - `seekByIndex`: before existing routing — if `isPartyModeGuest` → `notAvailableInSession` snackbar + return.
   - `_addRadioContinuation` (≈798): first line `if (_isSessionGuest) return;`.
6. **Sheet UI** (`listen_together_sheet.dart`): `bool _partyMode = false;` + `SwitchListTile` (title `partyMode`, subtitle `partyModeDes`) between transport selector and Host button; Host button passes the mode; in `_activeView` show `partyModeGuestHint` line when `sessionMode == party`.
7. **l10n** (both arb files + gen-l10n): `partyMode`, `partyModeDes`, `partyModeGuestHint`, `addedToSharedQueue`, `notAvailableInSession`, `listenTogetherGuestAdded` ("\"{name}\" added {title}", String placeholders — HR: "\"{name}\" je dodao {title}"), `songsAddedCount` ("{count} songs" / "{count} pjesama", int placeholder) for the enqueueList host toast.
8. **Tests** (`test/listen_together_test.dart`): enqueue command round-trip with local-url stripping (`songJson` has no `url`, `fromJson` reconstructs id/title/artUri); enqueueList order preserved; `chunkList` (7/3 → [3,3,1]; empty → []); helloAck with/without mode; `fromWire(null|garbage) == sync`. Party-mode controller behavior is covered by the manual script (PlayerController is concrete, not fakeable cheaply).
9. **Manual script** (2 phones, same Wi-Fi): sync-mode regression (mirror + controls); guest Enqueue → both queues + host toast; guest Play next → correct position; guest tap-to-play → "Added to shared queue", guest playback NOT hijacked; playlist "Enqueue all" >50 songs → order + chunking; party mode: guest sheet shows hint, guest stays silent while host plays, guest adds/controls work, guest queue-tile tap → blocked snackbar; empty-queue jukebox start; leave → local behavior restored.

---

## Verification (all workstreams)

1. `flutter gen-l10n` after arb edits; `flutter analyze` (must be clean); `flutter test` (existing suites + new `test/playlist_art_test.dart` + extended `test/listen_together_test.dart` + `test/localization_sync_test.dart` parity).
2. Hand the three manual scripts above to the user (device testing is theirs; never run the app).
3. No staging/commits until the user confirms on-device.
