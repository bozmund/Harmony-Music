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

  group('applyResolvedDuration', () {
    test('fills a missing duration in the on-screen list', () {
      final controller = _librarySongsController();
      controller.librarySongsList = [_song('kalasi', 'Kalasi', 1000)];

      controller.applyResolvedDuration(
        'kalasi',
        const Duration(seconds: 148),
      );

      expect(
        controller.librarySongsList.single.duration,
        const Duration(seconds: 148),
      );
    });

    test('never overwrites a duration the song already has', () {
      final controller = _librarySongsController();
      controller.librarySongsList = [
        _song('kalasi', 'Kalasi', 1000)
            .copyWith(duration: const Duration(seconds: 200)),
      ];

      controller.applyResolvedDuration(
        'kalasi',
        const Duration(seconds: 148),
      );

      expect(
        controller.librarySongsList.single.duration,
        const Duration(seconds: 200),
      );
    });

    test('ignores unknown ids and zero durations', () {
      final controller = _librarySongsController();
      controller.librarySongsList = [_song('kalasi', 'Kalasi', 1000)];

      controller.applyResolvedDuration('missing', const Duration(seconds: 90));
      controller.applyResolvedDuration('kalasi', Duration.zero);

      expect(controller.librarySongsList.single.duration, isNull);
    });

    test('also patches the search snapshot while searching', () {
      final controller = _librarySongsController();
      controller.librarySongsList = [
        _song('kalasi', 'Kalasi', 1000),
        _song('other', 'Other', 2000),
      ];
      controller.onSearchStart(LibrarySongsController.sortWidgetTag);
      controller.onSearch('Kalasi', LibrarySongsController.sortWidgetTag);

      controller.applyResolvedDuration(
        'kalasi',
        const Duration(seconds: 148),
      );
      controller.onSearchClose(LibrarySongsController.sortWidgetTag);

      final kalasi =
          controller.librarySongsList.firstWhere((s) => s.id == 'kalasi');
      expect(kalasi.duration, const Duration(seconds: 148));
    });
  });

  group('playback backfills persisted duration', () {
    test('player persists and patches duration once playback resolves it', () {
      final source = File(
        'lib/ui/player/player_controller.dart',
      ).readAsStringSync();
      // Persist to the DB, then patch the on-screen library list.
      final persistIndex = source.indexOf(
        '_libraryRepository.backfillSongDuration(mediaItem.id, duration)',
      );
      final patchIndex = source.indexOf(
        'LibrarySongsControllerRegistry.current?.applyResolvedDuration',
      );
      expect(persistIndex, greaterThan(-1));
      expect(patchIndex, greaterThan(persistIndex));
      // Runs as a side effect of the resolved media item.
      expect(source, contains('await _backfillLibraryDuration(mediaItem);'));
    });

    test('backfill only touches the library song boxes when missing', () {
      final source = File(
        'lib/data/repositories/hive_library_repository.dart',
      ).readAsStringSync();
      final start = source.indexOf('Future<bool> backfillSongDuration(');
      expect(start, greaterThan(-1));
      final body = source.substring(start, source.indexOf('\n  }', start));
      expect(body, contains('BoxNames.songsCache'));
      expect(body, contains('BoxNames.songDownloads'));
      // Existing durations must be preserved.
      expect(body, contains('if (existing is int && existing > 0) continue;'));
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
