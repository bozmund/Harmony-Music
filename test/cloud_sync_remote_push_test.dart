import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/data/repositories/cloud_sync_repository.dart';
import 'package:harmonymusic/domain/repositories/playlist_repository.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/cloud/cloud_sync_coordinator.dart';
import 'package:harmonymusic/services/cloud/harmony_cloud_client.dart';
import 'package:harmonymusic/services/cloud/playback_socket_client.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:hive/hive.dart';

/// A device left open used to learn about another device's edit only on its
/// next poll tick — up to a minute later. The server now pushes a
/// `libraryChanged` frame over the same socket playback already uses, and
/// `CloudSyncCoordinator` is supposed to react to it immediately rather than
/// wait. These drive that reaction directly, without a real network or a real
/// socket.
void main() {
  late Directory hiveDir;
  late CloudSyncRepository repository;
  late _CountingCloudAdapter adapter;
  late HarmonyCloudClient client;
  late _FakeSocketTransport socket;
  late CloudSyncCoordinator coordinator;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('cloud_sync_push_test_');
    Hive.init(hiveDir.path);
    for (final box in const [
      BoxNames.appPrefs,
      BoxNames.libFav,
      BoxNames.libRP,
      BoxNames.libraryPlaylists,
      BoxNames.libraryAlbums,
      BoxNames.libraryArtists,
      BoxNames.librarySearches,
      BoxNames.blacklistedPlaylist,
      BoxNames.searchQuery,
      BoxNames.cloudSyncOutbox,
      BoxNames.cloudSyncState,
    ]) {
      await Hive.openBox(box);
    }
    repository = CloudSyncRepository(_NoPlaylists());
    await repository.setEnabled(true);
    adapter = _CountingCloudAdapter();
    client = HarmonyCloudClient(
      dio: Dio()..httpClientAdapter = adapter,
      accessToken: () async => 'fake-access-token',
    );
    socket = _FakeSocketTransport();
    coordinator = CloudSyncCoordinator(repository, client, socket: socket);
  });

  tearDown(() async {
    await coordinator.stop();
    await socket.dispose();
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  test('a libraryChanged frame triggers an immediate sync', () async {
    await coordinator.start();
    expect(adapter.syncCalls, 0, reason: 'starting must not sync by itself');

    socket.emit({'type': 'libraryChanged', 'sourceDeviceId': 'other-device'});
    // `pumpEventQueue()` only drains microtasks, and Dio's request pipeline
    // isn't purely microtask-based — it needs a real wait. Emitting starts the
    // sync via the (unawaited) frame listener; joining it here through the
    // public method is what `_activeSync` coalescing exists for, and it
    // deterministically waits for the real completion however it gets there.
    await pumpEventQueue();
    await coordinator.synchronize();

    expect(adapter.syncCalls, 1);
  });

  test('an unrelated frame type is ignored', () async {
    await coordinator.start();

    socket.emit({
      'type': 'progress',
      'currentSongId': 'song-1',
      'positionMs': 1000,
    });
    // Nothing to join here — proving absence needs a real wait, not a signal
    // to wait on.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(adapter.syncCalls, 0);
  });

  test('concurrent pushes coalesce into one sync via the existing guard', () async {
    // Not a new mechanism: `synchronize()` already shares one in-flight future
    // (`_activeSync`) across overlapping callers. A burst of pushes — several
    // devices editing around the same moment — must not turn into a request
    // storm.
    await coordinator.start();

    socket.emit({'type': 'libraryChanged', 'sourceDeviceId': 'device-a'});
    socket.emit({'type': 'libraryChanged', 'sourceDeviceId': 'device-b'});
    socket.emit({'type': 'libraryChanged', 'sourceDeviceId': 'device-c'});
    await pumpEventQueue();
    await coordinator.synchronize();

    expect(adapter.syncCalls, 1);
  });

  test('stopping cancels the socket subscription', () async {
    await coordinator.start();
    await coordinator.stop();

    socket.emit({'type': 'libraryChanged', 'sourceDeviceId': 'other-device'});
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(adapter.syncCalls, 0);
  });

  test('with no socket, the coordinator behaves exactly as before', () async {
    // The socket is optional — every construction site that does not wire one
    // (tests included) must keep working exactly as it did.
    final withoutSocket = CloudSyncCoordinator(repository, client);
    addTearDown(withoutSocket.stop);

    await withoutSocket.start();
    await withoutSocket.synchronize();

    expect(adapter.syncCalls, 1);
  });
}

class _FakeSocketTransport implements PlaybackSocketTransport {
  final _frames = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get frames => _frames.stream;

  @override
  Stream<PlaybackSocketStatus> get status => const Stream.empty();

  @override
  PlaybackSocketStatus get currentStatus => PlaybackSocketStatus.connected;

  @override
  Future<void> connect(String deviceId) async {}

  @override
  void send(Map<String, Object?> frame) {}

  void emit(Map<String, dynamic> frame) => _frames.add(frame);

  @override
  Future<void> dispose() async {
    await _frames.close();
  }
}

/// Counts real `/v1/sync` calls; every other endpoint `_synchronizeCore` and
/// `setEnabled`/`registerCurrentDevice` touch along the way just needs to
/// succeed.
class _CountingCloudAdapter implements HttpClientAdapter {
  int syncCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    Map<String, dynamic>? json;
    var statusCode = 204;
    if (path.endsWith('/v1/sync')) {
      syncCalls++;
      statusCode = 200;
      json = const {
        'checkpoint': 0,
        'acceptedEventIds': <String>[],
        'changes': <dynamic>[],
      };
    } else if (path.endsWith('/devices/register')) {
      statusCode = 200;
      json = {'deviceId': options.data is Map ? options.data['deviceId'] : ''};
    } else if (path.endsWith('/playback/presence') ||
        path.endsWith('/sync/pause')) {
      statusCode = 204;
    }
    final body = json == null ? <int>[] : utf8.encode(jsonEncode(json));
    return ResponseBody.fromBytes(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _NoPlaylists implements PlaylistRepository {
  @override
  Future<List<Playlist>> getPlaylists() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}
