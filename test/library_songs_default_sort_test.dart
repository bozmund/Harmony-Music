import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/widgets/sort_widget.dart';
import 'package:harmonymusic/utils/helper.dart';

void main() {
  group('library songs default date sort', () {
    test('dated songs sort newest first by default', () {
      final songs = [
        _song('old', 'Old', 1000),
        _song('new', 'New', 3000),
        _song('middle', 'Middle', 2000),
      ];

      sortSongsNVideos(songs, SortType.date, false);

      expect(songs.map((song) => song.id), ['new', 'middle', 'old']);
    });

    test('missing-date songs stay after dated songs', () {
      final songs = [
        _song('missing-a', 'Beta', null),
        _song('dated', 'Alpha', 1000),
        _song('missing-b', 'Aardvark', null),
      ];

      sortSongsNVideos(songs, SortType.date, false);

      expect(songs.map((song) => song.id), ['dated', 'missing-b', 'missing-a']);
    });

    test('equal-date songs fall back to title order', () {
      final songs = [_song('z', 'Zulu', 1000), _song('a', 'Alpha', 1000)];

      sortSongsNVideos(songs, SortType.date, false);

      expect(songs.map((song) => song.id), ['a', 'z']);
    });

    test('library songs widget initializes date descending sort controls', () {
      final librarySource = File(
        'lib/ui/screens/Library/library.dart',
      ).readAsStringSync();
      final controllerSource = File(
        'lib/ui/screens/Library/library_controller.dart',
      ).readAsStringSync();
      final sortWidgetSource = File(
        'lib/ui/widgets/sort_widget.dart',
      ).readAsStringSync();

      expect(controllerSource, contains('defaultSortType = SortType.date'));
      expect(controllerSource, contains('defaultSortAscending = false'));
      expect(controllerSource, contains('sortWidgetTag = "LibSongSort"'));
      expect(controllerSource, contains('Get.find<SortWidgetController>'));
      expect(librarySource, contains('initialSortType:'));
      expect(librarySource, contains('initialIsAscending:'));
      expect(sortWidgetSource, contains('initialSortType = SortType.name'));
      expect(sortWidgetSource, contains('initialIsAscending = true'));
    });
  });
}

MediaItem _song(String id, String title, int? date) {
  return MediaItem(id: id, title: title, extras: {'date': date});
}
