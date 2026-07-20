import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../../services/listen_together/sync_transport.dart';

class ListenTogetherTransportSelector extends StatelessWidget {
  const ListenTogetherTransportSelector({
    super.key,
    required this.selected,
    required this.availability,
    required this.isAndroid,
    required this.onSelected,
    required this.onRequestPermissions,
  });

  final TransportKind selected;
  final TransportAvailability? availability;
  final bool isAndroid;
  final ValueChanged<TransportKind> onSelected;
  final VoidCallback onRequestPermissions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.connectVia,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: isAndroid
              ? [
                  _chip(
                    context: context,
                    key: const Key('listen_transport_bluetooth'),
                    kind: TransportKind.bluetooth,
                    icon: Icons.bluetooth_searching,
                    label: context.l10n.bluetoothTransport,
                  ),
                  _chip(
                    context: context,
                    key: const Key('listen_transport_wifi'),
                    kind: TransportKind.wifi,
                    icon: Icons.wifi,
                    label: context.l10n.wifiTransport,
                  ),
                  _chip(
                    context: context,
                    key: const Key('listen_transport_both'),
                    kind: TransportKind.both,
                    icon: Icons.device_hub,
                    label: context.l10n.bothTransports,
                  ),
                ]
              : [
                  _chip(
                    context: context,
                    key: const Key('listen_transport_wifi'),
                    kind: TransportKind.wifi,
                    icon: Icons.wifi,
                    label: context.l10n.wifiTransport,
                  ),
                ],
        ),
        const SizedBox(height: 8),
        _status(context),
        if (_needsBluetooth &&
            availability?.bluetoothPermissionGranted == false)
          TextButton.icon(
            onPressed: onRequestPermissions,
            icon: const Icon(Icons.security),
            label: Text(context.l10n.grantPermissions),
          ),
      ],
    );
  }

  Widget _chip({
    required BuildContext context,
    required Key key,
    required TransportKind kind,
    required IconData icon,
    required String label,
  }) => ChoiceChip(
    key: key,
    selected: selected == kind,
    avatar: Icon(icon, size: 18),
    label: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: 6),
        if (availability == null)
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          )
        else
          Tooltip(
            message: availability!.supports(kind)
                ? context.l10n.transportReady
                : _unavailableMessage(context, kind),
            child: Icon(
              availability!.supports(kind)
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              key: Key('listen_transport_${kind.name}_readiness'),
              size: 15,
              color: availability!.supports(kind)
                  ? Colors.green
                  : Theme.of(context).colorScheme.error,
            ),
          ),
      ],
    ),
    onSelected: (_) => onSelected(kind),
  );

  String _unavailableMessage(BuildContext context, TransportKind kind) {
    final value = availability!;
    final needsBluetooth =
        kind == TransportKind.bluetooth || kind == TransportKind.both;
    final needsWifi = kind == TransportKind.wifi || kind == TransportKind.both;
    if (needsBluetooth && !value.bluetoothEnabled) {
      return context.l10n.bluetoothDisabled;
    }
    if (needsWifi && !value.wifiEnabled) return context.l10n.wifiDisabled;
    if (needsBluetooth && !value.playServicesAvailable) {
      return context.l10n.playServicesUnavailable;
    }
    return context.l10n.nearbyPermissionRequired;
  }

  Widget _status(BuildContext context) {
    final value = availability;
    final ready = value?.supports(selected) ?? false;
    final message = value == null
        ? context.l10n.searchingForSessions
        : !value.bluetoothEnabled &&
              (selected == TransportKind.bluetooth ||
                  selected == TransportKind.both)
        ? context.l10n.bluetoothDisabled
        : !value.wifiEnabled &&
              (selected == TransportKind.wifi || selected == TransportKind.both)
        ? context.l10n.wifiDisabled
        : !value.playServicesAvailable &&
              (selected == TransportKind.bluetooth ||
                  selected == TransportKind.both)
        ? context.l10n.playServicesUnavailable
        : !value.bluetoothPermissionGranted && _needsBluetooth
        ? context.l10n.nearbyPermissionRequired
        : context.l10n.transportReady;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(ready ? Icons.check_circle_outline : Icons.info_outline, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }

  bool get _needsBluetooth =>
      selected == TransportKind.bluetooth || selected == TransportKind.both;
}
