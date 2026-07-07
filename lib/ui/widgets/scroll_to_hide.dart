import 'package:flutter/material.dart';

import '../../utils/insets.dart';

class ScrollToHideWidget extends StatelessWidget {
  const ScrollToHideWidget({
    super.key,
    required this.isVisible,
    required this.child,
  });
  final Widget child;
  final bool isVisible;

  static double visibleHeight(BuildContext context) =>
      80.0 + bottomNavInset(context);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: isVisible ? visibleHeight(context) : 0.0,
      child: child,
    );
  }
}
