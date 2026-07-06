import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('song info bottom sheet favorite toggle', () {
    late String toggleFavBody;

    setUpAll(() {
      final source = File(
        'lib/ui/widgets/song_info_bottom_sheet.dart',
      ).readAsStringSync();
      final start = source.indexOf('Future<void> toggleFav()');
      expect(start, greaterThan(-1));
      final end = source.indexOf('\n  }', start);
      toggleFavBody = source.substring(start, end);
    });

    test('a missing playlist-screen controller never aborts the toggle', () {
      // The registry lookups only refresh playlist screens that happen to be
      // open. An early return here once left the heart unfilled and skipped
      // the auto-download even though the favorite was already persisted.
      expect(toggleFavBody, isNot(contains('== null) return;')));
      expect(toggleFavBody, contains('!= null)'));
    });

    test('state flip, UI notification and auto-download always run last', () {
      final setFavoriteIndex = toggleFavBody.indexOf('setFavorite(song');
      final flipIndex = toggleFavBody.indexOf(
        'isCurrentSongFav = !isCurrentSongFav;',
        setFavoriteIndex,
      );
      final notifyIndex = toggleFavBody.indexOf('notifyListeners();', flipIndex);
      final autoDownloadIndex = toggleFavBody.indexOf(
        '_downloader.download(song)',
        notifyIndex,
      );
      expect(setFavoriteIndex, greaterThan(-1));
      expect(flipIndex, greaterThan(setFavoriteIndex));
      expect(notifyIndex, greaterThan(flipIndex));
      expect(autoDownloadIndex, greaterThan(notifyIndex));
    });
  });
}
