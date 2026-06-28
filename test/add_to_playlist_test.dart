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

      expect(source, contains('_loadPipedPlaylistMembership'));
      expect(source, contains('getPlaylistSongs'));
      expect(source, contains('updatePlaylistMembership'));
      expect(source, contains('markSongsAddedToPlaylist'));
    });
  });
}

MediaItem _song(String id) {
  return MediaItem(id: id, title: id, extras: const {});
}
