# Toggle Icon Button Standardization

**Date:** 2026-07-10

## Problem

The listen-together button in `standard_player.dart` uses `colorScheme.primary` for its active color, but it sits on a `primaryColor` background — making it nearly invisible when active (looks disabled). The existing shuffle/loop buttons in `player_control.dart`, `mini_player.dart`, and `gesture_player.dart` all repeat the same inline color math manually: `textTheme.titleLarge!.color` (active) vs `.withValues(alpha: 0.2)` (inactive). This repetition is error-prone.

## Solution

1. **New widget** `ToggleIconButton` in `lib/ui/widgets/toggle_icon_button.dart` — encapsulates the active/inactive pattern once.
2. **Documentation** `docs/component_guide.md` — lists all reusable UI widgets.
3. **Migrate** 4 call sites to use the new widget (fixes the listen-together bug).
4. **Reference** in `AGENTS.md`.

### Files changed

| Action | File |
|---|---|
| CREATE | `lib/ui/widgets/toggle_icon_button.dart` |
| CREATE | `docs/component_guide.md` |
| EDIT | `lib/ui/player/components/standard_player.dart` |
| EDIT | `lib/ui/player/components/player_control.dart` |
| EDIT | `lib/ui/player/components/mini_player.dart` |
| EDIT | `lib/ui/player/components/gesture_player.dart` |
| EDIT | `AGENTS.md` |

### Verification

- `flutter analyze` passes.
- Listen-together button uses a high-contrast text color, not `colorScheme.primary`.