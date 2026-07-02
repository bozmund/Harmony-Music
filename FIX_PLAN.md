# Fix Plan for Uncommitted Changes

## Situation

The working tree has 9 files with real changes plus ~570 files that differ only by line endings (CRLF/LF noise). The real changes fall into 4 groups. Only group A works.

- **A. Prev goes to end of playlist on first song** — WORKS, keep as-is
- **B. Radio loading indicator (`isRadioLoading`)** — broken
- **C. Player panel open/close behavior** — broken
- **D. Album screen sliver rewrite** — broken

---

## A. Prev-to-end-of-queue (keep, no action)

Files: `lib/services/audio_handler.dart`, `test/audio_handler_source_swap_test.dart`, and the prev-button enable condition in `lib/ui/player/components/mini_player.dart`.

`_getPrevSongIndex()` now wraps to `queue.value.length - 1` when `queueLoopModeEnabled`, and the mini player no longer disables the prev button on the first song when shuffle or queue-loop is on. Correct and consistent. Keep.

---

## B. Radio loading indicator — root cause and fix

### Root cause

`_beginRadioLoading()` is called in `pushSongToQueue` *before* any playback starts. But the playback-state listener clears it on **any non-playing state**:

```dart
// lib/ui/player/player_controller.dart, _listenForChangesInPlayerState()
if (!isPlaying ||
    processingState == AudioProcessingState.completed ||
    processingState == AudioProcessingState.error) {
  _clearPendingSourceStart();
  _clearRadioLoading();   // <-- BUG
}
```

While the radio queue is being fetched, nothing is playing, so `playbackState` keeps emitting `playing == false`. The very next emission (triggered by `updateQueue` broadcasting state) wipes the loading flag milliseconds after it was set. Result: the spinner never appears (or flickers once).

Secondary issue: `_beginRadioLoading()` sets `PlayButtonState.loading`, but the same listener immediately overwrites `buttonState` with `paused` based on the real (idle) player state, so the play button spinner is also lost.

### Fix

1. In `_listenForChangesInPlayerState`, only clear radio loading on terminal states, never on `!isPlaying`:

```dart
if (!isPlaying ||
    processingState == AudioProcessingState.completed ||
    processingState == AudioProcessingState.error) {
  _clearPendingSourceStart();
}
if (processingState == AudioProcessingState.completed ||
    processingState == AudioProcessingState.error) {
  _clearRadioLoading();
}
```

2. While `isRadioLoading` is true, don't let the playback-state listener downgrade the button state (keep it at `loading`):

```dart
void _setButtonStateFromPlayer(PlayButtonState state) {
  if (isRadioLoading.value && state != PlayButtonState.playing) return;
  _setButtonState(state);
}
```

(or an equivalent guard inside the existing listener).

3. Keep the existing clear points — they are correct:
   - new `mediaItem` arrives (first radio track resolved)
   - `mediaItem == null`
   - `playError` custom event
   - catch-block in `pushSongToQueue`
   - `playPlayListSong` (user starts normal playback)

4. Add a safety timeout (e.g. 30 s) that clears loading if nothing ever resolves, so the mini player can't get stuck showing "Random Radio" forever.

Files touched: `lib/ui/player/player_controller.dart` only. The UI wiring in `mini_player.dart`, `player_control.dart`, `library_combined.dart` is fine once the flag actually stays set.

---

## C. Panel open behavior — root cause and fix

Two sub-changes were made:

### C1. `_playerPanelCheck` reorder — correct in principle, keep

Old code called `playerPanelController.open()` *before* `playerPanelMinHeight` was set, so on the very first play the panel opened from height 0. Setting the min height (+ `_notifyPlayerChanged()`) first, then auto-opening, is the right order. Keep, but remove the duplicated trailing `_notifyPlayerChanged()` (it now runs twice when the init branch executes).

### C2. `home.dart` `onPanelOpened` / `onPanelClosed` callbacks — remove

```dart
onPanelOpened: () { playerController.isPanelGTHOpened.value = true; },
onPanelClosed: () {
  playerController.panelListener(0);
  playerController.isPanelGTHOpened.value = false;
},
```

`SlidingUpPanel` already invokes `onPanelSlide` continuously during both drag and programmatic `open()`/`close()` animations, and `panelListener(x)` already sets `isPanelGTHOpened` (x > 0.6) and top visibility/opacity. These callbacks are redundant and can fight the slide listener: `onPanelClosed → panelListener(0)` forces opacity to 1 and `topVisible = true` in the same frame the slide listener processed, causing visible flicker of the mini player, and `onPanelOpened` firing after an interrupted drag can leave `isPanelGTHOpened` stuck true while the panel is mid-position.

**Fix:** delete both callbacks from `home.dart`; keep C1 (with the duplicate notify removed). If the original symptom C was trying to solve reappears, treat it separately with a reproduction — don't patch state from two places.

