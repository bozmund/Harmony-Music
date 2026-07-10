# Remaining Riverpod 3 / GetX Removal Plan

## Current State

The dependency baseline is in place: `flutter_riverpod` is on 3.x, `go_router` is installed, Flutter `gen-l10n` is configured, app tests use `mocktail`, and the app has transitional provider/router/localization infrastructure.

This is not a complete GetX removal yet. As of the latest migration slice, production code still has GetX imports in 78 Dart files, 12 `GetxController` references, 0 `GetxService` references, and 6 `Get.put(...)` call sites, including `GetMaterialApp`, `Get.find`, `.obs`, `Obx`, `.tr`, `Get.context`, `Get.dialog`, `Get.back`, and `Get.snackbar`.

The migration must remain incremental: each subsystem should compile, analyze, and test before moving to the next one.

## Already Done

- Riverpod 3 dependency graph is resolved.
- Mockito is removed from app dev dependencies; `mocktail` remains.
- `go_router` dependency and `appRouterProvider` exist.
- Flutter `gen-l10n` is configured with ARB files generated from the old GetX translation map.
- Existing repository/service/controller providers exist under `lib/app/providers`.
- Search input/history/suggestion state is now a Riverpod-backed `ChangeNotifier`; Search input route pushes use the app-owned nested navigator key. Search Result still uses GetX reactive state.
- `PipedServices`, `MusicServices`, `SyncedLyricsService`, `WindowsAudioService`, `MyAudioHandler`, `Downloader`, platform-only helpers, and the app platform/file/update static facades no longer use GetX as their service locator/lifecycle base.
- `ThemeController` is now Riverpod-owned `ChangeNotifier` state; `main.dart` listens through Riverpod/`AnimatedBuilder` instead of `GetX<ThemeController>`.
- `DesktopSystemTray` is now a plain disposable service with explicit audio/player/settings dependencies.
- `IssueReportDialogController`, Piped linking, import Spotify/YouTube Music playlist, export files, backup, restore, and add-to-playlist controllers are now local `ChangeNotifier` dialog state instead of `GetxController`/`Get.put` state.
- Combined library tab ownership moved into local widget state with an inherited tab-controller scope.
- Library saved searches are now backed by `LibraryRepository` through a local `ChangeNotifier`; the saved-search controller no longer opens Hive directly.
- `AddToPlaylistController` no longer uses `Get.find`, `Get.put`, `.obs`, or global `Get.delete` cleanup; call sites rely on widget-local disposal.
- Analyzer excludes vendored `third_party/**/test/**` so app analysis does not require third-party Mockito test dependencies.

## Remaining Implementation

### 1. App Shell And Composition Root

- Replace `GetMaterialApp` in `main.dart` with `MaterialApp.router`.
- Read `appRouterProvider`, `settingsRepositoryProvider`, and the theme provider from Riverpod instead of `Get.find`.
- Move `AudioHandler` registration into a Riverpod provider and remove `Get.put<AudioHandler>`.
- Replace `LifecycleHandler` dependency access with constructor-injected `AudioHandler`.
- Remove `registerGetxBridge` only after every old `Get.find` consumer is gone.

### 2. Routing And Navigation

- Replace `lib/ui/navigator.dart` nested `Navigator` + `GetPageRoute` with `go_router` routes.
- Preserve existing route intents:
  - home
  - search
  - search result with query argument
  - playlist with playlist id/source arguments
  - album with album/id arguments
  - artist with artist/id arguments
- Replace all `Get.toNamed`, `Get.back`, and `Get.nestedKey(...)` calls with `context.go`, `context.push`, `context.pop`, or an injected app navigation service.
- Convert app links from `AppLinksController extends GetxController` to a Riverpod service/notifier that receives `GoRouter`, `MusicServiceContract`, and `PlayerController`/player notifier dependencies explicitly.
- Add navigation smoke tests for home, search, search result, playlist, album, artist, and deep-link flows.

### 3. Localization

- Localization call sites have been migrated to generated `AppLocalizations` through `context.l10n`.
- Rename legacy invalid localization keys during replacement:
  - uppercase keys such as `CreateNewPlaylist`
  - reserved words such as `dynamic`
  - keys with symbols such as `music&Playback`
  - raw placeholder strings such as `{Song Name}`
- Add ARB metadata for real placeholders instead of interpolating translated fragments manually.
- The old `Languages` map and generated custom-localization file have been removed.
- A source guard fails if the legacy translation extension is reintroduced.

### 4. Settings And Theme State

