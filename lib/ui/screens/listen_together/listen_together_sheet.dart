import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/controller_providers.dart';
import '../../../services/listen_together/listen_together_controller.dart';
import '../../../services/listen_together/sync_transport.dart';
import '../../../utils/get_localization.dart';
import '../../widgets/awaitable_button.dart';

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

class _ListenTogetherSheetState extends ConsumerState<ListenTogetherSheet> {
  TransportKind _kind = TransportKind.lan;
  bool _browsing = false;
  bool _endingSession = false;
  bool _endingSessionWasHost = false;

  ListenTogetherController get _controller =>
      ref.read(listenTogetherControllerProvider);

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("listenTogetherUnavailable".tr)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(listenTogetherControllerProvider);
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
          builder:
              (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.groups_2_outlined),
                      const SizedBox(width: 10),
                      Text(
                        "listenTogether".tr,
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
                    _menuView(),
                ],
              ),
        ),
      ),
    );
  }

  // ---- Idle menu ------------------------------------------------------------

  Widget _menuView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _transportSelector(),
        const SizedBox(height: 16),
        AwaitableButton.filled(
          onPressed: () async {
            await _guard(() => _controller.startHosting(_kind));
          },
          icon: const Icon(Icons.wifi_tethering),
          label: Text("hostSession".tr),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            "hostSessionDes".tr,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 12),
        AwaitableButton.outlined(
          onPressed: () async {
            await _guard(() => _controller.startBrowsing(_kind));
            if (mounted) setState(() => _browsing = true);
          },
          icon: const Icon(Icons.search),
          label: Text("joinSession".tr),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }

  Widget _transportSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("connectVia".tr, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Row(
          children: [
            _transportChip(TransportKind.lan, Icons.wifi, "wifiTransport".tr),
            const SizedBox(width: 8),
            // Bluetooth transport is not wired up yet (no compatible plugin);
            // keep it visible but disabled so the intent is clear.
            _transportChip(
              TransportKind.nearby,
              Icons.bluetooth,
              "bluetoothTransport".tr,
              enabled: false,
            ),
          ],
        ),
      ],
    );
  }

  Widget _transportChip(
    TransportKind kind,
    IconData icon,
    String label, {
    bool enabled = true,
  }) {
    return ChoiceChip(
      selected: _kind == kind,
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onSelected:
          enabled
              ? (_) => setState(() => _kind = kind)
              : (_) => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("listenTogetherUnavailable".tr)),
              ),
    );
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
                sessions.isEmpty ? "searchingForSessions".tr : "joinSession".tr,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              "noSessionsFound".tr,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          ...sessions.map(
            (s) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                s.kind == TransportKind.lan ? Icons.wifi : Icons.bluetooth,
              ),
              title: Text(s.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await _guard(() => _controller.joinSession(s));
                if (mounted) setState(() => _browsing = false);
              },
            ),
          ),
        const SizedBox(height: 8),
        AwaitableButton.text(
          onPressed: () async {
            await _controller.leave();
            if (mounted) setState(() => _browsing = false);
          },
          label: Text("back".tr),
        ),
      ],
    );
  }

  // ---- Active session -------------------------------------------------------

  Widget _activeView(ListenTogetherController controller) {
    final statusText =
        (controller.isHost || _endingSessionWasHost)
            ? "hostingSession".tr
            : (controller.connectionState == TransportConnectionState.connecting
                ? "connectingToSession".tr
                : "connectedToSession".tr);
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
        const SizedBox(height: 16),
        Text("participants".tr, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person),
          title: Text('${controller.selfName} (${"you".tr})'),
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
                ? "endSession".tr
                : "leaveSession".tr,
          ),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ],
    );
  }
}
