import 'package:audio_service/audio_service.dart';

/// First-song-derived playlist artwork.
///
/// [emptyFallbackUrl] encodes the empty-playlist policy:
/// * built-in library playlists pass the placeholder URL, so their tiles fall
///   back to the icon look when emptied;
/// * user-created playlists pass [currentUrl], so they keep their last artwork
///   instead of resetting to the placeholder.
String resolvePlaylistArt({
  required String currentUrl,
  required List<MediaItem> songs,
  required String emptyFallbackUrl,
}) {
  if (songs.isEmpty) return emptyFallbackUrl;
  final art = songs.first.artUri?.toString();
  if (art == null || art.isEmpty) return currentUrl;
  return art;
}
