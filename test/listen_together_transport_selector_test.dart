import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/l10n/app_localizations.dart';
import 'package:harmonymusic/services/listen_together/sync_transport.dart';
import 'package:harmonymusic/ui/screens/listen_together/listen_together_transport_selector.dart';

void main() {
  const ready = TransportAvailability(
    bluetoothEnabled: true,
    wifiEnabled: true,
    playServicesAvailable: true,
  );

  Widget app({
    required Locale locale,
    required TransportKind selected,
    required TransportAvailability availability,
    ValueChanged<TransportKind>? onSelected,
  }) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ListenTogetherTransportSelector(
        selected: selected,
        availability: availability,
        isAndroid: true,
        onSelected: onSelected ?? (_) {},
        onRequestPermissions: () {},
      ),
    ),
  );

  testWidgets('shows all Android transport choices in English', (tester) async {
    await tester.pumpWidget(
      app(
        locale: const Locale('en'),
        selected: TransportKind.both,
        availability: ready,
      ),
    );

    expect(find.text('Bluetooth'), findsOneWidget);
    expect(find.text('Wi-Fi'), findsOneWidget);
    expect(find.text('Bluetooth + Wi-Fi'), findsOneWidget);
    expect(find.text('Selected connection mode is ready.'), findsOneWidget);
  });

  testWidgets('shows the missing Wi-Fi state in Croatian', (tester) async {
    await tester.pumpWidget(
      app(
        locale: const Locale('hr'),
        selected: TransportKind.both,
        availability: const TransportAvailability(
          bluetoothEnabled: true,
          wifiEnabled: false,
          playServicesAvailable: true,
        ),
      ),
    );

    expect(
      find.text(
        'Uključite Wi-Fi za ovaj način povezivanja. Internetska veza nije potrebna.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('reports the user transport selection', (tester) async {
    TransportKind? selected;
    await tester.pumpWidget(
      app(
        locale: const Locale('en'),
        selected: TransportKind.both,
        availability: ready,
        onSelected: (value) => selected = value,
      ),
    );

    await tester.tap(find.byKey(const Key('listen_transport_wifi')));
    expect(selected, TransportKind.wifi);
  });
}
