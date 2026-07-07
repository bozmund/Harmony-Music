import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/data/repositories/hive_playlist_repository.dart';
import 'package:harmonymusic/data/repositories/hive_settings_repository.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/piped_service.dart';
import 'package:harmonymusic/ui/widgets/add_to_playlist.dart';
import 'package:hive/hive.dart';

class TestPipedServices extends PipedServices {
  TestPipedServices({
    this.loggedIn = false,
    Res? playlistsResponse,
    this.playlistSongsHandler,
    this.addToPlaylistHandler,
  }) : playlistsResponse = playlistsResponse ?? Res(0),
       super(HiveSettingsRepository());

  final bool loggedIn;
  final Res playlistsResponse;
  Future<List<MediaItem>> Function(String playlistId)? playlistSongsHandler;
  Future<Res> Function(String playlistId, List<String> videosId)?
  addToPlaylistHandler;
  final requestedMemberships = <String>[];
  final requestedAdds = <TestPlaylistAddRequest>[];
  final requestedRemovals = <TestPlaylistRemoveRequest>[];

  @override
  bool get isLoggedIn => loggedIn;

  @override
  Future<Res> getAllPlaylists() async => playlistsResponse;

  @override
  Future<List<MediaItem>> getPlaylistSongs(String playlistId) async {
    requestedMemberships.add(playlistId);
    final handler = playlistSongsHandler;
    if (handler == null) return [];
    return handler(playlistId);
  }

  @override
  Future<Res> addToPlaylist(String playlistId, List<String> videosId) async {
    requestedAdds.add(TestPlaylistAddRequest(playlistId, videosId));
    final handler = addToPlaylistHandler;
    if (handler == null) return Res(1);
    return handler(playlistId, videosId);
  }

  @override
  Future<Res> removeFromPlaylist(String playlistId, int index) async {
    requestedRemovals.add(TestPlaylistRemoveRequest(playlistId, index));
    return Res(1);
  }
}

class TestPlaylistAddRequest {
  const TestPlaylistAddRequest(this.playlistId, this.videosId);

  final String playlistId;
  final List<String> videosId;
}

class TestPlaylistRemoveRequest {
  const TestPlaylistRemoveRequest(this.playlistId, this.index);

  final String playlistId;
  final int index;
}

