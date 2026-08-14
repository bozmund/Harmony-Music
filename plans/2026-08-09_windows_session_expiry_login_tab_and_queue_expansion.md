# Windows session expiry, Windows login tab, and the unfilled "similar songs" queue

## Context

Three separate defects, all reported from the Windows build:

1. **An expired session is invisible on Windows.** On Android/iOS/macOS a lapsed token makes
   `Auth0Service.tryRestoreSession()` throw inside `CredentialsManager`, so `AuthController.init()`
   sets `userProfile = null` and the app presents itself as signed out — Settings shows
   "Login / Register" and, with sync on, the Library shows the `sessionExpiredMessage` banner.
   On Windows `_restoreFromSecureStorage()` ([lib/services/auth0_service.dart:217](lib/services/auth0_service.dart:217))
   only decodes the cached `user` blob out of `flutter_secure_storage`. It never touches the token,
   so a device whose refresh token died months ago still boots looking fully signed in.
   Separately, when a refresh *does* fail mid-session with 400/401, `_refreshWindowsCredentials`
   silently deletes the stored credentials ([auth0_service.dart:296-299](lib/services/auth0_service.dart:296))
   and returns `null` — nothing tells `AuthController`, so the UI stays "signed in" until the next
   relaunch, and every cloud call quietly 401s in the meantime.

2. **The Windows login browser tab is left open.** Logout's tab closes; login's does not. Neither
   is the app's doing. Both flows are identical — `ShellExecuteW` → system browser →
   `harmonymusic://callback` custom scheme → protocol activation → named pipe → the plugin polls
   `PLUGIN_STARTUP_URL`. There is no loopback server and no served HTML anywhere in the repo.
   The logout URL 302s straight to the custom scheme, so that tab **never commits a page**; browsers
   auto-close a fresh tab with empty history when it hands off to an external protocol handler. The
   login tab commits Auth0 Universal Login and (with `prompt=login`) the Google account chooser, so
   it has history and a rendered document, and no browser will auto-close that. `window.close()` is
   also a no-op for a tab the user did not script-open. **True auto-close is not achievable.** What
   is achievable is the standard desktop-OAuth end state: land the tab on a page that says the sign-in
   worked and the tab can be closed, via the plugin's currently-unused `redirectUrl` option.

3. **Tapping a song sometimes leaves it alone in the queue.** Home Quick Picks and search results both
   call `PlayerController.pushSongToQueue(mediaItem)`, which fires `getWatchPlaylist` and replaces the
   queue with the result. `setSourceNPlay` sets `queue.add([currMed])`
   ([lib/services/audio_handler.dart:2028](lib/services/audio_handler.dart:2028)) to start playback
   immediately, expecting the slower watch-playlist result to overwrite it. The expansion has **no
   error handling** ([lib/ui/player/player_controller.dart:1652-1675](lib/ui/player/player_controller.dart:1652)),
   and on the local path it is consumed by `unawaited(queueUpdate.then(...))` with no `onError`. Any
   throw therefore means `updateQueue` never runs, the error becomes an unhandled async error, and the
   queue is left as the single tapped song — while the song itself plays fine. `getWatchPlaylist` has
   several unguarded throw points, the worst being `.first` at
   [lib/services/music_service.dart:341](lib/services/music_service.dart:341), which raises
   `StateError: No element` when no track in a valid response carries a playlist id — for a value the
   caller never even reads. This is online-only (offline library playback goes through
   `playPlayListSong`, which never calls `getWatchPlaylist`) and intermittent, matching the report.

   One caveat worth stating plainly: this diagnosis comes from reading the code, not from a log of your
   actual failure. Both defects are real and unambiguous on their own terms — `.first` throws, and the
   error is genuinely unhandled — but I cannot prove from here that this is the exact path you hit. The
   logging added in 3b is what would confirm it if it recurs.

Intended outcome: Windows surfaces a dead session exactly like the phone does, both at launch and the
moment it dies; the Windows login tab ends on a deliberate "you can close this tab" page; and a failed
watch-playlist lookup can no longer silently strand the queue at one song.

---

## Part 1 — Windows session expiry

### 1a. Validate the token on restore

`lib/services/auth0_service.dart`

- In `tryRestoreSession()`, the Windows branch must prove the session is still usable rather than
  trusting the cached profile. After `_restoreFromSecureStorage()` returns a profile, call the
  existing `_windowsAccessToken(forceRefresh: false)` and return `null` when it yields `null`.
- Reuse the existing machinery — do not add a second refresh path. `_windowsAccessToken` already
  short-circuits on a still-valid token and delegates to `_refreshWindowsCredentials` otherwise, and
  `_windowsRefreshInFlight` already de-duplicates concurrent refreshes.
