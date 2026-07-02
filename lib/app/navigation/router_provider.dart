import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ui/home.dart';
import 'app_navigator.dart';
import 'app_routes.dart';

final appRouterProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    navigatorKey: AppNavigator.rootNavigatorKey,
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        builder: (context, state) => const Home(),
      ),
    ],
  ),
);