void main() {
  late Directory hiveDir;
  var boxCounter = 0;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('add_to_playlist_test_');
    Hive.init(hiveDir.path);
  });

  setUp(() async {
    await Hive.openBox('AppPrefs');
  });

  tearDown(() async {
    await Hive.close();
  });

  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  String nextBoxName(String prefix) => '${prefix}_${boxCounter++}';

  group('add to playlist multi-select behavior', () {
    test('membership disables playlists that contain every selected song', () {
      final controller = _controller();
      controller.updatePlaylistMembership('playlist-a', ['song-1']);

      expect(
        controller.playlistContainsAllSongs('playlist-a', [_song('song-1')]),
        isTrue,
      );
      expect(
        controller.playlistContainsAllSongs('playlist-a', [
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
      final controller = _controller();
      controller.updatePlaylistMembership('playlist-a', []);
      controller.updatePlaylistMembership('playlist-b', []);

      controller.markSongsAddedToPlaylist('playlist-a', [_song('song-1')]);

      expect(
        controller.playlistContainsAllSongs('playlist-a', [_song('song-1')]),
        isTrue,
      );
      expect(
        controller.playlistContainsAllSongs('playlist-b', [_song('song-1')]),
        isFalse,
      );

      controller.markSongsAddedToPlaylist('playlist-b', [_song('song-1')]);

      expect(
        controller.playlistContainsAllSongs('playlist-b', [_song('song-1')]),
        isTrue,
      );
    });

    test('duplicate membership updates do not duplicate ids', () {
      final controller = _controller();
      controller.updatePlaylistMembership('playlist-a', ['song-1']);

      controller.markSongsAddedToPlaylist('playlist-a', [
        _song('song-1'),
        _song('song-1'),
      ]);

      expect(controller.playlistSongIds['playlist-a'], {'song-1'});
    });

    test('removed songs make a playlist addable again', () {
      final controller = _controller();
      controller.updatePlaylistMembership('playlist-a', ['song-1']);

      expect(
        controller.playlistContainsAllSongs('playlist-a', [_song('song-1')]),
        isTrue,
      );

      controller.markSongsRemovedFromPlaylist('playlist-a', [_song('song-1')]);

      expect(
        controller.playlistContainsAllSongs('playlist-a', [_song('song-1')]),
        isFalse,
      );
    });

    test('stale local cache skips when Hive already has all songs', () async {
      final controller = _controller();
      final playlistId = nextBoxName('stale_all');
      final playlistBox = await Hive.openBox(playlistId);
      await playlistBox.add(MediaItemBuilder.toJson(_song('song-1')));
      await playlistBox.close();

      controller.updatePlaylistMembership(playlistId, []);

      final result = await controller.addSongsToPlaylist([
        _song('song-1'),
      ], playlistId);

      expect(result, PlaylistAddStatus.skipped);
      expect(controller.playlistSongIds[playlistId], {'song-1'});
    });

    test('stale local cache adds only missing songs', () async {
      final controller = _controller();
      final playlistId = nextBoxName('stale_partial');
      final playlistBox = await Hive.openBox(playlistId);
      await playlistBox.add(MediaItemBuilder.toJson(_song('song-1')));
      await playlistBox.close();

      controller.updatePlaylistMembership(playlistId, []);

      final result = await controller.addSongsToPlaylist([
        _song('song-1'),
        _song('song-2'),
      ], playlistId);

      final updatedBox = await Hive.openBox(playlistId);
      final ids = updatedBox.values
          .map((item) => item['videoId'])
          .whereType<String>()
          .toList();

      expect(result, PlaylistAddStatus.added);
      expect(ids, containsAll(['song-1', 'song-2']));
      expect(ids.where((id) => id == 'song-1'), hasLength(1));
      expect(controller.playlistSongIds[playlistId], {'song-1', 'song-2'});
    });

    test('piped membership failure remains unloaded and can retry', () async {
      final pipedServices = await _putPipedServices(
        TestPipedServices(
          playlistSongsHandler: (_) async {
            throw Exception('temporary failure');
          },
        ),
      );
      final controller = _controller(pipedServices: pipedServices)
        ..playlistType.value = 'piped';

      final failed = await controller.ensurePlaylistMembershipLoaded('piped-a');

      expect(failed, isFalse);
      expect(controller.isPlaylistMembershipLoaded('piped-a'), isFalse);
      expect(controller.isPlaylistMembershipLoading('piped-a'), isFalse);

      pipedServices.playlistSongsHandler = (_) async => [_song('song-1')];

      final retried = await controller.ensurePlaylistMembershipLoaded(
        'piped-a',
      );

      expect(retried, isTrue);
      expect(controller.playlistSongIds['piped-a'], {'song-1'});
    });

    test('switching to piped does not eagerly load memberships', () async {
      final pipedServices = await _putPipedServices(TestPipedServices());
      final controller = _controller(pipedServices: pipedServices)
        ..pipedPlaylists = [_playlist('piped-a'), _playlist('piped-b')];

      await controller.changePlaylistType('piped');

      expect(controller.playlists.map((playlist) => playlist.playlistId), [
        'piped-a',
        'piped-b',
      ]);
      expect(pipedServices.requestedMemberships, isEmpty);
    });

    test('piped add loads only the tapped playlist membership', () async {
      final pipedServices = await _putPipedServices(
        TestPipedServices(playlistSongsHandler: (_) async => []),
      );
      final controller = _controller(pipedServices: pipedServices)
        ..playlistType.value = 'piped';

      final result = await controller.addSongsToPlaylist([
        _song('song-1'),
      ], 'piped-a');

      expect(result, PlaylistAddStatus.added);
      expect(pipedServices.requestedMemberships, ['piped-a']);
      expect(pipedServices.requestedAdds, hasLength(1));
      expect(pipedServices.requestedAdds.single.playlistId, 'piped-a');
      expect(pipedServices.requestedAdds.single.videosId, ['song-1']);
    });

    test(
      'piped add skips after tap-time membership finds existing song',
      () async {
        final pipedServices = await _putPipedServices(
          TestPipedServices(
            playlistSongsHandler: (_) async => [_song('song-1')],
          ),
        );
        final controller = _controller(pipedServices: pipedServices)
          ..playlistType.value = 'piped';

        final result = await controller.addSongsToPlaylist([
          _song('song-1'),
        ], 'piped-a');

        expect(result, PlaylistAddStatus.skipped);
        expect(pipedServices.requestedMemberships, ['piped-a']);
        expect(pipedServices.requestedAdds, isEmpty);
        expect(controller.playlistSongIds['piped-a'], {'song-1'});
      },
    );

    test('in-flight add keeps the backend it started with', () async {
      final addCompleter = Completer<Res>();
      final pipedServices = await _putPipedServices(
        TestPipedServices(
          loggedIn: true,
          addToPlaylistHandler: (_, _) => addCompleter.future,
        ),
      );
      final controller = _controller(pipedServices: pipedServices)
        ..playlistType.value = 'piped';
      controller.updatePlaylistMembership('piped-a', []);

      final pendingAdd = controller.addSongsToPlaylist([
        _song('song-1'),
      ], 'piped-a');
      await Future<void>.delayed(Duration.zero);

      controller.playlistType.value = 'local';
      addCompleter.complete(Res(1));

      expect(await pendingAdd, PlaylistAddStatus.added);
      expect(pipedServices.requestedAdds, hasLength(1));
      expect(pipedServices.requestedAdds.single.playlistId, 'piped-a');
      expect(pipedServices.requestedAdds.single.videosId, ['song-1']);
    });

    test(
      'local membership loads lazily and disables contained songs',
      () async {
        final playlistId = nextBoxName('local_disabled');
        final playlistBox = await Hive.openBox(playlistId);
        await playlistBox.add(MediaItemBuilder.toJson(_song('song-1')));
        await playlistBox.close();
        final controller = _controller();

        expect(controller.isPlaylistMembershipLoaded(playlistId), isFalse);
        expect(
          await controller.ensurePlaylistMembershipLoaded(playlistId),
          isTrue,
        );
        expect(
          controller.playlistContainsAllSongs(playlistId, [_song('song-1')]),
          isTrue,
        );
      },
    );

    test('adding locally marks the playlist disabled afterward', () async {
      final playlistId = nextBoxName('local_add');
      final controller = _controller();

      expect(
        await controller.addSongsToPlaylist([_song('song-1')], playlistId),
        PlaylistAddStatus.added,
      );
      expect(
        controller.playlistContainsAllSongs(playlistId, [_song('song-1')]),
        isTrue,
      );
    });

    test('tapping a local playlist that has the song removes it', () async {
      final playlistId = nextBoxName('local_remove');
      final controller = _controller();

      // Seed: song is in the playlist.
      expect(
        await controller.addSongsToPlaylist([_song('song-1')], playlistId),
        PlaylistAddStatus.added,
      );
      expect(
        controller.playlistContainsAllSongs(playlistId, [_song('song-1')]),
        isTrue,
      );

      final result = await controller.removeSongsFromPlaylist([
        _song('song-1'),
      ], playlistId);

      expect(result, PlaylistRemoveStatus.removed);
      // Row flips back to "addable", and the box no longer holds the song.
      expect(
        controller.playlistContainsAllSongs(playlistId, [_song('song-1')]),
        isFalse,
      );
      final box = await Hive.openBox(playlistId);
      final ids = box.values
          .map((item) => item['videoId'])
          .whereType<String>()
          .toList();
      expect(ids, isNot(contains('song-1')));
    });

    test(
      'loadPlaylists eagerly resolves local membership so removal is visible',
      () async {
        final pipedServices = await _putPipedServices(TestPipedServices());
        final playlistId = nextBoxName('eager_local');

        // A local playlist already containing song-1.
        final playlistBox = await Hive.openBox('LibraryPlaylists');
        await playlistBox.put(
          playlistId,
          _localPlaylistJson(playlistId),
        );
        await playlistBox.close();
        final songBox = await Hive.openBox(playlistId);
        await songBox.add(MediaItemBuilder.toJson(_song('song-1')));
        await songBox.close();

        final controller = _controller(pipedServices: pipedServices);
        await controller.loadPlaylists();

        // Membership is known without the user tapping the row first, so the
        // "already added — tap to remove" state can render immediately.
        expect(controller.isPlaylistMembershipLoaded(playlistId), isTrue);
        expect(
          controller.playlistContainsAllSongs(playlistId, [_song('song-1')]),
          isTrue,
        );
        // Local preload must not fire any piped membership requests.
        expect(pipedServices.requestedMemberships, isEmpty);
      },
    );

    test('removing a song the playlist does not have is a no-op', () async {
      final playlistId = nextBoxName('local_remove_absent');
      final controller = _controller();
      controller.updatePlaylistMembership(playlistId, []);

      final result = await controller.removeSongsFromPlaylist([
        _song('song-1'),
      ], playlistId);

      expect(result, PlaylistRemoveStatus.skipped);
    });

    test('tapping a piped playlist removes the song by index', () async {
      final pipedServices = await _putPipedServices(
        TestPipedServices(
          playlistSongsHandler: (_) async => [
            _song('song-0'),
            _song('song-1'),
            _song('song-2'),
          ],
        ),
      );
      final controller = _controller(pipedServices: pipedServices)
        ..playlistType.value = 'piped';
      controller.updatePlaylistMembership('piped-a', [
        'song-0',
        'song-1',
        'song-2',
      ]);

      final result = await controller.removeSongsFromPlaylist([
        _song('song-1'),
      ], 'piped-a');

      expect(result, PlaylistRemoveStatus.removed);
      expect(pipedServices.requestedRemovals, hasLength(1));
      expect(pipedServices.requestedRemovals.single.playlistId, 'piped-a');
      // song-1 sits at index 1 in the fetched order.
      expect(pipedServices.requestedRemovals.single.index, 1);
      expect(controller.playlistSongIds['piped-a'], {'song-0', 'song-2'});
    });

    test('piped multi-remove deletes highest index first', () async {
      final pipedServices = await _putPipedServices(
        TestPipedServices(
          playlistSongsHandler: (_) async => [
            _song('song-0'),
            _song('song-1'),
            _song('song-2'),
          ],
        ),
      );
      final controller = _controller(pipedServices: pipedServices)
        ..playlistType.value = 'piped';
      controller.updatePlaylistMembership('piped-a', [
        'song-0',
        'song-1',
        'song-2',
      ]);

      final result = await controller.removeSongsFromPlaylist([
        _song('song-0'),
        _song('song-2'),
      ], 'piped-a');

      expect(result, PlaylistRemoveStatus.removed);
      // Descending so the lower index stays valid: index 2 then index 0.
      expect(
        pipedServices.requestedRemovals.map((request) => request.index),
        [2, 0],
      );
      expect(controller.playlistSongIds['piped-a'], {'song-1'});
    });
  });
}

AddToPlaylistController _controller({TestPipedServices? pipedServices}) {
  return AddToPlaylistController(
    playlistRepository: HivePlaylistRepository(),
    pipedServices: pipedServices ?? TestPipedServices(),
  );
}

Future<TestPipedServices> _putPipedServices(TestPipedServices service) async {
  return service;
}

Playlist _playlist(String id) {
  return Playlist(
    title: id,
    playlistId: id,
    thumbnailUrl: Playlist.thumbPlaceholderUrl,
  );
}

Map<String, dynamic> _localPlaylistJson(String id) {
  return Playlist(
    title: id,
    playlistId: id,
    thumbnailUrl: Playlist.thumbPlaceholderUrl,
    isCloudPlaylist: false,
  ).toJson();
}

MediaItem _song(String id) {
  return MediaItem(
    id: id,
    title: id,
    artist: 'artist',
    duration: const Duration(seconds: 60),
    artUri: Uri.parse(Playlist.thumbPlaceholderUrl),
    extras: const {
      'album': null,
      'artists': [
        {'name': 'artist'},
      ],
      'length': '1:00',
      'url': 'https://example.com/song',
      'date': 1,
      'trackDetails': null,
      'year': null,
    },
  );
}