- **Offline must not sign anyone out.** `_refreshWindowsCredentials` already distinguishes: it clears
  credentials only on 400/401 and leaves them intact on any other `DioException`. That distinction has
  to reach the caller, which it currently cannot — both cases return `null`. Introduce a private
  outcome (e.g. an enum or a nullable `bool sessionRevoked` field set alongside the clear) so
  `tryRestoreSession` returns `null` **only** on a genuine revocation, and on a network failure returns
  the cached profile unchanged. Getting this backwards would sign users out on every offline launch.
- Guard the `_audience.isEmpty` case: `accessToken()` returns `null` early when no audience is
  configured ([auth0_service.dart:162](lib/services/auth0_service.dart:162)). Restoration must not
  treat that as expiry — an unconfigured audience is not a dead session.

### 1b. Broadcast mid-session revocation

- Add a session-revoked signal to `Auth0Service` — a `Stream<void>` (or `void Function()` callback)
  exposed on `AuthServiceContract` in [lib/services/app_contracts.dart:125](lib/services/app_contracts.dart:125),
  emitted from the same 400/401 branch that calls `_clearPersistedCredentials()`.
  Put it on the contract, not just the concrete class, so `FakeAuthService` can drive it in tests.
- Have `AuthController` (in [lib/app/providers/auth_providers.dart:81](lib/app/providers/auth_providers.dart:81))
  subscribe in its constructor: on a revocation, stop cloud sync via `_cloud.stop()`, set
  `userProfile = null`, reset `sessionExpiredNoticeDismissed = false`, and `notifyListeners()`.
  Do **not** clear `cloudAccountSubject` — `needsReauthentication` is derived from
  `!isAuthenticated && accountSubject != null && cloudSyncEnabled`
  ([auth_providers.dart:125](lib/app/providers/auth_providers.dart:125)), so keeping the subject is
  exactly what makes the banner and the Settings badge appear. Cancel the subscription in `dispose()`.
- No new UI is needed. `SessionExpiredBanner` ([lib/ui/widgets/session_expired_banner.dart](lib/ui/widgets/session_expired_banner.dart))
  and the Settings account row ([lib/ui/screens/Settings/settings_screen.dart:103-137](lib/ui/screens/Settings/settings_screen.dart:103))
  already render off that derived state; they simply never saw it on Windows.

### 1c. Tests

- Unit, `test/`: a new test over `Auth0Service` restore semantics — revoked refresh token returns
  `null`; network failure returns the cached profile; a still-valid stored token returns the profile
  without a network call.
- Integration: extend `integration_test/session_expiry_test.dart` (do not create a new file) with a
  case where `FakeAuthService` starts with a `restorableSession`, then emits a revocation mid-run, and
  the Library banner plus Settings badge appear **without a relaunch**. `FakeAuthService`
  ([integration_test/support/fakes.dart:623](integration_test/support/fakes.dart:623)) needs a way to
  fire the new signal.

---

## Part 2 — Windows login landing page

### 2a. Harmony-Cloud (`C:\MyRepositories\Harmony-Cloud`)

`src/Harmony.Cloud.Api/Program.cs`

- Map an **unauthenticated** `GET /cloud/auth/windows/callback` on `app`, *not* on the `cloud` group —
  the group carries `RequireAuthorization()` ([Program.cs:133](Program.cs:133)) and the browser has no
  bearer token here. Mirror the placement of `/cloud/health/live` at
  [Program.cs:126](Program.cs:126).
- The handler returns a small self-contained HTML page (no external assets) that:
  - immediately redirects the browser to `harmonymusic://callback` **with the incoming query string
    forwarded verbatim** — via `<meta http-equiv="refresh">` plus a `location.replace` script, so the
    protocol handoff still happens and the existing native pipe path is untouched;
  - renders "Signed in to Harmony Music — you can close this tab", with a manual link as a fallback
    for a browser that blocks the automatic protocol navigation.
- Forward only the query string; do not parse, log, or store the `code`/`state`. Set
  `Cache-Control: no-store`.
- The debug and release schemes differ (`harmonymusic-dev` vs `harmonymusic`,
  [auth0_service.dart:23](lib/services/auth0_service.dart:23)). Carry the target scheme in the query
  string (e.g. `?scheme=harmonymusic-dev`) and validate it against a hardcoded allowlist of those two
  values before building the redirect — never echo an arbitrary scheme into a `location.replace`.
- Add a test under `tests/` asserting the route is reachable without a bearer token, that the query
  string round-trips, and that an unknown `scheme` value is rejected.

### 2b. Harmony-Music

