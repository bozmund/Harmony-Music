import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against the library TabBar's labels using Flutter's [Tab(text:)]
/// default fixed-height label box (~21.43 * textScale). On some devices/fonts
/// that box overflows vertically even though the library reserves a 50px tab
/// bar area.
void main() {
  test('library tabs use the full reserved height for scaled labels', () {
    final source = File(
      'lib/ui/screens/Library/library_combined.dart',
    ).readAsStringSync();

    expect(source, contains('const double tabBarHeight = 50'));
    expect(source, contains('height: 50'));
    expect(source, contains('child: Text('));
    expect(
      source.contains('Tab(text:'),
      isFalse,
      reason: 'Tab(text:) uses Flutter\'s fixed ~22px internal label height',
    );
  });
}
