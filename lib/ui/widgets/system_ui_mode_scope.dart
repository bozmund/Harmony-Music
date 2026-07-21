import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/service_providers.dart';
import '../../services/system_ui_mode_service.dart';

class SystemUiModeScope extends ConsumerStatefulWidget {
  const SystemUiModeScope({
    super.key,
    required this.mode,
    required this.child,
    this.active = true,
    this.priority = SystemUiModePriority.route,
  });

  const SystemUiModeScope.edgeToEdge({
    super.key,
    required this.child,
    this.active = true,
    this.priority = SystemUiModePriority.route,
  }) : mode = SystemUiMode.edgeToEdge;

  const SystemUiModeScope.immersive({
    super.key,
    required this.child,
    this.active = true,
    this.priority = SystemUiModePriority.player,
  }) : mode = SystemUiMode.immersive;

  final SystemUiMode mode;
  final bool active;
  final int priority;
  final Widget child;

  @override
  ConsumerState<SystemUiModeScope> createState() => _SystemUiModeScopeState();
}

class _SystemUiModeScopeState extends ConsumerState<SystemUiModeScope>
    with WidgetsBindingObserver {
  final Object _owner = Object();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncRequest();
  }

  @override
  void didUpdateWidget(SystemUiModeScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode ||
        oldWidget.active != widget.active ||
        oldWidget.priority != widget.priority) {
      _syncRequest();
      if (oldWidget.active &&
          !widget.active &&
          oldWidget.mode == SystemUiMode.immersive) {
        // Android can apply the last immersive window flags after the
        // portrait rotation finishes. Queue a second edge-to-edge assertion
        // after the transition settles; release builds reach this race more
        // often because their frame timing is faster than debug builds.
        unawaited(ref.read(systemUiModeServiceProvider).reapplyCurrentMode());
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) {
      unawaited(ref.read(systemUiModeServiceProvider).reapplyCurrentMode());
    }
  }

  @override
  void didChangeMetrics() {
    if (!widget.active) return;
    // Android finishes applying rotation window flags after Flutter receives
    // its first metrics update. Reapply after that handoff so a portrait
    // window cannot remain in the landscape player's immersive state.
    unawaited(_reapplyAfterMetrics());
  }

  Future<void> _reapplyAfterMetrics() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!mounted || !widget.active) return;
    await ref.read(systemUiModeServiceProvider).reapplyCurrentMode();
  }

  @override
  void dispose() {
    ref.read(systemUiModeServiceProvider).unregisterRequest(_owner);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _syncRequest() {
    final service = ref.read(systemUiModeServiceProvider);
    if (widget.active) {
      service.registerRequest(
        owner: _owner,
        mode: widget.mode,
        priority: widget.priority,
      );
    } else {
      service.unregisterRequest(_owner);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
