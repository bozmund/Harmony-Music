# Welcome Screen Implementation Plan

## Overview
Add a Welcome/Onboarding screen that shows on first launch of the app. This screen will introduce users to Harmony Music's key features and guide them through initial setup.

## Implementation Plan

### 1. Add First Launch Preference Key
- Add `hasSeenWelcomeScreen` key to `PrefKeys` in `lib/services/constant.dart`
- Add getter/setter methods in `SettingsRepository` interface and `HiveSettingsRepository` implementation

### 2. Create Welcome Screen
- Create `lib/ui/screens/Welcome/welcome_screen.dart` with onboarding UI
- Include key features: YouTube Music streaming, offline downloads, library management, background play, etc.
- Add "Get Started" button to dismiss and navigate to home
- Include localization strings in `app_en.arb` and `app_hr.arb`

### 3. Update Router
- Add welcome route to `app_routes.dart`
- Update `router_provider.dart` to show welcome screen on first launch
- Use a redirect in GoRouter to check first launch preference

### 4. Update Settings Repository
- Add `getHasSeenWelcomeScreen()` and `setHasSeenWelcomeScreen()` methods
- Initialize default value in `seedDefaults()`

### 5. Localization
- Add English strings to `lib/l10n/app_en.arb`
- Add Croatian strings to `lib/l10n/app_hr.arb`
- Run `flutter gen-l10n` after changes

### 6. Testing
- Run `flutter analyze`
- Run targeted tests
- Verify first launch shows welcome screen, subsequent launches go directly to home

## Files to Create/Modify
1. `lib/services/constant.dart` - Add PrefKeys entry
2. `lib/domain/repositories/settings_repository.dart` - Add interface methods
3. `lib/data/repositories/hive_settings_repository.dart` - Add implementation
4. `lib/app/navigation/app_routes.dart` - Add welcome route
3. `lib/app/navigation/router_provider.dart` - Add redirect logic
4. `lib/ui/screens/Welcome/welcome_screen.dart` - New welcome screen widget
5. `lib/l10n/app_en.arb` - English strings
6. `lib/l10n/app_hr.arb` - Croatian strings
7. Run `flutter gen-l10n`