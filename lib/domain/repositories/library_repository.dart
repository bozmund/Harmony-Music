import 'package:audio_service/audio_service.dart';

import '../../models/album.dart';
import '../../models/artist.dart';

abstract class LibraryRepository {
  Future<List<MediaItem>> getCachedSongs();
  Future<List<MediaItem>> getDownloadedSongs();
  Future<List<MediaItem>> getAllLibrarySongs();

  /// Writes [duration] into the stored cached/downloaded copies of [songId]
  /// when they were saved without one (some sources omit duration until the
  /// track is actually played). Existing durations are left untouched.
  /// Returns true if any stored entry was updated.
  Future<bool> backfillSongDuration(String songId, Duration duration);
  Future<void> deleteCachedSong(String songId);
  Future<void> deleteDownloadedSong(String songId);
  Future<bool> isDownloaded(String songId);
  Future<bool> isFavorite(String songId);
  Future<void> setFavorite(MediaItem song, bool favorite);
  Future<List<MediaItem>> getFavoriteSongs();
  Future<List<MediaItem>> getFavoriteNotDownloadedSongs();
  Future<List<MediaItem>> getRecentlyPlayedSongs();
  Future<void> addRecentlyPlayedSong(MediaItem song);
  Future<List<MediaItem>> getImportDuplicateSongs();
  Future<List<MediaItem>> getImportReviewSongs();
  Future<void> addImportDuplicate(MediaItem song);
  Future<void> addImportReview(MediaItem song);
  Future<void> deleteImportDuplicate(String songId);
  Future<void> deleteImportReview(String songId);
  Future<void> clearImportReview();
  Future<void> clearImportDuplicates();
  Future<List<Album>> getAlbums();
  Future<void> saveAlbum(Album album);
  Future<void> deleteAlbum(String albumId);
  Future<List<Artist>> getArtists();
  Future<void> saveArtist(Artist artist);
  Future<void> deleteArtist(String artistId);
  Future<List<String>> getSearches();
  Future<void> addSearch(String query);
  Future<void> deleteSearch(String query);

  /// Applies [transform] to every song JSON map stored in the library song
  /// boxes (favorites, recently played, import review/duplicates). A null
  /// return leaves the entry unchanged. Used after a backup restore to fix
  /// absolute file paths persisted by another install.
  Future<void> rewriteSongEntries(
    Map<dynamic, dynamic>? Function(Map<dynamic, dynamic> song) transform,
  );
}
