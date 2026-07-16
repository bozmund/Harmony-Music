import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/controller_providers.dart';
import '../../../services/listen_together/listen_together_controller.dart';
import '../../../services/listen_together/session_message.dart';
import '../../../services/listen_together/sync_transport.dart';
import '../../../l10n/l10n.dart';
import '../../widgets/awaitable_button.dart';
import '../../../utils/runtime_platform.dart';
import 'listen_together_transport_selector.dart';

/// Opens the "Listen Together" bottom sheet.
Future<void> showListenTogetherSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 500),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const ListenTogetherSheet(),
  );
}

class ListenTogetherSheet extends ConsumerStatefulWidget {
  const ListenTogetherSheet({super.key});

  @override
  ConsumerState<ListenTogetherSheet> createState() =>
      _ListenTogetherSheetState();
}

class _ListenTogetherSheetState extends ConsumerState<ListenTogetherSheet>
    with WidgetsBindingObserver {
  bool _partyMode = false;
  bool _browsing = false;
  bool _endingSession = false;
  bool _endingSessionWasHost = false;
  Object? _shownTransportError;
  ScaffoldMessengerState? _messenger;
  ModalRoute<dynamic>? _route;

  ListenTogetherController get _controller =>
      ref.read(listenTogetherControllerProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_controller.refreshAvailability());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.refreshAvailability());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
    _route = ModalRoute.of(context);
  }

  Future<bool> _guard(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } catch (error) {
      if (!mounted || _route?.isCurrent != true) return false;
      _messenger?.showSnackBar(SnackBar(content: Text(_failureMessage(error))));
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(listenTogetherControllerProvider);
    final transportError = controller.lastTransportError;
    if (transportError != null && transportError != _shownTransportError) {
      _shownTransportError = transportError;
      controller.clearTransportError();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showTransportError(transportError),
      );
    }
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.groups_2_outlined),
                  const SizedBox(width: 10),
                  Text(
                    context.l10n.listenTogether,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (controller.isActive || _endingSession)
                _activeView(controller)
              else if (_browsing)
                _browseView(controller)
              else
                _menuView(controller),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Idle menu ------------------------------------------------------------

  Widget _menuView(ListenTogetherController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListenTogetherTransportSelector(
          selected: controller.selectedTransport,
          availability: controller.availability,
          isAndroid: RuntimePlatform.isAndroid,
          onSelected: (kind) =>
              unawaited(controller.setSelectedTransport(kind)),
          onRequestPermissions: () =>
              unawaited(_guard(controller.requestBluetoothPermissions)),
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _partyMode,
          onChanged: (value) => setState(() => _partyMode = value),
          title: Text(context.l10n.partyMode),
          subtitle: Text(context.l10n.partyModeDes),
        ),
        const SizedBox(height: 16),
        AwaitableButton.filled(
          onPressed: !controller.selectedTransportReady
              ? null
              : () async {
                  await _guard(
                    () => _controller.startHosting(
                      controller.selectedTransport,
                      mode: _partyMode
                          ? SessionPlaybackMode.party
                          : SessionPlaybackMode.sync,
                    ),
                  );
                },
          icon: const Icon(Icons.wifi_tethering),
          label: Text(context.l10n.hostSession),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            context.l10n.hostSessionDes,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 12),
        AwaitableButton.outlined(
          onPressed: !controller.selectedTransportReady
              ? null
              : () async {
                  final started = await _guard(
                    () =>
                        _controller.startBrowsing(controller.selectedTransport),
                  );
                  if (mounted && started) setState(() => _browsing = true);
                },
          icon: const Icon(Icons.search),
          label: Text(context.l10n.joinSession),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }

  void _showTransportError(Object error) {
    if (!mounted || _route?.isCurrent != true) return;
    _messenger?.showSnackBar(SnackBar(content: Text(_failureMessage(error))));
  }

  String _failureMessage(Object error) {
    if (error is! TransportFailure) {
      return context.l10n.transportStartupFailed;
    }
    return switch (error.code) {
      TransportFailureCode.bluetoothDisabled => context.l10n.bluetoothDisabled,
      TransportFailureCode.wifiDisabled => context.l10n.wifiDisabled,
      TransportFailureCode.permissionDenied =>
        context.l10n.nearbyPermissionRequired,
      TransportFailureCode.playServicesUnavailable =>
        context.l10n.playServicesUnavailable,
      TransportFailureCode.radioFailure ||
      TransportFailureCode.startupFailure =>
        context.l10n.transportStartupFailed,
    };
  }

  // ---- Browsing for hosts ---------------------------------------------------

  Widget _browseView(ListenTogetherController controller) {
    final sessions = controller.discoveredSessions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                sessions.isEmpty
                    ? context.l10n.searchingForSessions
                    : context.l10n.joinSession,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              context.l10n.noSessionsFound,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          ...sessions.map(
            (s) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                s.kind == TransportKind.wifi ? Icons.wifi : Icons.bluetooth,
              ),
              title: Text(s.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final joined = await _guard(() => _controller.joinSession(s));
                if (mounted && joined) setState(() => _browsing = false);
              },
            ),
          ),
        const SizedBox(height: 8),
        AwaitableButton.text(
          onPressed: () async {
            await _controller.leave();
            if (mounted) setState(() => _browsing = false);
          },
          label: Text(context.l10n.back),
        ),
      ],
    );
  }

  // ---- Active session -------------------------------------------------------

  Widget _activeView(ListenTogetherController controller) {
    final statusText = (controller.isHost || _endingSessionWasHost)
        ? context.l10n.hostingSession
        : (controller.connectionState == TransportConnectionState.connecting
              ? context.l10n.connectingToSession
              : context.l10n.connectedToSession);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              controller.isHost || _endingSessionWasHost
                  ? Icons.wifi_tethering
                  : Icons.link,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(statusText)),
          ],
        ),
        if (!controller.isHost &&
            controller.sessionMode == SessionPlaybackMode.party) ...[
          const SizedBox(height: 8),
          Text(
            context.l10n.partyModeGuestHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 16),
        Text(
          context.l10n.participants,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person),
          title: Text('${controller.selfName} (${context.l10n.you})'),
          trailing: IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editDeviceName(controller),
          ),
        ),
        ...controller.peers.map(
          (p) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: Text(p.name),
          ),
        ),
        const SizedBox(height: 16),
        AwaitableButton.filledTonal(
          onPressed: () async {
            setState(() {
              _endingSession = true;
              _endingSessionWasHost = controller.isHost;
            });
            await _controller.leave();
            if (mounted) await Navigator.of(context).maybePop();
          },
          icon: const Icon(Icons.logout),
          label: Text(
            controller.isHost || _endingSessionWasHost
                ? context.l10n.endSession
                : context.l10n.leaveSession,
          ),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ],
    );
  }

  Future<void> _editDeviceName(ListenTogetherController controller) async {
    final input = TextEditingController(text: controller.selfName);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.listenTogetherDeviceName),
        content: TextField(controller: input, autofocus: true, maxLength: 40),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
    input.dispose();
    if (value != null) controller.deviceName = value;
  }
}