---

## D. Album screen rewrite — recommend revert, then redo properly

The Stack → `CustomScrollView`/`SliverAppBar` rewrite (~835 lines changed) has several concrete defects:

1. **Double parallax / disappearing artwork.** The artwork lives in `flexibleSpace` and is *additionally* shifted by `Transform.translate(offset: Offset(0, -scrollOffset))`. The SliverAppBar already collapses with scroll, so the image moves at ~2× scroll speed and vanishes almost immediately.

2. **Broken spacing.** The action-button row is wrapped in `Padding(top: 200, bottom: 200)`. In the old Stack layout content overlapped the artwork, so a 200 top offset made sense; in the sliver layout content starts *below* the app bar, so this produces a ~200 px gap above the buttons and another 200 px of blank space before the album title.

3. **Oversized flexibleSpace.** The `Positioned` child is 420 px tall inside an app bar whose `expandedHeight` is 280 px — the bottom 140 px is clipped, and the fade gradient's midpoint lands in the wrong place.

4. **Performance.** `albumController.scrollOffset.value` is written on every scroll notification and the `AnimatedBuilder` wrapping the *entire* `CustomScrollView` listens to the controller — the whole scroll view rebuilds every frame during scroll.

5. **Stale thresholds.** The `appBarTitleVisible` offsets (270 / 225) were tuned for the old layout's scroll metrics.

### Fix plan

**Step 1 — revert `lib/ui/screens/Album/album_screen.dart` to HEAD** (the committed Stack version works).

**Step 2 — redo the sliver conversion as its own change**, with these rules:

- Put the artwork in `FlexibleSpaceBar(background: ...)` (or a `LayoutBuilder`-based flexibleSpace) and let the SliverAppBar drive the collapse. No manual `Transform.translate` from scroll offset.
- Size the artwork to the app bar (`expandedHeight`), not a fixed 420 px; apply the fade gradient over that box.
- Remove the 200/200 padding; content after the app bar needs only normal spacing (e.g. 10–20 px).
- Drive app-bar title visibility from the SliverAppBar collapse itself (e.g. `LayoutBuilder` in flexibleSpace comparing `constraints.maxHeight` to `kToolbarHeight`) instead of raw pixel thresholds, so it works in both orientations without magic numbers.
- Don't rebuild the `CustomScrollView` on scroll: scope any scroll-dependent widget to its own `AnimatedBuilder`/`ValueListenableBuilder`, or drop `scrollOffset` tracking entirely once FlexibleSpaceBar handles the parallax.
- Verify: portrait + landscape, search mode (`isSearchingOn` collapsing the header to 80), empty album, long album (scroll to bottom), download-progress icon states.

---

## E. Library header height (`library_combined.dart`)

`_LibraryHeader` changed from fixed `height: 85`, `top: 45` to `viewPadding.top + 8` / `+48`. This is a sensible safe-area fix but on devices with a small/zero status bar inset (desktop, some tablets) the header shrinks from 85 to ~56 px, which may look cramped. Suggested guard:

```dart
final topPadding = math.max(mediaQuery.viewPadding.top + 8, 20.0);
final headerHeight = topPadding + 48;
```

Keep the `miniPlayerHeight` change (it correctly reserves space when `isRadioLoading` shows the mini player) — it depends on group B being fixed.

---

## Line-ending normalization

Add `.gitattributes`:

```gitattributes
* text=auto
*.dart text eol=lf
*.yaml text eol=lf
*.yml text eol=lf
*.json text eol=lf
*.md text eol=lf
*.sh text eol=lf
*.gradle text eol=lf
*.kt text eol=lf
*.java text eol=lf
*.xml text eol=lf
*.bat text eol=crlf
*.ps1 text eol=crlf
*.sln text eol=crlf
*.rc text eol=crlf
*.png binary
*.jpg binary
*.ico binary
*.ttf binary
*.pem binary
```

Then:

```bash
git add .gitattributes
git add --renormalize .
git status   # only the 9 real files + .gitattributes should remain
```

Do this **first** so the real diffs become reviewable.

---

## Execution order

1. `.gitattributes` + renormalize (kills the 570-file noise)
2. Commit group A (prev-to-end fix + test + mini-player button condition)
3. Fix B in `player_controller.dart` (clear only on terminal states, button-state guard, timeout) — verify spinner shows during radio start and clears when the first track plays or on error
4. Fix C: keep the `_playerPanelCheck` reorder, remove duplicate notify, delete the `home.dart` panel callbacks — verify first-play panel opens at correct height and mini player doesn't flicker on close
5. Revert `album_screen.dart` to HEAD; redo the sliver rewrite per the checklist in D as a separate commit
6. Apply the E guard, run `flutter analyze` + the test suite (`audio_handler_source_swap_test`, `player_controller_queue_order_test`)
