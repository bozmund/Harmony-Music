import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:harmonymusic/ui/screens/Library/library.dart';
import 'package:harmonymusic/ui/screens/Library/library_combined.dart';
import 'package:harmonymusic/ui/screens/Library/library_controller.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';

void main() {
  group('Library Tab Reordering Logic', () {
    test('getOrderedTabKeys reorders correctly for Songs (index 0)', () {
      final keys = getOrderedTabKeys(0);
      expect(keys[0], "songs");
      expect(keys.length, 5);
      expect(keys, ["songs", "searches", "playlists", "albums", "artists"]);
    });

    test('getOrderedTabKeys reorders correctly for Playlists (index 2)', () {
      final keys = getOrderedTabKeys(2);
      expect(keys[0], "playlists");
      expect(keys.length, 5);
      expect(keys, ["playlists", "songs", "searches", "albums", "artists"]);
    });

    test('getOrderedTabKeys reorders correctly for Artists (index 4)', () {
      final keys = getOrderedTabKeys(4);
      expect(keys[0], "artists");
      expect(keys.length, 5);
      expect(keys, ["artists", "songs", "searches", "playlists", "albums"]);
    });

    test('getOrderedTabKeys handles out of bounds gracefully', () {
      final keys = getOrderedTabKeys(10);
      expect(keys, libraryTabKeys);
    });

    test(
      'getOrderedLibraryWidgets reorders correctly for Searches (index 1)',
      () {
        final widgets = getOrderedLibraryWidgets(1);
        expect(widgets[0], isA<LibrarySearchWidget>());
        expect(widgets[1], isA<SongsLibraryWidget>());
        expect(widgets.length, 5);
      },
    );

    test(
      'getOrderedLibraryWidgets reorders correctly for Albums (index 3)',
      () {
        final widgets = getOrderedLibraryWidgets(3);
        expect(widgets[0], isA<PlaylistNAlbumLibraryWidget>());
        // index 3 in original list is albums (isAlbumContent: true)
        final albumWidget = widgets[0] as PlaylistNAlbumLibraryWidget;
        expect(albumWidget.isAlbumContent, true);
        expect(widgets.length, 5);
      },
    );

    test(
      'getOrderedLibraryWidgets reorders correctly for Playlists (index 2)',
      () {
        final widgets = getOrderedLibraryWidgets(2);
        expect(widgets[0], isA<PlaylistNAlbumLibraryWidget>());
        final playlistWidget = widgets[0] as PlaylistNAlbumLibraryWidget;
        expect(playlistWidget.isAlbumContent, false);
        expect(widgets.length, 5);
      },
    );

    test(
      'getOrderedLibraryWidgets reorders correctly for Artists (index 4)',
      () {
        final widgets = getOrderedLibraryWidgets(4);
        expect(widgets[0], isA<LibraryArtistWidget>());
        expect(widgets.length, 5);
      },
    );

    test('withInitialPlaylistsTail keeps user playlists before built-ins', () {
      final userPlaylist = Playlist(
        title: 'User Playlist',
        playlistId: 'LIB1',
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        isCloudPlaylist: false,
      );
      final importedPlaylist = Playlist(
        title: 'Imported Playlist',
        playlistId: 'LIB2',
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        isCloudPlaylist: false,
      );
      final mixed = [
        LibraryPlaylistsController.initialPlaylists.first,
        userPlaylist,
        importedPlaylist,
      ];

      final ordered = LibraryPlaylistsController.withInitialPlaylistsTail(
        mixed,
      );

      expect(ordered.first.playlistId, userPlaylist.playlistId);
      expect(ordered[1].playlistId, importedPlaylist.playlistId);
      expect(
        ordered.sublist(2).map((playlist) => playlist.playlistId),
        LibraryPlaylistsController.initialPlaylists.map(
          (playlist) => playlist.playlistId,
        ),
      );
    });

    test('normalizeLibraryFirstTab clamps invalid stored values', () {
      expect(SettingsScreenController.normalizeLibraryFirstTab(null), 0);
      expect(SettingsScreenController.normalizeLibraryFirstTab('2'), 0);
      expect(SettingsScreenController.normalizeLibraryFirstTab(-1), 0);
      expect(SettingsScreenController.normalizeLibraryFirstTab(99), 0);
      expect(SettingsScreenController.normalizeLibraryFirstTab(2), 2);
    });
  });
}