- In `Auth0Service.login()`, pass `redirectUrl:` to `windowsWebAuthentication().login(...)`
  ([auth0_service.dart:122](lib/services/auth0_service.dart:122)) pointing at the new endpoint, with
  the scheme parameter appended. Derive the base from `HarmonyCloudClient.defaultBaseUrl`
  ([lib/services/cloud/harmony_cloud_client.dart:99](lib/services/cloud/harmony_cloud_client.dart:99))
  rather than hardcoding the host a second time.
- Leave `logout()` alone — its tab already closes itself, and routing it through an intermediary would
  *stop* that from happening.
- Update `docs/windows_auth0_setup.md`: the new Allowed Callback URL, why login and logout differ, and
  that the tab cannot be programmatically closed.

### 2c. Auth0 dashboard (manual, by you)

Add `https://harmony-resolver.duckdns.org/cloud/auth/windows/callback` to **Allowed Callback URLs**
for the Harmony Music application. `harmonymusic://callback` and `harmonymusic-dev://callback` must
stay listed — the plugin still validates against `appCustomURL`. **Allowed Logout URLs** are unchanged.

---

## Part 3 — The unfilled queue

### 3a. Stop `getWatchPlaylist` throwing on an optional field

`lib/services/music_service.dart`

- [line 332-341](lib/services/music_service.dart:332): the `playlist` extraction ends in `.first`,
  which throws `StateError` when no entry yields a playlist id. `pushSongToQueue` never reads the
  returned `playlistId`. Make it non-fatal — take the first non-null match or `null` — so a response
  with perfectly good tracks is no longer discarded wholesale.
- Guard `results['contents']` being absent before mapping over it: `nav(...)` returns null on an
  unexpected response shape, and `results.addAll(null)` / `null.map(...)` currently throws.

### 3b. Retry the expansion, and show that it is loading

`lib/ui/player/player_controller.dart`

- Wrap the body of the `queueUpdate` future ([line 1652-1675](lib/ui/player/player_controller.dart:1652))
  in a `try/catch` that logs via the existing `printERROR` + `LogTags` convention and returns `null`,
  so a failure can never surface as an unhandled async error and can never leave `updateQueue` unrun
  by accident.
- **Retry with backoff** rather than giving up after one failure: attempt the lookup up to 5 times
  with a 1s/2s/4s/8s delay between tries. Two aborts must short-circuit the loop immediately:
  - `selectionGeneration != _playNowSelectionGeneration` — a newer tap supersedes this one, and a
    retry loop must never outlive its selection. This is the same guard already used at
    [lines 1658/1662](lib/ui/player/player_controller.dart:1658); it now also has to be checked
    *between* attempts.
  - controller disposal.
- Add an observable `isQueueExpanding` (an `RxBool`/`ValueNotifier`, matching the existing
  `isShuffleModeEnabled` / `isQueueLoopModeEnabled` style on this controller). Set it true when the
  expansion starts, false when it succeeds, is superseded, or exhausts its retries. It must be reset
  in a `finally` so no path can leave a spinner running forever.
- On final exhaustion: leave the single-song queue, clear the flag, log the cause. Never throw.
- Preserve the existing `_playNowSelectionGeneration` guards; they are correct and not implicated here.
- Note `test/player_controller_queue_order_test.dart` parses the `pushSongToQueue` source text — it
  will likely need updating alongside these edits.

### 3b-ii. The loading indicator

`lib/ui/widgets/up_next_queue.dart`

- The `ReorderableListView.builder` already has a `footer` slot
  ([line 43](lib/ui/widgets/up_next_queue.dart:43), currently just `SizedBox(height: bottomPadding)`).
  Render a "finding similar songs" row there while `isQueueExpanding` is true, above the existing
  bottom padding.
- Match the surrounding idiom: reuse `BasicShimmerContainer`
  ([lib/ui/widgets/shimmer_widgets/basic_container.dart](lib/ui/widgets/shimmer_widgets/basic_container.dart)),
  which this file already uses for unresolved rows ([lines 153, 170](lib/ui/widgets/up_next_queue.dart:153)),
  so a pending queue looks like the rest of the app's pending state rather than a bare spinner.
- Add `isQueueExpanding` to the existing `Listenable.merge([...])` at
  [line 35](lib/ui/widgets/up_next_queue.dart:35) so the footer actually rebuilds.
- New l10n key (e.g. `findingSimilarSongs`) in **both** `lib/l10n/app_en.arb` and `lib/l10n/app_hr.arb`
  — the repo ships English and Croatian and they are kept in step. Resolve it through `context.l10n`,
  never a hardcoded string.
- Give the footer a `Key` (e.g. `Key('queue-expanding-indicator')`) so integration tests can assert on
  it, following the keyed-row convention already used here (`queue-row-…`, `queue-dismiss-…`).

### 3c. Integration tests (the ones requested)

