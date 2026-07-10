# Plan: `.env` config + optional Auth0 login/register

Accepted: 2026-07-10

## Goal
- Add `.env` (flutter_dotenv) support for non-secret client config (Auth0 domain/clientId/redirect scheme).
- Add an **optional** Auth0 account: user logs in only from Settings; no app-launch gate; all music/library features work without login.
- Update `AGENTS.md` to reflect Riverpod (not GetX) and document the new patterns.

## Decisions
- `.env` via `flutter_dotenv` (does not replace existing `--dart-define` build-time values).
- Credential persistence is platform-branched:
  - Android/iOS/macOS: rely on auth0_flutter's built-in Credentials Manager.
  - Windows (`RuntimePlatform.isWindows`): manually persist `Credentials` via `flutter_secure_storage` (SDK does not manage credentials on Windows).

## Implementation steps
1. Add `flutter_dotenv`, `auth0_flutter` (and `flutter_secure_storage`) to `pubspec.yaml`.
2. Add `.env` (gitignored) + `.env.example` with `AUTH0_DOMAIN`, `AUTH0_CLIENT_ID`, `AUTH0_REDIRECT_SCHEME`; register as Flutter asset.
3. `lib/main.dart`: `await dotenv.load()` before `runApp`; read Auth0 config from `dotenv`. Leave `--dart-define` (BuildInfo / ISSUE_REPORT_ENDPOINT) untouched.
4. `lib/services/auth0_service.dart`: wrap `Auth0(domain, clientId)` with `login()`, `logout()`, `userProfile`, `isAuthenticated`; platform-branched persistence as above.
5. Riverpod wiring: `auth0ServiceProvider` + `authControllerProvider` (`ChangeNotifierProvider`) in `lib/app/providers/...`.
6. Optional Settings UI: new section in `SettingsScreenController` + Settings screen (`CustomExpansionTile`/`ListTile` per `docs/component_guide.md`) with Login/Register + Logout; show avatar/email when authenticated.
7. l10n strings in `lib/l10n/app_en.arb` & `app_hr.arb` (e.g. `login`, `logout`, `accountSection`, `loggedInAs`); regenerate via `flutter gen-l10n`.
8. Platform config: Android `AndroidManifest.xml` redirect intent-filter + `app_links` scheme; Windows callback/package config. Register handled on Auth0 hosted Universal Login page.
9. Update `AGENTS.md`: "Flutter/GetX" -> "Flutter/Riverpod (ChangeNotifierProvider controllers)"; document `.env`/flutter_dotenv + Auth0 service; keep `--dart-define` note.
10. Verify: `flutter analyze` + focused unit test for `Auth0Service` credential save/load (mock/in-memory storage for the Windows branch).
