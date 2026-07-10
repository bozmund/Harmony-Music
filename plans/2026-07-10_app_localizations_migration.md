# Replace `.tr` with Flutter `AppLocalizations`

Accepted: 2026-07-10

## Summary

Migrate all 453 `.tr` calls across 55 files to Flutter’s generated `AppLocalizations`. English and Croatian remain the supported locales. ARB files become the sole translation source; the legacy JSON generator and custom runtime are removed.

## Implementation changes

1. Reconcile localization sources: move missing English keys to `app_en.arb`, add Croatian equivalents, model dynamic strings with ARB placeholders/plurals/selects, add `context.l10n`, and regenerate.
2. Migrate presentation code: replace widget `.tr` access with typed generated getters, starting with Settings and continuing through all screens and shared widgets.
3. Remove translations from non-UI layers: return typed outcomes from controllers/services, translate in widgets, and inject locale-aware media labels into AudioHandler.
4. Remove the legacy system: delete `get_localization.dart`, JSON sources/generator, replace sync tests, update documentation, and prevent `.tr` regressions.

## Interfaces and behavior

- UI localization API: `context.l10n.<generatedGetter>`.
- Controller/service failures use typed codes or enums mapped by UI code.
- English remains the fallback locale.
- Persisted English/Croatian selection and immediate switching remain unchanged.
- Unsupported historical JSON locales are removed.

## Test plan

- Validate matching ARB keys and placeholders.
- Generate localizations and test English/Croatian widgets and runtime switching.
- Test typed error presentation and AudioHandler labels after locale changes.
- Assert zero `.tr` calls and legacy imports.
- Run `flutter analyze`, focused tests, and the full `flutter test` suite.

## Assumptions

- Only English and Croatian remain supported.
- Wording changes are limited to broken or incomplete translations.
- Migration proceeds in reviewable stages; legacy files are removed only after all call sites move.
