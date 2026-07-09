import 'package:flutter/widgets.dart';

import '../../utils/insets.dart';

const double compactBottomNavBarHeight = 64.0;
const double compactMiniPlayerHeight = 75.0;
const double wideMiniPlayerHeight = 105.0;

double bottomNavBarVisibleHeight(BuildContext context) {
  return bottomNavBarVisibleHeightForInset(bottomNavInset(context));
}

double bottomNavBarVisibleHeightForInset(double bottomInset) {
  return compactBottomNavBarHeight + bottomInset;
}

double miniPlayerBaseHeight({required bool isWideScreen}) {
  return isWideScreen ? wideMiniPlayerHeight : compactMiniPlayerHeight;
}

double collapsedMiniPlayerHeight(
  BuildContext context, {
  required bool isWideScreen,
  required bool bottomNavVisible,
}) {
  return collapsedMiniPlayerHeightForInset(
    bottomInset: bottomNavInset(context),
    isWideScreen: isWideScreen,
    bottomNavVisible: bottomNavVisible,
  );
}

double collapsedMiniPlayerHeightForInset({
  required double bottomInset,
  required bool isWideScreen,
  required bool bottomNavVisible,
}) {
  final baseHeight = miniPlayerBaseHeight(isWideScreen: isWideScreen);
  final reservedBottomHeight = bottomNavVisible
      ? bottomNavBarVisibleHeightForInset(bottomInset)
      : bottomInset;
  return baseHeight + reservedBottomHeight;
}
