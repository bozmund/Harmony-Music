import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/domain/repositories/download_repository.dart';
import 'package:harmonymusic/domain/repositories/library_repository.dart';
import 'package:harmonymusic/domain/repositories/song_cache_repository.dart';
import 'package:harmonymusic/ui/screens/Library/library_controller.dart';
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
      expect(controllerSource, contains('SortWidgetRegistry.maybeOf'));
      expect(librarySource, contains('initialSortType:'));
      expect(librarySource, contains('initialIsAscending:'));
      expect(sortWidgetSource, contains('initialSortType = SortType.name'));
      expect(sortWidgetSource, contains('initialIsAscending = true'));
    });

    test('song added during search remains after search closes', () {
      final controller = _librarySongsController();
      controller.librarySongsList = [
        _song('alpha', 'Alpha', 1000),
        _song('bravo', 'Bravo', 2000),
      ];

      controller.onSearchStart(LibrarySongsController.sortWidgetTag);
      controller.onSearch('Alpha', LibrarySongsController.sortWidgetTag);
      controller.addSongToLibraryList(_song('charlie', 'Charlie', 3000));
      controller.onSearchClose(LibrarySongsController.sortWidgetTag);

      expect(
        controller.librarySongsList.map((song) => song.id),
        contains('charlie'),
      );
    });

    test('matching song added during search appears immediately', () {
      final controller = _librarySongsController();
      controller.librarySongsList = [
        _song('alpha', 'Alpha', 1000),
        _song('bravo', 'Bravo', 2000),
      ];

      controller.onSearchStart(LibrarySongsController.sortWidgetTag);
      controller.onSearch('Al', LibrarySongsController.sortWidgetTag);
      controller.addSongToLibraryList(_song('alpine', 'Alpine', 3000));

      expect(controller.librarySongsList.map((song) => song.id), [
        'alpine',
        'alpha',
      ]);
    });

    test(
      'non-matching song added during search appears after search closes',
      () {
        final controller = _librarySongsController();
        controller.librarySongsList = [
          _song('alpha', 'Alpha', 1000),
          _song('bravo', 'Bravo', 2000),
        ];

        controller.onSearchStart(LibrarySongsController.sortWidgetTag);
        controller.onSearch('Alpha', LibrarySongsController.sortWidgetTag);
        controller.addSongToLibraryList(_song('charlie', 'Charlie', 3000));

        expect(controller.librarySongsList.map((song) => song.id), ['alpha']);

        controller.onSearchClose(LibrarySongsController.sortWidgetTag);

        expect(controller.librarySongsList.map((song) => song.id), [
          'charlie',
          'bravo',
          'alpha',
        ]);
      },
    );

    test('adding duplicate song id replaces instead of duplicating', () {
      final controller = _librarySongsController();
      controller.librarySongsList = [
        _song('alpha', 'Alpha', 1000),
        _song('bravo', 'Bravo', 2000),
      ];

      controller.addSongToLibraryList(_song('alpha', 'Alpha Updated', 3000));

      expect(
        controller.librarySongsList.where((song) => song.id == 'alpha'),
        hasLength(1),
      );
      expect(controller.librarySongsList.first.id, 'alpha');
      expect(controller.librarySongsList.first.title, 'Alpha Updated');
    });

    test('inactive additions use date newest first sorting', () {
      final controller = _librarySongsController();
      controller.librarySongsList = [
        _song('old', 'Old', 1000),
        _song('middle', 'Middle', 2000),
      ];

      controller.addSongToLibraryList(_song('new', 'New', 3000));

      expect(controller.librarySongsList.map((song) => song.id), [
        'new',
        'middle',
        'old',
      ]);
    });
  });
}

MediaItem _song(String id, String title, int? date) {
  return MediaItem(id: id, title: title, extras: {'date': date});
}

LibrarySongsController _librarySongsController() {
  return LibrarySongsController(
    downloadRepository: _FakeDownloadRepository(),
    libraryRepository: _FakeLibraryRepository(),
    songCacheRepository: _FakeSongCacheRepository(),
  );
}

class _FakeDownloadRepository implements DownloadRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSongCacheRepository implements SongCacheRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLibraryRepository implements LibraryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
