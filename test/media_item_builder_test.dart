import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';

void main() {
  group('MediaItemBuilder.displayDuration', () {
    test('uses existing length text when present', () {
      final song = MediaItem(
        id: 'song-id',
        title: 'Song',
        extras: const {'length': '2:25'},
      );

      expect(MediaItemBuilder.displayDuration(song), '2:25');
    });

    test('falls back to media duration when length text is missing', () {
      final song = MediaItem(
        id: 'song-id',
        title: 'Song',
        duration: const Duration(milliseconds: 148261),
        extras: const {'length': null},
      );

      expect(MediaItemBuilder.displayDuration(song), '2:28');
    });

    test('formats hour-long media with hours', () {
      final song = MediaItem(
        id: 'song-id',
        title: 'Song',
        duration: const Duration(hours: 1, minutes: 2, seconds: 3),
        extras: const {'length': null},
      );

      expect(MediaItemBuilder.displayDuration(song), '01:02:03');
    });
  });
}
