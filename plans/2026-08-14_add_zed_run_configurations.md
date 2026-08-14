# Add Zed run configurations mirroring the existing IDE ones

## Context
The repo already has run/debug launch configs for VS Code (`.vscode/launch.json`, 3 configs: debug/profile/release) and Android Studio (`.idea/runConfigurations/Harmony_Music_profile.xml` + an IDE-local "main.dart" config), both targeting the single entry point `lib/main.dart`, no flavors, no `--dart-define`s, no hardcoded device (the IDE's device picker chooses). There is no `.zed/` directory yet. The user wants equivalent Zed run configs so they can launch the app from Zed too.

Zed has no built-in Flutter/Dart debugger (DAP) — that would require installing a third-party extension, which the user declined for now. Instead, Zed's plain **task runner** (`.zed/tasks.json`) will run `flutter run` in a new terminal, same mechanism as invoking it manually, just like the Android Studio configs do (no device flag — `flutter run` will prompt interactively if more than one device is available).

## Change
Create `C:\MyRepositories\Harmony-Music\.zed\tasks.json` with three tasks mirroring the Android Studio / VS Code configs, using the vendored SDK at `.flutter/bin/flutter.bat` (per CLAUDE.md — not relying on `flutter` being on PATH), targeting `lib/main.dart`, no device pinned:

- **Harmony Music** — `flutter run --target lib/main.dart` (debug mode, default)
- **Harmony Music (profile)** — adds `--profile` (matches `.idea/runConfigurations/Harmony_Music_profile.xml`)
- **Harmony Music (release)** — adds `--release` (matches the VS Code release config)

Each task:
- `command`: `.flutter/bin/flutter.bat`
- `use_new_terminal: true`, `reveal: "always"` so the interactive device picker / hot-reload keys are usable
- `allow_concurrent_runs: false` to avoid stacking multiple `flutter run` sessions
- `cwd: "$ZED_WORKTREE_ROOT"` for robustness regardless of which file is focused when the task is triggered

## Verification
Since I can't launch the app myself (per CLAUDE.md), verification is limited to:
- Confirm `.zed/tasks.json` is valid JSON
- Ask the user to open the repo in Zed, run `task: spawn` (or the Tasks panel) and confirm the three "Harmony Music" tasks appear and that triggering one runs `flutter run` in a new terminal pane as expected
