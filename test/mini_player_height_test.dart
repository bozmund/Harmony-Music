import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/widgets/bottom_nav_bar_dimensions.dart';

void main() {
  group('collapsed mini-player height', () {
    test(
      'bottom nav visible reserves mini-player, nav bar, and system inset',
      () {
        expect(
          collapsedMiniPlayerHeightForInset(
            bottomInset: 24,
            isWideScreen: false,
            bottomNavVisible: true,
          ),
          75 + 64 + 24,
        );
      },
    );

    test('bottom nav hidden reserves mini-player and system inset', () {
      expect(
        collapsedMiniPlayerHeightForInset(
          bottomInset: 24,
          isWideScreen: false,
          bottomNavVisible: false,
        ),
        75 + 24,
      );
    });

    test('wide layout uses the wide mini-player base height', () {
      expect(
        collapsedMiniPlayerHeightForInset(
          bottomInset: 24,
          isWideScreen: true,
          bottomNavVisible: false,
        ),
        105 + 24,
      );
    });
  });
}
