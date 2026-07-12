import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/controller_providers.dart';
import '../../../services/listen_together/listen_together_controller.dart';
import '../../../services/listen_together/session_message.dart';
import '../../../services/listen_together/sync_transport.dart';
import '../../../l10n/l10n.dart';
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
  bool _partyMode = false;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.listenTogetherUnavailable)),
      );
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
          onPressed: () async {
            await _guard(
              () => _controller.startHosting(
                _kind,
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
          onPressed: () async {
            await _guard(() => _controller.startBrowsing(_kind));
            if (mounted) setState(() => _browsing = true);
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

  Widget _transportSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.connectVia,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _transportChip(
              TransportKind.lan,
              Icons.wifi,
              context.l10n.wifiTransport,
            ),
            const SizedBox(width: 8),
            // Bluetooth transport is not wired up yet (no compatible plugin);
            // keep it visible but disabled so the intent is clear.
            _transportChip(
              TransportKind.nearby,
              Icons.bluetooth,
              context.l10n.bluetoothTransport,
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
      onSelected: enabled
          ? (_) => setState(() => _kind = kind)
          : (_) => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.listenTogetherUnavailable)),
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
}
