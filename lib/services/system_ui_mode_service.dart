import 'dart:async';

import 'package:flutter/services.dart';

class SystemUiModePriority {
  const SystemUiModePriority._();

  static const route = 0;
  static const player = 100;
}

class SystemUiModeService {
  SystemUiModeService({bool immersiveAllowed = true})
    : _immersiveAllowed = immersiveAllowed;

  final Map<Object, _SystemUiModeRequest> _requests = {};
  int _nextSequence = 0;
  SystemUiMode? _currentMode;
  Future<void> _pendingApply = Future<void>.value();
  bool _immersiveAllowed;

  bool get immersiveAllowed => _immersiveAllowed;

  void setImmersiveAllowed(bool allowed) {
    if (_immersiveAllowed == allowed) return;
    _immersiveAllowed = allowed;
    unawaited(_scheduleApply(force: true));
  }

  void registerRequest({
    required Object owner,
    required SystemUiMode mode,
    required int priority,
  }) {
    _requests[owner] = _SystemUiModeRequest(
      mode: mode,
      priority: priority,
      sequence: _nextSequence++,
    );
    unawaited(_scheduleApply());
  }

  void unregisterRequest(Object owner) {
    final removed = _requests.remove(owner);
    if (removed != null) {
      unawaited(_scheduleApply());
    }
  }

  /// Re-asserts whichever mode is currently resolved (edge-to-edge, or
  /// immersive while the player panel is open). Called on every app resume.
  ///
  /// On Android, the window can regain actual focus slightly *after* the
  /// `resumed` lifecycle callback fires — most noticeably when returning
  /// from the recents/task switcher, and more often in release builds where
  /// the app reattaches faster than the OS settles the window. A
  /// `SystemChrome.setEnabledSystemUIMode` call made in that gap can be
  /// silently overridden once focus actually lands, which shows up as
  /// edge-to-edge getting "stuck" back to showing system bars after resume.
  /// Re-asserting once more shortly after covers that race without
  /// depending on exact platform timing.
  Future<void> reapplyCurrentMode() async {
    await _scheduleApply(force: true);
    await Future.delayed(reapplySettleDelay);
    await _scheduleApply(force: true);
  }

  /// Gap before the second resume reapply; exposed for tests.
  static const reapplySettleDelay = Duration(milliseconds: 300);

  Future<void> _scheduleApply({bool force = false}) {
    _pendingApply = _pendingApply.whenComplete(
      () => _applyResolvedMode(force: force),
    );
    return _pendingApply;
  }

  Future<void> _applyResolvedMode({bool force = false}) async {
    final resolvedMode = _resolveMode();
    if (resolvedMode == null) return;
    if (!force && _currentMode == resolvedMode) return;
    await SystemChrome.setEnabledSystemUIMode(resolvedMode);
    _currentMode = resolvedMode;
  }

  SystemUiMode? _resolveMode() {
    _SystemUiModeRequest? selected;
    for (final request in _requests.values) {
      if (!_immersiveAllowed && _isImmersiveMode(request.mode)) {
        continue;
      }
      if (selected == null ||
          request.priority > selected.priority ||
          (request.priority == selected.priority &&
              request.sequence > selected.sequence)) {
        selected = request;
      }
    }
    return selected?.mode;
  }

  bool _isImmersiveMode(SystemUiMode mode) {
    return mode == SystemUiMode.immersive ||
        mode == SystemUiMode.immersiveSticky;
  }
}

class _SystemUiModeRequest {
  const _SystemUiModeRequest({
    required this.mode,
    required this.priority,
    required this.sequence,
  });

  final SystemUiMode mode;
  final int priority;
  final int sequence;
}
