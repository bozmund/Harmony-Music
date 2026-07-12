import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/utils/playlist_art.dart';

void main() {
  const placeholder = 'https://example.com/placeholder.png';
  const currentArt = 'https://example.com/current.jpg';

  MediaItem song({Uri? artUri}) =>
      MediaItem(id: 's1', title: 'Song', artUri: artUri);

  group('resolvePlaylistArt', () {
    test('empty songs -> emptyFallbackUrl (built-in policy: placeholder)', () {
      final result = resolvePlaylistArt(
        currentUrl: currentArt,
        songs: const [],
        emptyFallbackUrl: placeholder,
      );
      expect(result, placeholder);
    });

    test('empty songs -> emptyFallbackUrl (user policy: keep current)', () {
      final result = resolvePlaylistArt(
        currentUrl: currentArt,
        songs: const [],
        emptyFallbackUrl: currentArt,
      );
      expect(result, currentArt);
    });

    test('non-empty -> first song artUri', () {
      final result = resolvePlaylistArt(
        currentUrl: currentArt,
        songs: [
          song(artUri: Uri.parse('https://img.example/first.jpg')),
          song(artUri: Uri.parse('https://img.example/second.jpg')),
        ],
        emptyFallbackUrl: placeholder,
      );
      expect(result, 'https://img.example/first.jpg');
    });

    test('first song without artUri -> currentUrl', () {
      final result = resolvePlaylistArt(
        currentUrl: currentArt,
        songs: [song()],
        emptyFallbackUrl: placeholder,
      );
      expect(result, currentArt);
    });
  });
}
