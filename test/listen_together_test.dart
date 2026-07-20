import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/listen_together/listen_together_controller.dart';
import 'package:harmonymusic/services/listen_together/session_message.dart';
import 'package:harmonymusic/services/listen_together/session_payload.dart';
import 'package:harmonymusic/services/listen_together/sync_clock.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';

void main() {
  group('ListenTogetherController queue payloads', () {
    test('strips host-local file urls from synced queue items', () {
      final json = ListenTogetherController.sessionSafeQueueJson(
        _mediaItem(url: 'file:///data/user/0/app/files/Music/song.opus'),
      );

      expect(json, isNot(contains('url')));
      expect(json['thumbnails'], [
        {'url': 'https://img.example/song.jpg'},
      ]);
    });

    test('keeps remote stream urls in synced queue items', () {
      final json = ListenTogetherController.sessionSafeQueueJson(
        _mediaItem(url: 'https://stream.example/audio.m4a'),
      );

      expect(json['url'], 'https://stream.example/audio.m4a');
    });
  });

  group('SessionMessage encoding', () {
    test('enqueue command strips local URLs and reconstructs a song', () {
      final original = _mediaItem(url: 'file:///private/song.opus');
      final message = SessionMessage.command(
        senderId: 'guest-1',
        senderName: 'Guest',
        command: SessionCommand.enqueue(sessionSafeSongJson(original)),
      );

      final decoded = SessionMessage.decode(message.encode()).command;
      expect(decoded.action, SessionCommand.actionEnqueue);
      expect(decoded.songJson, isNotNull);
      expect(decoded.songJson, isNot(contains('url')));

      final rebuilt = MediaItemBuilder.fromJson(decoded.songJson!);
      expect(rebuilt.id, original.id);
      expect(rebuilt.title, original.title);
      expect(rebuilt.artUri, original.artUri);
    });

    test('enqueueList preserves song order', () {
      final message = SessionMessage.command(
        senderId: 'guest-1',
        senderName: 'Guest',
        command: SessionCommand.enqueueList([
          {'videoId': 'first', 'title': 'First'},
          {'videoId': 'second', 'title': 'Second'},
          {'videoId': 'third', 'title': 'Third'},
        ]),
      );

      final songs = SessionMessage.decode(message.encode()).command.songsJson;
      expect(songs.map((song) => song['videoId']), [
        'first',
        'second',
        'third',
      ]);
    });

    test('helloAck mode is optional and defaults safely to sync', () {
      final party = SessionMessage.helloAck(
        senderId: 'host',
        senderName: 'Host',
        clientTimeMs: 1,
        hostTimeMs: 2,
        mode: SessionPlaybackMode.party.wireName,
      );
      final legacy = SessionMessage.helloAck(
        senderId: 'host',
        senderName: 'Host',
        clientTimeMs: 1,
        hostTimeMs: 2,
      );

      expect(
        SessionPlaybackMode.fromWire(
          SessionMessage.decode(party.encode()).sessionModeName,
        ),
        SessionPlaybackMode.party,
      );
      expect(
        SessionPlaybackMode.fromWire(
          SessionMessage.decode(legacy.encode()).sessionModeName,
        ),
        SessionPlaybackMode.sync,
      );
      expect(
        SessionPlaybackMode.fromWire('future-mode'),
        SessionPlaybackMode.sync,
      );
    });

    test('playbackSync round-trips through encode/decode', () {
      final original = SessionMessage.playbackSync(
        senderId: 'host-1',
        senderName: 'Host',
        snapshot: const PlaybackSnapshot(
          songId: 'abc123',
          index: 3,
          positionMs: 42000,
          playing: true,
          hostTimestampMs: 1700000000000,
          shuffle: true,
          loop: false,
        ),
      );

      final decoded = SessionMessage.decode(original.encode());

      expect(decoded.type, SessionMessageType.playbackSync);
      expect(decoded.senderId, 'host-1');
      final snap = decoded.snapshot;
      expect(snap.songId, 'abc123');
      expect(snap.index, 3);
      expect(snap.positionMs, 42000);
      expect(snap.playing, isTrue);
      expect(snap.hostTimestampMs, 1700000000000);
      expect(snap.shuffle, isTrue);
      expect(snap.loop, isFalse);
    });

    test('byte encoding round-trips (used by the Bluetooth transport)', () {
      final original = SessionMessage.command(
        senderId: 'guest-9',
        senderName: 'Guest',
        command: SessionCommand.seek(const Duration(milliseconds: 12345)),
      );

      final decoded = SessionMessage.decodeBytes(original.encodeBytes());

      expect(decoded.type, SessionMessageType.command);
      final cmd = decoded.command;
      expect(cmd.action, SessionCommand.actionSeek);
      expect(cmd.seekPosition, const Duration(milliseconds: 12345));
    });

    test('queueSync preserves order and index', () {
      final message = SessionMessage.queueSync(
        senderId: 'host',
        senderName: 'Host',
        queue: [
          {'videoId': 'a'},
          {'videoId': 'b'},
          {'videoId': 'c'},
        ],
        index: 2,
      );

      final decoded = SessionMessage.decode(message.encode());
      expect(decoded.queueIndex, 2);
      expect(decoded.queue.map((e) => e['videoId']).toList(), ['a', 'b', 'c']);
    });

    test('unknown/garbage decodes without throwing (defaults to bye)', () {
      final decoded = SessionMessage.fromJson({'type': 'nonsense'});
      expect(decoded.type, SessionMessageType.bye);
    });
  });

  group('session payload helpers', () {
    test('chunkList preserves order and leaves an empty list empty', () {
      expect(chunkList([1, 2, 3, 4, 5, 6, 7], 3), [
        [1, 2, 3],
        [4, 5, 6],
        [7],
      ]);
      expect(chunkList(<int>[], 3), isEmpty);
    });
  });

  group('SyncClock', () {
    test('offset estimation assumes symmetric latency', () {
      // Guest sent hello at t=1000, host replied at hostClock=6000,
      // ack arrived at t=1040 => rtt=40, host-now ~= 6000+20, offset ~= 4980.
      final offset = SyncClock.estimateOffsetMs(
        helloClientTimeMs: 1000,
        hostTimeMs: 6000,
        ackReceivedMs: 1040,
      );
      expect(offset, 6000 + 20 - 1040); // 4980
    });

    test('offset sample includes round trip time', () {
      final sample = SyncClock.estimateOffsetSample(
        helloClientTimeMs: 1000,
        hostTimeMs: 6000,
        ackReceivedMs: 1040,
      );

      expect(sample.rttMs, 40);
      expect(sample.offsetMs, 4980);
    });

    test('offset sample clamps negative round trip time', () {
      final sample = SyncClock.estimateOffsetSample(
        helloClientTimeMs: 1040,
        hostTimeMs: 6000,
        ackReceivedMs: 1000,
      );

      expect(sample.rttMs, 0);
      expect(sample.offsetMs, 5000);
    });

    test('expected position advances while playing', () {
      const snap = PlaybackSnapshot(
        songId: 's',
        index: 0,
        positionMs: 10000,
        playing: true,
        hostTimestampMs: 5000, // in host clock
      );
      // Guest clock offset +4980 means guest-now 300 maps to host 5280,
      // i.e. 280ms after the snapshot.
      final pos = SyncClock.expectedPositionMs(
        snap,
        clockOffsetMs: 4980,
        nowMs: 300,
      );
      expect(pos, 10000 + 280);
    });

    test('expected position is frozen while paused', () {
      const snap = PlaybackSnapshot(
        songId: 's',
        index: 0,
        positionMs: 10000,
        playing: false,
        hostTimestampMs: 5000,
      );
      final pos = SyncClock.expectedPositionMs(
        snap,
        clockOffsetMs: 4980,
        nowMs: 999999,
      );
      expect(pos, 10000);
    });

    test('never projects a negative elapsed', () {
      const snap = PlaybackSnapshot(
        songId: 's',
        index: 0,
        positionMs: 10000,
        playing: true,
        hostTimestampMs:
            100000, // snapshot in the future relative to now+offset
      );
      final pos = SyncClock.expectedPositionMs(
        snap,
        clockOffsetMs: 0,
        nowMs: 0,
      );
      expect(pos, 10000);
    });
  });
}

MediaItem _mediaItem({required String url}) {
  return MediaItem(
    id: 'song-1',
    title: 'Song',
    artist: 'Artist',
    duration: const Duration(seconds: 180),
    artUri: Uri.parse('https://img.example/song.jpg'),
    extras: {
      'url': url,
      'length': '3:00',
      'album': null,
      'artists': [
        {'name': 'Artist'},
      ],
      'date': null,
      'trackDetails': null,
      'year': null,
    },
  );
}
