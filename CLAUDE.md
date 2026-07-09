# CLAUDE.md

## Accepted Plans

Before implementing an explicitly accepted plan, save its full accepted content as a timestamped Markdown file in the repository-root `plans/` directory.

## Flutter/Dart MCP server

This repo ships a small dependency-free MCP stdio server at `mcp/flutter_dart_server.js`
that exposes the repo-local Flutter SDK (`.flutter/`) as two tools:

- `flutter` — runs `.flutter/bin/flutter(.bat) <args>` in the repo (or a workspace-relative
  `working_directory`)
- `dart` — runs `.flutter/bin/dart(.bat) <args>` the same way

It's registered as a project MCP server in `.mcp.json` (server name `harmony-flutter-dart`).
After `.mcp.json` changes, the session needs to be restarted/reloaded (and the new project
server approved) before these tools are actually callable.

**Prefer these tools over raw Bash calls to `.flutter\bin\flutter.bat` / `dart.bat`** once
connected — e.g. `flutter({args: ["analyze", "--no-pub"]})`, `flutter({args: ["test"]})`,
`dart({args: ["format", "lib/..."]})`.

**Always pass `timeout_ms: 600000`** (the tool's own cap). The default (120000) is too short
for this repo — `flutter analyze` and `flutter test` here routinely run several minutes,
sometimes longer on a cold analyzer-server start. A timed-out call still returns whatever
stdout was captured (check it before assuming failure), but the exit code is lost, so just
budget the full 600s up front instead of retrying.

**Still bound by the standing rule: never run, launch, attach to, or otherwise control the
app on a device or emulator, and never touch adb.** This server is a raw passthrough with no
subcommand allowlist — it will execute `flutter run` / `flutter devices` / `flutter attach` /
`flutter install` / `flutter drive` if asked. Do not pass those subcommands (or anything
device/emulator-related) through it. Only `analyze`, `test`, `format`, `fix`, `pub`, and
similarly inert subcommands are in scope. The user builds, runs, and tests the app themselves
on their own devices.
