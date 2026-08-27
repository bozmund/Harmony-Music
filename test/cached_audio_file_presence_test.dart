import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A Hive cache entry is not proof the audio file still exists.
///
/// On Windows the cache lives in `%TEMP%`, which Storage Sense empties behind
/// the app's back — the directory was found completely empty while the database
/// still claimed the songs were cached. Handing just_audio a `file://` URL for a
/// missing file does not raise: the player sits in `loading` indefinitely, which
/// presented as a cloud handoff that spun forever and never produced sound.
///
/// Source-level assertions, matching the convention of the other architecture
/// tests here: the real path needs a platform audio player and a populated Hive
/// box, neither of which exists under `flutter test`.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/services/audio_handler.dart').readAsStringSync();
  });

  group('cached audio must be verified on disk', () {
    test('checkNGetUrl drops a cache entry whose file is gone', () {
      expect(
        source.contains('final cachedFile = File(cachedPath);') &&
            source.contains('await cachedFile.exists()'),
        isTrue,
        reason: 'the cache branch must confirm the file exists on disk',
      );
      expect(
        source.contains('deleteCachedSong(songId)'),
        isTrue,
        reason: 'a stale entry must be dropped, not left to fail again',
      );
    });

    test('the preload path also refuses a missing cached file', () {
      final index = source.indexOf(
        'Future<HMStreamingData?> _cachedStreamInfoForSong',
      );
      expect(index, greaterThan(-1), reason: 'preload helper not found');

      final method = source.substring(index, index + 600);
      expect(
        method.contains('.exists()'),
        isTrue,
        reason: 'preloading a missing file stalls the player just the same',
      );
    });
  });

  group('cloud handoff must not block on the audio load', () {
    test('playback start is bounded by a timeout', () {
      final receiver = File(
        'lib/services/cloud/cloud_playback_receiver.dart',
      ).readAsStringSync();

      expect(
        receiver.contains('_playbackStartTimeout'),
        isTrue,
        reason: 'a stalled load must not wedge the ack, spinner and publishing',
      );
      expect(
        receiver.contains('.timeout('),
        isTrue,
        reason: 'playByIndex must be awaited with a bound',
      );
    });
  });
}
