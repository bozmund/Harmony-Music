# Release Process

This documents how Harmony Music (this fork, `bozmund/Harmony-Music`) is
versioned and released. The pipeline lives in
`.github/workflows/android_release.yml`; this file explains how to drive it.

## Update channels

The app has two update channels (Settings → Update channel). Since 6.0.0 the
default is **stable**; on first launch of 6.0.0 every user is asked once to
pick a channel (see `lib/services/release_prompt.dart`).

| Channel | What users get | Published by |
| --- | --- | --- |
| **stable** | Versioned releases (`v6.0.0`, `v6.1.0`, …). The app compares its version against the repo's `v*` tags. | Pushing a `v*` git tag |
| **rolling** | The `main-latest` prerelease, rebuilt automatically on **every push to main**. The app compares build SHAs. | Automatic on push to main |

## How to publish

- **Rolling**: just push (or merge) to `main`. CI builds a signed APK and
  force-updates the `main-latest` tag + prerelease. Nothing else to do.
- **Stable**: create and push a version tag — this is the release flag:

  ```bash
  git tag v6.0.0
  git push origin v6.0.0
  ```

  CI builds a signed APK with the version from `pubspec.yaml` and publishes a
  GitHub release marked *latest*. The tag version and pubspec version should
  match — bump pubspec first, in the tagged commit.

## Versioning scheme

`pubspec.yaml` `version: <name>+<code>` is the single source of truth.
`<name>` is the user-visible semver, `<code>` is the Android versionCode and
must increase whenever a build should be installable over a previous one.

Semver positions are owned by release type:

- **Major** (`6`.0.0) — bumped manually for milestone releases.
- **Minor** (6.`1`.x) — bumped for each **stable** release.
- **Patch** (6.x.`1`) — reserved for **rolling** builds.

So a stable release is cut as `6.1.0`, `6.2.0`, …; rolling builds between
stable releases conceptually advance the patch position.

### Planned automation (not yet implemented)

Currently both the pubspec bump and the tag are manual. The intended follow-up
is to let the pipeline do the bumping:

- Stable: a manually triggered workflow increments the **minor** version in
  pubspec, commits, tags `v<version>`, and publishes — one click per release.
- Rolling: each main build stamps an incremented **patch** version (and a
  monotonically increasing versionCode, e.g. derived from the CI run number)
  into the build without committing back.

Until then: bump `pubspec.yaml` by hand (both the version name and the `+`
build number) in the release commit, then push the `v*` tag.

## Release checklist (stable)

1. `flutter analyze --no-pub` and `flutter test` are green on main.
2. Run the manual playback checklist:
   `docs/release_candidate_playback_manual_testing.md`.
3. Bump `version:` in `pubspec.yaml` (minor bump, +1 on the build number).
4. Update `CHANGELOG.md`.
5. Commit, push to main, wait for CI to be green.
6. Tag the commit `v<version>` and push the tag.
7. Verify the GitHub release contains the APK and the in-app update check
   offers it on the stable channel.
