import 'package:flutter/material.dart';

/// An [IconButton] that toggles between a filled and outlined icon with the
/// standard active/inactive color scheme used across player controls.
///
/// **Active state:**
///   - Shows [activeIcon] in [TextTheme.titleLarge] color (full opacity).
///
/// **Inactive state:**
///   - Shows [inactiveIcon] in the same color at 20 % opacity.
///
/// Use for controls like shuffle, loop, listen-together, and similar
/// toggle-style icon buttons in the player UI.
///
/// ## Example
///
/// ```dart
/// ToggleIconButton(
///   isActive: playerController.isShuffleModeEnabled.value,
///   activeIcon: Icons.shuffle,
///   inactiveIcon: Icons.shuffle,
///   onPressed: () => playerController.toggleShuffleMode(),
///   tooltip: 'Shuffle',
/// )
/// ```
class ToggleIconButton extends StatelessWidget {
  const ToggleIconButton({
    super.key,
    required this.isActive,
    required this.activeIcon,
    required this.inactiveIcon,
    required this.onPressed,
    this.size,
    this.splashRadius,
    this.tooltip,
    this.visualDensity,
  });

  /// Whether the toggle is in the active (on) state.
  final bool isActive;

  /// Icon shown when [isActive] is true.
  final IconData activeIcon;

  /// Icon shown when [isActive] is false.
  final IconData inactiveIcon;

  /// Called when the button is tapped. Set to `null` to disable the button.
  final VoidCallback? onPressed;

  /// Optional icon size. Defaults to the [IconButton] default (24).
  final double? size;

  /// Optional radius for the tap splash.
  final double? splashRadius;

  /// Optional tooltip string.
  final String? tooltip;

  /// Optional density override for compact player layouts.
  final VisualDensity? visualDensity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.textTheme.titleLarge!.color!;
    return IconButton(
      splashRadius: splashRadius,
      visualDensity: visualDensity,
      icon: Icon(
        isActive ? activeIcon : inactiveIcon,
        size: size,
        color: isActive ? color : color.withValues(alpha: 0.2),
      ),
      onPressed: onPressed,
      tooltip: tooltip,
    );
  }
}
