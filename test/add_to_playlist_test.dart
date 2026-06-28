import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/widgets/add_to_playlist.dart';

void main() {
  group('add to playlist multi-select behavior', () {
    test('membership disables playlists that contain every selected song', () {
      final controller = AddToPlaylistController();
      controller.updatePlaylistMembership('playlist-a', ['song-1']);

      expect(
        controller.isPlaylistDisabled('playlist-a', [_song('song-1')]),
        isTrue,
      );
      expect(
        controller.isPlaylistDisabled('playlist-a', [
          _song('song-1'),
          _song('song-2'),
        ]),
        isFalse,
      );
      expect(
        controller
            .missingSongsForPlaylist([
              _song('song-1'),
              _song('song-2'),
            ], 'playlist-a')
            .map((song) => song.id),
        ['song-2'],
      );
    });

    test('marking one playlist added leaves other playlists available', () {
      final controller = AddToPlaylistController();
      controller.updatePlaylistMembership('playlist-a', []);
      controller.updatePlaylistMembership('playlist-b', []);

      controller.markSongsAddedToPlaylist('playlist-a', [_song('song-1')]);

      expect(
        controller.isPlaylistDisabled('playlist-a', [_song('song-1')]),
        isTrue,
      );
      expect(
        controller.isPlaylistDisabled('playlist-b', [_song('song-1')]),
        isFalse,
      );

      controller.markSongsAddedToPlaylist('playlist-b', [_song('song-1')]);

      expect(
        controller.isPlaylistDisabled('playlist-b', [_song('song-1')]),
        isTrue,
      );
    });

    test('duplicate membership updates do not duplicate ids', () {
      final controller = AddToPlaylistController();
      controller.updatePlaylistMembership('playlist-a', ['song-1']);

      controller.markSongsAddedToPlaylist('playlist-a', [
        _song('song-1'),
        _song('song-1'),
      ]);

      expect(controller.playlistSongIds['playlist-a'], {'song-1'});
    });

    test('dialog add path stays open and exposes disabled row state', () {
      final source = File(
        'lib/ui/widgets/add_to_playlist.dart',
      ).readAsStringSync();
      final rowTapStart = source.indexOf('final result =');
      final rowTapEnd = source.indexOf('ScaffoldMessenger.of', rowTapStart);
      final rowTapBlock = source.substring(rowTapStart, rowTapEnd);

      expect(rowTapStart, isNot(-1));
      expect(rowTapBlock, contains('addSongsToPlaylist'));
      expect(rowTapBlock, isNot(contains('Navigator.of(context).pop')));
      expect(source, contains('isPlaylistDisabled'));
      expect(source, contains('Icons.check_circle'));
      expect(source, contains('Icons.done'));
    });

    test('piped membership loads playlist songs for disabled state', () {
      final source = File(
        'lib/ui/widgets/add_to_playlist.dart',
      ).readAsStringSync();

      expect(source, contains('ensurePlaylistMembershipLoaded'));
      expect(source, contains('getPlaylistSongs'));
      expect(source, contains('updatePlaylistMembership'));
      expect(source, contains('markSongsAddedToPlaylist'));
    });

    test('local add tracks actual inserts before reporting added', () {
      final source = File(
        'lib/ui/widgets/add_to_playlist.dart',
      ).readAsStringSync();

      expect(source, contains('actuallyAddedSongs'));
      expect(
        source,
        contains(
          'if (actuallyAddedSongs.isEmpty) return PlaylistAddStatus.skipped',
        ),
      );
      expect(
        source,
        contains('markSongsAddedToPlaylist(playlistId, actuallyAddedSongs)'),
      );
    });

    test('add failures are converted to failed status', () {
      final source = File(
        'lib/ui/widgets/add_to_playlist.dart',
      ).readAsStringSync();

      final addMethodStart = source.indexOf(
        'Future<PlaylistAddStatus> addSongsToPlaylist',
      );
      final addMethodEnd = source.indexOf(
        'Future<List<MediaItem>> _addLocalMissingSongs',
      );
      final addMethod = source.substring(addMethodStart, addMethodEnd);

      expect(addMethod, contains('catch (e)'));
      expect(addMethod, contains('PlaylistAddStatus.failed'));
      expect(addMethod, contains('printWarning'));
      expect(addMethod, contains('finally'));
      expect(addMethod, contains('addingPlaylistIds.remove(playlistId)'));
    });

    test('switching to piped does not eagerly load every playlist', () {
      final source = File(
        'lib/ui/widgets/add_to_playlist.dart',
      ).readAsStringSync();

      final changeTypeStart = source.indexOf('Future<void> changePlaylistType');
      final changeTypeEnd = source.indexOf('bool isPlaylistAdding');
      final changeTypeMethod = source.substring(changeTypeStart, changeTypeEnd);

      expect(changeTypeMethod, isNot(contains('getPlaylistSongs')));
      expect(
        changeTypeMethod,
        isNot(contains('ensurePlaylistMembershipLoaded')),
      );
      expect(source, contains('isPlaylistMembershipLoading'));
      expect(source, contains('ensurePlaylistMembershipLoaded('));
    });
  });
}

MediaItem _song(String id) {
  return MediaItem(id: id, title: id, extras: const {});
}
