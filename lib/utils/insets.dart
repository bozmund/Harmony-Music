import 'package:flutter/material.dart';

/// Bottom inset reserved for the Android system navigation bar (3-button or
/// gesture). This is the single source of truth for "how tall is the nav bar"
/// across the app.
///
/// Why this exists:
///  * [MediaQuery.of] reads an inset that any ancestor (e.g. a [Scaffold]
///    around its [BottomNavigationBar], or a [SafeArea]) may have already
///    narrowed or zeroed. Sourcing from [MediaQueryData.fromView] keeps the
///    raw OS value even when an ancestor [MediaQuery] consumed padding.
///  * On some devices (notably Samsung One UI under Android 15's enforced
///    edge-to-edge) [viewPadding.bottom] is reported stale or transiently 0
///    right after launch, resume, or an immersive<->edgeToEdge transition.
///    A momentary 0 must not collapse the library offset or mini-player
///    height, so we remember the largest non-zero value seen and floor to it.
double bottomNavInset(BuildContext context) {
  final raw = MediaQueryData.fromView(View.of(context)).viewPadding.bottom;
  if (raw > _maxSeenBottomInset) {
    _maxSeenBottomInset = raw;
  }
  return raw > 0 ? raw : _maxSeenBottomInset;
}

/// Largest non-zero bottom nav inset observed this session. Protected against
/// transient 0 reports during immersive/resume transitions.
double _maxSeenBottomInset = 0.0;
