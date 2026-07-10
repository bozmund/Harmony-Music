import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/widgets/awaitable_button.dart';

void main() {
  testWidgets('button disables immediately after tap', (tester) async {
    final completer = Completer<void>();

    await tester.pumpWidget(
      _host(
        AwaitableButton.filled(
          label: const Text('Save'),
          onPressed: () => completer.future,
        ),
      ),
    );

    await tester.tap(find.text('Save'));
    await tester.pump();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('spinner replaces the leading icon slot while awaiting', (
    tester,
  ) async {
    final completer = Completer<void>();

    await tester.pumpWidget(
      _host(
        AwaitableButton.filled(
          icon: const Icon(Icons.logout),
          label: const Text('Leave'),
          onPressed: () => completer.future,
        ),
      ),
    );

    expect(find.byIcon(Icons.logout), findsOneWidget);

    await tester.tap(find.text('Leave'));
    await tester.pump();

    expect(find.byIcon(Icons.logout), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('double tap invokes callback once', (tester) async {
    final completer = Completer<void>();
    var calls = 0;

    await tester.pumpWidget(
      _host(
        AwaitableButton.outlined(
          label: const Text('Sync'),
          onPressed: () {
            calls++;
            return completer.future;
          },
        ),
      ),
    );

    await tester.tap(find.text('Sync'));
    await tester.tap(find.text('Sync'));
    await tester.pump();

    expect(calls, 1);

    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('callback completion restores enabled state', (tester) async {
    final completer = Completer<void>();

    await tester.pumpWidget(
      _host(
        AwaitableButton.text(
          label: const Text('Refresh'),
          onPressed: () => completer.future,
        ),
      ),
    );

    await tester.tap(find.text('Refresh'));
    await tester.pump();
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );

    completer.complete();
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('disabled button never starts loading', (tester) async {
    await tester.pumpWidget(
      _host(
        const AwaitableButton.filled(label: Text('Disabled'), onPressed: null),
      ),
    );

    await tester.tap(find.text('Disabled'), warnIfMissed: false);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('icon button keeps stable size while awaiting', (tester) async {
    final completer = Completer<void>();
    const buttonKey = Key('awaitable-icon-button');

    await tester.pumpWidget(
      _host(
        AwaitableIconButton(
          key: buttonKey,
          icon: const Icon(Icons.sync),
          onPressed: () => completer.future,
        ),
      ),
    );

    final sizeBefore = tester.getSize(find.byKey(buttonKey));

    await tester.tap(find.byKey(buttonKey));
    await tester.pump();

    final sizeDuring = tester.getSize(find.byKey(buttonKey));
    expect(sizeDuring, sizeBefore);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
  });
}

Widget _host(Widget child) {
  return MaterialApp(home: Scaffold(body: Center(child: child)));
}
