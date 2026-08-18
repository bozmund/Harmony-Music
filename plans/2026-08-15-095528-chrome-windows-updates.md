# Chrome compatibility and in-app Windows installer updates

## Summary

Make the app compile and start in Chrome by preventing web builds from importing Android JNI/FFI code. Extend the existing update dialog so Windows downloads the release installer directly, closes Harmony Music, and opens the normal Inno Setup update wizard—without opening GitHub in a browser.

## Key changes

- Split the three JNI-dependent services into platform facades plus implementations:
  - Keep the existing Android/JNI behavior in IO implementations.
  - Export web-safe stubs for `EqualizerService`, `PermissionService`, and `NearbyPermissions` via conditional exports.
  - On web: equalizer calls are no-ops/return unavailable; external-storage permission is granted because browser storage does not require Android permission; nearby-device permission reports unavailable and rejects explicit requests as unsupported.
  - Keep `jni` and `jni_flutter` dependencies for Android; they will simply no longer enter the web compilation graph.

- Add Windows installer handling to the platform contract:
  - Add a `launchWindowsInstaller(path)` operation to `AppPlatformContract` and `AppPlatformService`.
  - On Windows, start the downloaded `.exe` detached, without a shell or browser; reject calls on other platforms.
  - After a successful launch, persist the playback session, then terminate Harmony Music so Inno Setup can update the existing install cleanly.
  - Keep the existing Inno Setup AppId and interactive wizard behavior; no silent install switches.

- Extend `downloadAndInstallUpdate`:
  - Treat a Windows HTTPS `.exe` asset as an installable update, alongside Android `.apk`.
  - Download it into the temporary update cache with progress, verify it exists and is non-empty, launch it locally, and exit the app.
  - Rename the APK-only cleanup/file helpers to generic update-installer helpers.
  - On Windows download, validation, or launcher failure, show an actionable in-app error and leave the user able to retry; do not fall back to a GitHub browser page.
  - Preserve the current Android installer flow and the existing URL-opening fallback for unsupported platforms.

- Keep GitHub Releases as the distribution backend:
  - Continue selecting the platform-specific `.exe` release asset through the existing GitHub release metadata.
  - Do not alter the release workflow’s Windows packaging format; it already produces a same-AppId Inno Setup installer suitable for in-place updates.

- Add localized English and Croatian status/error strings for Windows download, installer launch, and retry failures; route dialog progress text through localization rather than hard-coded text.

## Test plan

- Unit-test the platform facades:
  - Web stubs expose the same APIs and never reference JNI types.
  - Android/VM permission rules and nearby permission tests remain unchanged.
- Extend update-controller/contract tests:
  - Windows `.exe` downloads invoke the installer launcher and app termination only after a valid download.
  - Windows failures show an error and never invoke `openUrl`.
  - Android `.apk` behavior and unsupported-platform fallback remain unchanged.
- Run `flutter test`, `flutter analyze`, and `flutter build web --no-pub`.
- Manually verify a Windows release install: detect update, download in-app, close Harmony, show Inno Setup, preserve the existing install location and launch the updated app.

## Assumptions

- “Without going on GitHub” means no browser redirect; GitHub Release assets remain the approved HTTPS hosting backend.
- Windows updates use the visible Inno Setup wizard, not a silent/background installer.
- Web does not support Android-only system equalizer, Android storage permissions, or Nearby Connections; those capabilities remain unavailable rather than emulated.
