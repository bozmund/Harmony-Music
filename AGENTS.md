# Harmony Music Agent Guide

## First Steps

- Inspect the existing implementation before changing behavior. Start with `rg` and targeted file reads so the current Flutter/Riverpod/Hive patterns drive the solution.
- Check the working tree with read-only Git commands such as `git status`, `git diff`, `git show`, or `git log` when needed.
- Do not run Git commands that change repository state unless the user explicitly asks for that exact Git operation.
- Preserve user work. Do not revert, overwrite, or tidy unrelated changes.

## Working Style

- Keep edits small and aligned with the existing app structure.
- When a plan is explicitly accepted before implementation, save the accepted plan as a timestamped Markdown file in `plans/` at the repository root.
- For Settings UI, prefer the established `CustomExpansionTile`, `ListTile`, `AnimatedBuilder`, `CustomSwitch`, and `SettingsScreenController` patterns.
- Keep controller wiring in Riverpod providers; existing controllers use `ChangeNotifierProvider`.
- Load non-secret Auth0 client configuration from `.env` with `flutter_dotenv`; keep build metadata and `ISSUE_REPORT_ENDPOINT` on `--dart-define`.
- When choosing or building UI widgets, consult `docs/component_guide.md` to reuse existing components before writing inline widgets.
- Keep state in controllers and persisted preferences in Hive using `PrefKeys` when behavior must survive restarts.
- Use `unawaited(...)` intentionally for fire-and-forget futures; analyzer rules treat unawaited futures as errors.
- Avoid editing generated, vendor, or third-party code under `third_party/`, platform build output, `.dart_tool/`, or `build/` unless the task specifically requires it.

## Solving App Issues

- Reproduce or trace the issue from the UI entry point to the controller/service layer.
- Prefer fixing the source of state or data flow instead of adding UI-only patches.
- Keep localization in mind when adding user-facing strings. Reuse existing keys when possible.
- Keep English and Croatian strings in `lib/l10n/app_en.arb` and `app_hr.arb`, access them through generated `AppLocalizations` (`context.l10n` in widgets), and run `flutter gen-l10n` after changes. Do not add custom translation maps or `.tr` calls.
- For Android-specific behavior, guard platform paths with `GetPlatform.isAndroid`; for desktop behavior, check existing desktop guards.
- Redact or avoid exposing auth tokens, visitor IDs, cookies, secrets, passwords, and similar values in debug surfaces.

## Verification

- Run `flutter analyze` after Dart changes when practical.
- Run `flutter test` for broad verification, or a focused `flutter test <path>` when the change is narrow.
- Use `flutter test integration_test` only when the task needs full UI flow coverage; it is intentionally not part of required PR checks.
- Report every verification command run and clearly note skipped checks or failures.

## Do Not

- Do not perform broad refactors while solving a narrow bug.
- Do not introduce new state management patterns unless the task requires it.
- Do not change formatting mechanically across unrelated files.
- Do not change repository metadata, branches, commits, tags, or remotes unless explicitly requested.
