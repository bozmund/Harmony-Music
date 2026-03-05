# Harmony Music - Agent Guidelines

This document provides essential information for AI agents working on the Harmony Music repository.

## Commands & Workflow Constraints

### Build & Test Policy
- **CRITICAL**: Do NOT execute build or test commands yourself. 
- The user will manually handle all building and testing. 
- Stop your workflow before these steps and inform the user.
- **LOCALIZATION**: Ignore all `.arb` and `lib/utils/get_localization.dart` files. Do not attempt to modify them as they are managed externally or auto-generated.

### Environment Setup
- **Dependencies**: `flutter pub get`
- **Clean**: `flutter clean`

### Verification (Informational Only)
- **Linting**: `flutter analyze`
- **Testing (All)**: `flutter test`
- **Single Test**: `flutter test test/path_to_test_file.dart`

### Building (Informational Only)
- **Android**: `flutter build apk`
- **Windows**: `flutter build windows`
- **Linux**: `flutter build linux`

## Code Style & Architecture

### Technology Stack
- **Framework**: Flutter (Dart SDK >=3.1.5 <4.0.0)
- **State Management**: GetX (`GetxController`, `Get.put`, `Get.find`, `Obx`)
- **Storage**: Hive (Local NoSQL DB)
- **Audio**: `just_audio` (Android), `media_kit` (Desktop), `audio_service` (Background)

### Project Structure
- `lib/models/`: Data models with serialization logic.
- `lib/services/`: Business logic and external API interactions (e.g., `MusicServices`).
- `lib/ui/screens/`: Feature-specific screens and their GetX controllers.
- `lib/ui/widgets/`: Reusable UI components.
- `lib/utils/`: Shared helper functions and constants.

### Naming Conventions
- **Classes**: `PascalCase` (e.g., `MusicServices`, `PlayerController`)
- **Variables/Methods**: `camelCase` (e.g., `themeModetype`, `onInit()`)
- **Files**: `snake_case.dart` (e.g., `settings_screen.dart`)
- **Controllers**: Suffix with `Controller` (e.g., `HomeScreenController`)

### Import Style
- Prefer relative imports for local files: `import '../../widgets/common_dialog_widget.dart';`
- Root-relative imports are also used: `import '/services/music_service.dart';`
- Use package imports for external dependencies: `import 'package:get/get.dart';`

### Types & Formatting
- **Static Typing**: Explicitly type variables and function return values. Avoid `dynamic` unless necessary.
- **Null Safety**: Always use null-safe types (`String?`, `int?`).
- **Lints**: Adhere to `flutter_lints` rules defined in `analysis_options.yaml`.

### State Management (GetX)
- Use `Obx(() => ...)` for reactive UI updates.
- Keep business logic in `GetxController` subclasses.
- Access controllers via `Get.find<ControllerType>()` or `Get.put()`.

### Platform Considerations
- Use `GetPlatform.isAndroid`, `GetPlatform.isDesktop`, etc., for platform-specific logic.
- Desktop (Windows/Linux) uses `media_kit`, while Android uses `just_audio`.

### Error Handling
- Use `try-catch` blocks for asynchronous operations (network, I/O).
- Use `printINFO`, `printERROR` (from `helper.dart`) or `debugPrint` for logging.

## Core Mandates
1. **Cross-Platform First**: Ensure changes work on Android, Windows, and Linux.
2. **No Breaking Changes**: Maintain compatibility with the custom `youtube_explode_dart` fork.
3. **Open Source**: Harmony Music is GPL v3.0; keep all code open.
4. **Performance**: Optimize for low resource usage in music streaming and caching.
