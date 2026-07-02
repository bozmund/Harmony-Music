import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The library tab controllers outlive the SortWidget that hosts their
/// search bar. Without a reset on remount, navigating away mid-search and
/// back left the list filtered while the search UI came back empty.
void main() {
  group('library stale search reset', () {
    test('sort widget reports mounting after the first frame', () {
      final source = File('lib/ui/widgets/sort_widget.dart')
          .readAsStringSync();
      final initStateIndex = source.indexOf('void initState()');
      final postFrameIndex = source.indexOf(
        'addPostFrameCallback',
        initStateIndex,
      );
      final onMountedIndex = source.indexOf(
        'widget.onMounted!()',
        postFrameIndex,
      );
      expect(initStateIndex, greaterThan(-1));
      // Deferred: the callback notifies listeners, which must not happen
      // during the surrounding build.
      expect(postFrameIndex, greaterThan(initStateIndex));
      expect(onMountedIndex, greaterThan(postFrameIndex));
    });

    test('all four library tab controllers can drop a stale filter', () {
      final source = File(
        'lib/ui/screens/Library/library_controller.dart',
      ).readAsStringSync();
      final occurrences =
          'void clearStaleSearch()'.allMatches(source).length;
      expect(
        occurrences,
        4,
        reason: 'songs, playlists, albums and artists controllers all keep '
            'their filtered list alive across navigation',
      );
      // Each reset is a no-op when no search was active — restoring from an
      // empty backup would wipe the list.
      expect(
        RegExp(
          r'void clearStaleSearch\(\) \{\s*\n\s*if \(tempListContainer\.isEmpty\) return;',
        ).allMatches(source).length,
        4,
      );
    });

    test('every library sort widget wires the stale-search reset', () {
      final source = File('lib/ui/screens/Library/library.dart')
          .readAsStringSync();
      expect(
        'onMounted:'.allMatches(source).length,
        4,
        reason: 'songs, albums, playlists and artists sort widgets',
      );
      expect('clearStaleSearch'.allMatches(source).length, 4);
    });
  });
}
