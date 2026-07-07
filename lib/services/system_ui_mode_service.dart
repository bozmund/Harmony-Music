import 'dart:async';

import 'package:flutter/services.dart';

class SystemUiModePriority {
  const SystemUiModePriority._();

  static const route = 0;
  static const player = 100;
}

class SystemUiModeService {
  final Map<Object, _SystemUiModeRequest> _requests = {};
  int _nextSequence = 0;
  SystemUiMode? _currentMode;
  Future<void> _pendingApply = Future<void>.value();

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

  Future<void> reapplyCurrentMode() => _scheduleApply(force: true);

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
      if (selected == null ||
          request.priority > selected.priority ||
          (request.priority == selected.priority &&
              request.sequence > selected.sequence)) {
        selected = request;
      }
    }
    return selected?.mode;
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
