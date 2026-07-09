import 'package:flutter/material.dart';

/// Applies Harmony's shared readable text and transparent-action styling.
ThemeData applyHarmonyTextAndActionTheme(ThemeData baseTheme) {
  final foregroundColor = baseTheme.colorScheme.onSurface;
  final disabledForegroundColor = foregroundColor.withValues(alpha: 0.38);
  final textTheme = baseTheme.textTheme.apply(
    fontFamily: 'Inter',
    displayColor: foregroundColor,
    bodyColor: foregroundColor,
  );

  return baseTheme.copyWith(
    textTheme: textTheme,
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: foregroundColor,
        disabledForegroundColor: disabledForegroundColor,
        textStyle: textTheme.titleMedium,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: foregroundColor,
        disabledForegroundColor: disabledForegroundColor,
      ),
    ),
  );
}
