import 'dart:async';

import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../services/auth0_service.dart';

final auth0ServiceProvider = Provider<Auth0Service>(
  (ref) => Auth0Service.create(),
);

final authControllerProvider = ChangeNotifierProvider<AuthController>((ref) {
  final controller = AuthController(ref.watch(auth0ServiceProvider));
  unawaited(controller.init());
  return controller;
});

class AuthController extends ChangeNotifier {
  AuthController(this._service);

  final Auth0Service _service;
  UserProfile? userProfile;
  bool isBusy = false;
  String? errorMessage;

  bool get isConfigured => _service.isConfigured;
  bool get isSupportedPlatform => _service.isSupportedPlatform;
  bool get isAvailable => _service.isAvailable;
  bool get isAuthenticated => userProfile != null;

  Future<void> init() async {
    userProfile = await _service.tryRestoreSession();
    notifyListeners();
  }

  Future<void> login() async => _run(() async {
    userProfile = await _service.login();
  });

  Future<void> logout() async => _run(() async {
    await _service.logout();
    userProfile = null;
  });

  Future<void> _run(Future<void> Function() action) async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }
}
