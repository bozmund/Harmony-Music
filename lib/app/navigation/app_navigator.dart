import 'package:flutter/material.dart';

class AppNavigator {
  AppNavigator._();

  static final rootNavigatorKey = GlobalKey<NavigatorState>();

  static BuildContext? get context => rootNavigatorKey.currentContext;
}
