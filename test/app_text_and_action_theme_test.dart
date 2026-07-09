import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/utils/app_text_and_action_theme.dart';
import 'package:harmonymusic/ui/widgets/awaitable_button.dart';
import 'package:harmonymusic/ui/widgets/toggle_icon_button.dart';

void main() {
  test(
    'dark themes use onSurface for default text and transparent actions',
    () {
      final theme = applyHarmonyTextAndActionTheme(
        ThemeData(
          colorScheme: const ColorScheme.dark(
            primary: Colors.black,
            surface: Colors.black,
            onSurface: Colors.white,
          ),
        ),
      );

      _expectReadableTheme(theme);
    },
  );

  test(
    'light themes use onSurface for default text and transparent actions',
    () {
      final theme = applyHarmonyTextAndActionTheme(
        ThemeData(
          colorScheme: const ColorScheme.light(
            primary: Colors.white,
            surface: Colors.white,
            onSurface: Colors.black,
          ),
        ),
      );

      _expectReadableTheme(theme);
    },
  );

  testWidgets('outlined awaitable Join action inherits readable foreground', (
    tester,
  ) async {
    final theme = applyHarmonyTextAndActionTheme(
      ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: Colors.black,
          surface: Colors.black,
          onSurface: Colors.white,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: AwaitableButton.outlined(
            icon: const Icon(Icons.search),
            label: const Text('Join a session'),
            onPressed: () async {},
          ),
        ),
      ),
    );

    final style = OutlinedButtonTheme.of(
      tester.element(find.byType(OutlinedButton)),
    ).style!;
    expect(style.foregroundColor!.resolve({}), Colors.white);
  });

  testWidgets('toggle icon button preserves compact control geometry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ToggleIconButton(
            isActive: false,
            activeIcon: Icons.repeat,
            inactiveIcon: Icons.repeat,
            onPressed: () {},
            size: 18,
            splashRadius: 10,
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          ),
        ),
      ),
    );

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.splashRadius, 10);
    expect(
      button.visualDensity,
      const VisualDensity(horizontal: -4, vertical: -4),
    );
    expect(tester.getSize(find.byType(IconButton)), const Size(34, 32));
  });
}

void _expectReadableTheme(ThemeData theme) {
  final foregroundColor = theme.colorScheme.onSurface;
  final disabledForegroundColor = foregroundColor.withValues(alpha: 0.38);

  expect(theme.textTheme.titleLarge!.color, foregroundColor);
  expect(theme.textTheme.bodyMedium!.color, foregroundColor);
  expect(theme.textTheme.labelSmall!.color, foregroundColor);

  final textButtonStyle = theme.textButtonTheme.style!;
  expect(textButtonStyle.foregroundColor!.resolve({}), foregroundColor);
  expect(
    textButtonStyle.foregroundColor!.resolve({WidgetState.disabled}),
    disabledForegroundColor,
  );

  final outlinedButtonStyle = theme.outlinedButtonTheme.style!;
  expect(outlinedButtonStyle.foregroundColor!.resolve({}), foregroundColor);
  expect(
    outlinedButtonStyle.foregroundColor!.resolve({WidgetState.disabled}),
    disabledForegroundColor,
  );
  expect(outlinedButtonStyle.backgroundColor, isNull);
  expect(outlinedButtonStyle.side, isNull);
}
