# UI Component Guide

This document catalogs the reusable UI widgets available in the project.
When adding a new UI element, prefer one of these components over writing
inline widgets, so the look and feel stay consistent.

---

## 1. ToggleIconButton

**File:** `lib/ui/widgets/toggle_icon_button.dart`

An `IconButton` that toggles between a filled and outlined icon with the
standard active/inactive color scheme.

| Prop | Type | Description |
|---|---|---|
| `isActive` | `bool` | Whether the toggle is in the on state |
| `activeIcon` | `IconData` | Icon shown when `isActive == true` |
| `inactiveIcon` | `IconData` | Icon shown when `isActive == false` |
| `onPressed` | `VoidCallback?` | Tap callback; `null` disables |
| `size` | `double?` | Optional icon size (default 24) |
| `splashRadius` | `double?` | Optional tap splash radius |
| `tooltip` | `String?` | Optional tooltip |
| `visualDensity` | `VisualDensity?` | Optional compact-layout density |

**Color rule (automatic):** Active = `textTheme.titleLarge.color` (full).
Inactive = same color at 20 % opacity. This works correctly on any
background, including the player's `primaryColor` backdrop.

**Used by:** shuffle (player, mini-player), loop (player, gesture-player),
listen-together button.

---

## 2. AwaitableButton

**File:** `lib/ui/widgets/awaitable_button.dart`

A button that shows a loading spinner while its `onPressed` future is
running, and disables itself during that time. Supports the same variants
as Material buttons.

| Named constructor | Maps to |
|---|---|
| `AwaitableButton.elevated` | `ElevatedButton.icon` |
| `AwaitableButton.filled` | `FilledButton.icon` |
| `AwaitableButton.filledTonal` | `FilledButton.tonalIcon` |
| `AwaitableButton.outlined` | `OutlinedButton.icon` |
| `AwaitableButton.text` | `TextButton.icon` |

Common props: `label`, `icon`, `onPressed`, `style`.

Use whenever a button invocation triggers an async operation (e.g.
starting a listen-together session, exporting data).

---

## 3. AwaitableIconButton

**File:** `lib/ui/widgets/awaitable_button.dart`

Same concept as [AwaitableButton](#2-awaitablebutton) but for
`IconButton`. Variants: `AwaitableIconButton` (standard),
`.filled`, `.filledTonal`, `.outlined`.

Also accepts `isSelected` / `selectedIcon` for selection-state toggling.

Use for icon-only async actions such as the "more" context menu button.

---

## 4. CustomSwitch

**File:** `lib/ui/widgets/custom_switch.dart`

A themed switch widget used in Settings screens. Typically wired to an
`Obx` / observable boolean from a controller.

---

## 5. CustomExpansionTile

A themed expansion tile used in Settings screens for grouped preferences.
No dedicated file — the pattern is used inline. Follow the existing
examples in settings screens.

---

## 6. ProceedButton / CancelButton

**File:** `lib/ui/widgets/custom_button.dart`

Simple convenience wrappers around `InkWell`:
- `ProceedButton` — filled button with text + tap callback.
- `CancelButton` — text-only button that pops the navigator.

Use only inside dialog footers; prefer `AwaitableButton` for new code.

---

## Choosing the right widget

| You need … | Use |
|---|---|
| An icon that toggles on/off (shuffle, loop, etc.) | `ToggleIconButton` |
| A labeled async button | `AwaitableButton.{variant}` |
| An icon-only async button | `AwaitableIconButton.{variant}` |
| A settings toggle | `CustomSwitch` + `Obx` |
| A settings accordion group | `CustomExpansionTile` pattern |
| A simple dialog footer button | `ProceedButton` / `CancelButton` |
