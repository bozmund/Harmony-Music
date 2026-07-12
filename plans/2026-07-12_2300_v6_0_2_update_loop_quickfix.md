# v6.0.2 Update-Loop Quickfix

## Summary

Publish `v6.0.2` through a dedicated branch and PR. The APK will identify itself as `6.0.2+30`, so users on the mislabeled `v6.0.1` build (`6.0.0+29` internally) receive one legitimate update and stop seeing it afterward.

## Implementation Changes

- Create an isolated quickfix branch from current `main`, keeping the existing resolver/Party-mode working tree changes out of the release fix.
- Change `pubspec.yaml` to `version: 6.0.2+30`.
- Harden `.github/workflows/android_release.yml` for stable tag builds:
  - Parse the release tag (`vX.Y.Z`) and the semantic portion of `pubspec.yaml` (`X.Y.Z`).
  - Fail before the APK build if they differ.
  - Use the validated `pubspec.yaml` version as `BUILD_VERSION`.
- Add focused update-check tests covering equal versions and a newer stable tag, ensuring `v6.0.2` is not offered to an internally versioned `6.0.2` build.
- Open a PR, run the existing checks, merge only after review, then create and push tag `v6.0.2` to trigger the production APK workflow.
- Do not rewrite or replace the existing `v6.0.1` release.

## Test Plan

- `flutter analyze`
- Focused update-check tests and full `flutter test`
- Confirm the workflow rejects a deliberately mismatched tag/version pair through a shell validation test or workflow-level check.
- After publishing, verify the release asset reports `6.0.2+30` in app diagnostics and that:
  - the old `v6.0.1` APK offers `v6.0.2`;
  - the corrected `v6.0.2` APK reports no stable update.

## Assumptions

- `v6.0.2+30` is the next Android version code.
- The PR targets `main`; the tag is created only after the PR is merged.
- The existing `v6.0.1` artifact remains untouched for traceability.