Extend `integration_test/player_behavior_test.dart` rather than adding a file, so the existing
`pumpUntil` and `startFixturePlayback` helpers ([player_behavior_test.dart:33,45](integration_test/player_behavior_test.dart:33))
are reused. Add to `integration_test/all_tests.dart` only if a new file ends up being warranted.

New cases:

1. **Home tap fills the queue with similar songs.** Tap `Fixture Song` on Home; assert the handler
   queue reaches both fixture songs, not just the tapped one. (Partly covered today by
   `startFixturePlayback`; make the queue-length assertion explicit and named.)
2. **Search-result tap fills the queue with similar songs.** Currently untested. Navigate to search,
   enter a query, tap the song under `Songs`, assert the same two-song queue. This exercises
   `ListWidget.listViewSongVid` → `pushSongToQueue` ([lib/ui/widgets/list_widget.dart:130](lib/ui/widgets/list_widget.dart:130)).
3. **A throwing `getWatchPlaylist` still plays the song and does not strand the queue.** Subclass
   `FakeMusicService` (the established override pattern — see `_HomeSelectionMusicService`,
   [integration_test/remote_playback_test.dart:1329](integration_test/remote_playback_test.dart:1329))
   so `getWatchPlaylist` throws on the first call and succeeds on the retry. Assert the tapped song
   plays **and** the queue ends up expanded. This is the regression test for the actual bug.
4. **The indicator shows while retrying and disappears once the queue lands.** Same throwing fake,
   held open: assert `Key('queue-expanding-indicator')` is present in the open queue panel during the
   retry and gone afterwards. Use `pumpUntil`, never `pumpAndSettle` — the shimmer animates
   continuously and would hang it (`integration_test/README.md:38-42`).
5. **A newer tap cancels an in-flight retry loop.** Tap one song whose lookup is held failing, then tap
   another that succeeds; assert the second song's queue wins and the indicator clears. Model the
   held/released fake on `_DelayedHomeSelectionMusicService`
   ([remote_playback_test.dart:1360](integration_test/remote_playback_test.dart:1360)). This is the
   guard against the retry loop outliving its selection.
6. **A watch playlist with no playlist id still yields its tracks.** Unit test in `test/` against
   `getWatchPlaylist` parsing, covering the `.first` fix from 3a with a fixture response whose entries
   carry no `navigation_playlist_id`.
7. **A permanently failing lookup degrades gracefully.** `getWatchPlaylist` always throws: the song
   plays, no unhandled async error escapes, the indicator eventually clears, and the queue is left at
   the single song — asserted explicitly so the degraded state is a decision rather than an accident.

Follow the suite's conventions: `.hitTestable()` on text finders, `pumpUntil` rather than
`pumpAndSettle` while a spinner may be on screen, no dialog left open and no async work in flight at
test end (`integration_test/README.md:38-45`).

---

## Verification

Order matters — Part 3 is verifiable entirely from here; Parts 1 and 2 need your devices.

1. **Unit tests** (mine to run):
   ```bash
   .flutter/bin/flutter.bat test
   ```
   Covers 1c (unit), 3a, and the updated `player_controller_queue_order_test.dart`.

2. **Integration suite** on the dedicated `claude_integration_test` AVD (mine to run):
   ```bash
   .flutter/bin/flutter.bat test integration_test/all_tests.dart -d emulator-5554
   ```
   Covers 1c (integration) and all of 3c. Restart the emulator first if it has been up a while.

3. **Windows session expiry** (yours — I never touch the Windows build):
   - Sign in on Windows, then revoke the session from the Auth0 dashboard (or delete the device's
     grant). Relaunch: Settings should show "Login / Register", and with cloud sync on the Library
     should carry the signed-out banner.
   - With the app already open, revoke the grant and then trigger any cloud call (toggle sync, or open
     the devices sheet). The banner should appear **without** a relaunch.
   - Disconnect the network and relaunch: you must stay signed in. This is the regression that matters
     most — getting 1a wrong signs people out every time they open the app offline.

4. **Windows login tab** (yours): after 2a is deployed and the Auth0 callback URL is added, sign in on
   Windows. The app should come to the front as it does today, and the browser tab should be sitting on
   the "you can close this tab" page rather than a stale Auth0 screen. Sign out and confirm that tab
   still closes itself — 2b must not have changed that.

5. **Real-world queue check** (yours): tap songs from Home and from search repeatedly on a live network,
   with the queue panel open. The queue should fill every time; when the lookup is slow or retrying you
   should see the "finding similar songs" row rather than a silently short queue. If it ever ends up
   stranded at one song, the new `printERROR` line will name the cause in the log — `adb logcat` on
   Android, the console log on Windows. Send me that line and I can finish the diagnosis.