- Convert `ThemeController` to a Riverpod notifier that exposes `ThemeData` and theme commands.
- Convert `SettingsScreenController` to a Riverpod notifier with an immutable settings state.
- Inject settings-related collaborators explicitly:
  - `SettingsRepository`
  - `StorageAdminRepository`
  - `AudioHandler`
  - `MusicServiceContract`
  - home/player/library notifiers as needed
- Replace all settings `Rx` fields with typed state fields.
- Convert Settings UI from `Obx` to `ConsumerWidget` / `ConsumerStatefulWidget`.
- Add focused tests for theme mode, language, playback mode, cache toggles, download/export paths, update settings, and developer settings.

### 5. Player, Audio, Download, And Platform Services

- Convert `PlayerController` to a Riverpod notifier with immutable player UI/queue state.
- Convert `Downloader` reactive fields to a Riverpod notifier or service plus progress state provider.
- Remove hidden `Get.find` calls from:
  - `audio_handler.dart`
  - `downloader.dart`
  - `windows_audio_service.dart`
  - `synced_lyrics_service.dart`
  - platform/file/update facades
- Replace `Get.context` snackbars with context-scoped UI calls or an app message provider consumed at the shell.
- Preserve existing playback behavior and tests around queue ordering, source swaps, preloading, downloads, and session restore.

### 6. Home, Search, Library, Playlist, Album, And Artist State

- Convert `HomeScreenController` to a Riverpod notifier.
- Finish Search migration:
  - convert Search Result controller and UI off `GetxController`, `.obs`, and `Obx/GetX`
  - move search result route arguments into typed `go_router` state/extra parsing
- Convert Library controllers into providers:
  - songs
  - playlists
  - albums
  - artists
  - saved searches refresh integration across tabs
- Convert playlist/album/artist page controllers to `autoDispose family` providers keyed by route id.
- Replace `PlaylistAlbumScreenControllerBase` with shared plain Dart logic or shared notifier helpers.
- Preserve dynamic page behavior for local playlists, Piped playlists, albums, artists, offline items, sorting, searching, and multi-select operations.

### 7. Dialogs, Sheets, And Widget-Local Controllers

- Convert dialog-only `GetxController` classes to local widget state or `autoDispose` providers:
  - song info bottom sheet
  - sort widget
- Replace `Get.dialog`, `Get.bottomSheet`, and `Get.snackbar` with Flutter `showDialog`, `showModalBottomSheet`, and `ScaffoldMessenger`.
- Pass dependencies through constructors/providers rather than reaching into global state.
- Keep dialog state ephemeral unless it must survive route changes.

### 8. Repository And Storage Cleanup

- Remove GetX registration from `hive_repository_registration.dart` once repository providers are the only registration path.
- Keep direct Hive access limited to:
  - Hive repository implementations
  - Hive bootstrap
  - storage admin internals
  - tests
- Remove any remaining direct Hive imports in UI/controllers/widgets during the same subsystem migrations.
- Add a final source guard for Hive import boundaries.

### 9. Final GetX Deletion

- Delete `lib/app/providers/getx_bridge.dart`.
- Delete `get` from `pubspec.yaml`.
- Delete `lib/utils/get_localization.dart`.
- Remove all `package:get/get.dart` imports.
- Add source guards for:
  - no `package:get/get.dart`
  - no `Get.`
  - no `GetxController`
  - no `.obs`
  - no `Obx(`
  - no `GetX<`
  - no `.tr`
- Run final analyzer and full test suite.

## Testing Gates

Run after each subsystem:

```powershell
& 'C:\dev\flutter\bin\flutter.bat' analyze
& 'C:\dev\flutter\bin\flutter.bat' test <focused-test-path>
```

Run at the end of each major phase:

```powershell
& 'C:\dev\flutter\bin\flutter.bat' test
```

Required final coverage:

- Provider override tests for repositories, services, router, settings, player, downloader, home, search, library, playlist, album, and artist state.
- Navigation smoke tests for every app route and deep-link entry.
- Localization smoke tests for supported locales and renamed keys.
- Source guard tests for no GetX usage and allowed Hive boundaries.
- Existing playback/download/cache regression tests must remain green.

## Acceptance Criteria

- `flutter analyze` passes.
- `flutter test` passes.
- `pubspec.yaml` no longer depends on `get`.
- Production code has no `package:get/get.dart` imports.
- Production code has no `Get.`, `GetxController`, `.obs`, `Obx(`, `GetX<`, or `.tr`.
- App starts through `MaterialApp.router`.
- Navigation uses `go_router`.
- UI text uses generated `AppLocalizations`.
- All long-lived dependencies are created through Riverpod providers.
- Existing Hive box names and stored data shapes remain compatible.
