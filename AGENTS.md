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

## Playback & State Management
- **Transition Safety**: Always call `_player.stop()` before `_playList.clear()` in `AudioHandler` to prevent `just_audio` race conditions that lead to "stuck loading" states.
- **Loading Indicators**: Ensure `isSongLoading` is reset to `false` in `try-catch` blocks during playback initialization.
- **Testing Playback**: Use `MockAudioPlayer` for playback logic tests to avoid hardware dependency in headless environments.

## Commit Message Guidelines
- **Format**: Always start commit messages with an **Uppercase** letter.
- **Style**: Avoid prefixes like `feat:`, `fix:`, or `refactor:`.
- **Detail**: Focus on the "why" and provide a concise summary of key changes.

## Smart Filter Syntax (Library/Collection)
- **Union (OR)**: Use `,` to search for multiple terms (e.g., `Artist A, Artist B`). Matches if any term is found.
- **Exclusion (NOT)**: Use `!` prefix to exclude terms (e.g., `!live`). Overrides inclusions.
- **Scoped Search**: Use prefixes to target specific fields:
  - `a:` or `artist:` for artist names (e.g., `a:Linkin Park`).
  - `t:` or `title:` for song/album titles (e.g., `t:Numb`).
- **Combined**: Combine for advanced filtering (e.g., `Rock, !live, t:Numb`).

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
    *   **I/O Streaming**: Always use streaming (Streams/Isolates) for backups or large file operations to maintain a small memory footprint (<100MB).
    *   **User Feedback**: Any background task exceeding 1 second must provide granular progress updates via GetX observables and reactive UI (Obx).
    *   **Memory Safety**: Avoid reading large files into memory using `readAsBytesSync` on the main thread; use Isolates for data-heavy operations.
