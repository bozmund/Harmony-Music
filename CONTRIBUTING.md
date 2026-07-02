# Contributing To Harmony Music

Thanks for helping with Harmony Music. This repo has a few local dependencies
that are required before `flutter pub get` will work, so use the setup steps
below instead of copying only the `lib/` folder or downloading a partial tree.

## Clone The Full Repository

Use a normal Git clone with submodules:

```powershell
git clone --recurse-submodules <repo-url>
cd Harmony-Music
```

If you already cloned the repo without submodules, run:

```powershell
git submodule update --init --recursive
```

The `.flutter` directory is a Git submodule. It provides the Flutter SDK version
used by this repository.

## Required Vendored Packages

The app uses local path dependencies from `third_party/`:

- `third_party/audio_service`
- `third_party/just_audio`
- `third_party/youtube_explode_dart`

These directories are normal tracked files in this repository, not submodules.
Anyone who clones the full repo should receive them automatically.

If `flutter pub get` says one of these paths does not exist, the checkout is
incomplete. Fix it by cloning the full repo again, or make sure the branch you
are using contains the tracked `third_party/` files.

Do not replace these packages with pub.dev versions unless a task explicitly
requires that migration. They are custom vendored copies used by the app.

## Use The Repo Flutter SDK

On Windows, prefer the checked-out Flutter SDK:

```powershell
.\.flutter\bin\flutter.bat --version
.\.flutter\bin\flutter.bat pub get
```

On Linux/macOS:

```bash
./.flutter/bin/flutter --version
./.flutter/bin/flutter pub get
```

Using the repo SDK avoids "works on my machine" issues from different Flutter
or Dart versions.

## Verify The App

Run analyzer before sending a change:

```powershell
.\.flutter\bin\flutter.bat analyze
```

Run tests relevant to your change. For core playback changes, run:

```powershell
.\.flutter\bin\flutter.bat test test/audio_handler_source_swap_test.dart
```

For broader changes, run:

```powershell
.\.flutter\bin\flutter.bat test
```

## Common Setup Problems

### Missing `third_party/...`

Cause: incomplete checkout, wrong branch, or files were not pushed to the
remote.

Fix:

```powershell
git status
git pull
git submodule update --init --recursive
```

If the folders are still missing, ask the maintainer to push the vendored
`third_party/` directories.

### Missing `.flutter/bin/flutter`

Cause: submodule was not initialized.

Fix:

```powershell
git submodule update --init --recursive
```

### Pub Gets The Wrong Packages

Cause: `pubspec.yaml` uses local path dependencies for some packages and Git
dependencies for others. Do not manually edit those dependency sources during
setup.

Fix:

```powershell
.\.flutter\bin\flutter.bat clean
.\.flutter\bin\flutter.bat pub get
```

## Before Opening A Pull Request

1. Make sure your checkout includes `.flutter` and all `third_party/` packages.
2. Run `.\.flutter\bin\flutter.bat pub get`.
3. Run `.\.flutter\bin\flutter.bat analyze`.
4. Run focused tests for the area you changed.
5. Describe what changed, why, and which commands passed.

## Notes For Maintainers

To make the repo easy for friends and contributors:

- Keep `third_party/` committed and pushed.
- Keep `.gitmodules` committed so `.flutter` can be initialized.
- Prefer documenting custom dependency changes in this file.
- Avoid requiring private files or local-only packages for normal development.
