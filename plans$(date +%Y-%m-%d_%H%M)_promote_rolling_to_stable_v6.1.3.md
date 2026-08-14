# Promote current rolling build to stable (tag v6.1.3)

## Context

The rolling channel (`main-latest` prerelease, rebuilt on every push to `main`
per `docs/release_process.md`) is currently at commit `80ad40a`, matching
`pubspec.yaml`'s `version: 6.1.3+32`. The user wants this exact build promoted
to the **stable** channel by pushing the version tag CI watches for
(`docs/release_process.md` → "Stable: create and push a version tag").

The user explicitly confirmed:
- The stable version should be the **current rolling build's version**
  (`6.1.3`), not a further minor/patch bump.
- **No pubspec.yaml or CHANGELOG.md edits**, and no commits — only push the
  tag against the existing commit.

## Plan

1. Confirm `origin/main` HEAD is still `80ad40abe0e00d8fcd185885a8474b5ebe3d8f2d`
   and that tag `v6.1.3` doesn't already exist (both already verified during
   planning; re-check immediately before tagging in case `main` moved).
2. Create an annotated tag `v6.1.3` on commit `80ad40abe0e00d8fcd185885a8474b5ebe3d8f2d`:
   ```
   git tag v6.1.3 80ad40abe0e00d8fcd185885a8474b5ebe3d8f2d
   ```
3. Push the tag to `origin`:
   ```
   git push origin v6.1.3
   ```
4. Verify: `gh release view v6.1.3` (or watch the Actions run) to confirm CI
   picked up the tag, built the signed APK with `pubspec.yaml`'s version
   (`6.1.3+32`), and published a GitHub release marked "latest" per the
   pipeline in `.github/workflows/android_release.yml`.

No other files are touched — this is tag-and-push only, using the existing
working tree state (which is otherwise untouched and unrelated to this task).
