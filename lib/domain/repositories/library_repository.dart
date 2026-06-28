import 'package:audio_service/audio_service.dart';

import '../../models/album.dart';
import '../../models/artist.dart';

abstract class LibraryRepository {
  Future<List<MediaItem>> getCachedSongs();
  Future<List<MediaItem>> getDownloadedSongs();
  Future<List<MediaItem>> getAllLibrarySongs();
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
}
