import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

import '../../domain/repositories/library_repository.dart';
import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/media_Item_builder.dart';
import '../../services/constant.dart';
import 'hive_repository_helpers.dart';

class HiveLibraryRepository implements LibraryRepository {
  Future<Box> _open(String name) => Hive.openBox(name);

  List<MediaItem> _mediaItems(Box box) => box.values
      .map<MediaItem?>((item) => MediaItemBuilder.fromJson(item))
      .whereType<MediaItem>()
      .toList();

  @override
  Future<List<MediaItem>> getCachedSongs() async =>
      _mediaItems(await _open(BoxNames.songsCache));

  @override
  Future<List<MediaItem>> getDownloadedSongs() async =>
      _mediaItems(await _open(BoxNames.songDownloads));

  @override
  Future<List<MediaItem>> getAllLibrarySongs() async => [
    ...await getCachedSongs(),
    ...await getDownloadedSongs(),
  ];

  @override
  Future<bool> backfillSongDuration(String songId, Duration duration) async {
    final seconds = duration.inSeconds;
    if (seconds <= 0) return false;
    var updated = false;
    for (final boxName in const [BoxNames.songsCache, BoxNames.songDownloads]) {
      final box = await _open(boxName);
      final value = box.get(songId);
      if (value is! Map) continue;
      final existing = value['duration'];
      if (existing is int && existing > 0) continue;
      await box.put(
        songId,
        Map<dynamic, dynamic>.from(value)..['duration'] = seconds,
      );
      updated = true;
    }
    return updated;
  }

  @override
  Future<void> deleteCachedSong(String songId) async =>
      (await _open(BoxNames.songsCache)).delete(songId);

  @override
  Future<void> deleteDownloadedSong(String songId) async =>
      (await _open(BoxNames.songDownloads)).delete(songId);

  @override
  Future<bool> isDownloaded(String songId) async =>
      (await _open(BoxNames.songDownloads)).containsKey(songId);

  @override
  Future<bool> isFavorite(String songId) async =>
      (await _open(BoxNames.libFav)).containsKey(songId);

  @override
  Future<void> setFavorite(MediaItem song, bool favorite) async {
    final box = await _open(BoxNames.libFav);
    if (favorite) {
      await box.put(song.id, MediaItemBuilder.toJson(song));
    } else {
      await box.delete(song.id);
    }
  }

  @override
  Future<List<MediaItem>> getFavoriteSongs() async =>
      _mediaItems(await _open(BoxNames.libFav));

  @override
  Future<List<MediaItem>> getFavoriteNotDownloadedSongs() async {
    final favorites = await getFavoriteSongs();
    final downloads = (await getDownloadedSongs())
        .map((song) => song.id)
        .toSet();
    return favorites.where((song) => !downloads.contains(song.id)).toList();
  }

  @override
  Future<List<MediaItem>> getRecentlyPlayedSongs() async =>
      _mediaItems(await _open(BoxNames.libRP));

  @override
  Future<void> addRecentlyPlayedSong(MediaItem song) async {
    final box = await _open(BoxNames.libRP);
    if (box.keys.length >= 30) {
      await box.deleteAt(0);
    }
    final valuesCopy = box.values.toList();
    for (var i = valuesCopy.length - 1; i >= 0; i--) {
      if (valuesCopy[i]['videoId'] == song.id) {
        await box.deleteAt(i);
      }
    }
    await box.add(MediaItemBuilder.toJson(song));
  }

  @override
  Future<List<MediaItem>> getImportDuplicateSongs() async =>
      _mediaItems(await _open(BoxNames.libImportDuplicates));

  @override
  Future<List<MediaItem>> getImportReviewSongs() async =>
      _mediaItems(await _open(BoxNames.libImportReview));

  @override
  Future<void> addImportDuplicate(MediaItem song) async => (await _open(
    BoxNames.libImportDuplicates,
  )).put(song.id, MediaItemBuilder.toJson(song));

  @override
  Future<void> addImportReview(MediaItem song) async => (await _open(
    BoxNames.libImportReview,
  )).put(song.id, MediaItemBuilder.toJson(song));

  @override
  Future<void> deleteImportDuplicate(String songId) async =>
      (await _open(BoxNames.libImportDuplicates)).delete(songId);

  @override
  Future<void> deleteImportReview(String songId) async =>
      (await _open(BoxNames.libImportReview)).delete(songId);

  @override
  Future<void> clearImportReview() async =>
      (await _open(BoxNames.libImportReview)).clear();

  @override
  Future<void> clearImportDuplicates() async =>
      (await _open(BoxNames.libImportDuplicates)).clear();

  @override
  Future<List<Album>> getAlbums() async => (await _open(BoxNames.libraryAlbums))
      .values
      .map<Album?>((item) => Album.fromJson(item))
      .whereType<Album>()
      .toList();

  @override
  Future<void> saveAlbum(Album album) async =>
      (await _open(BoxNames.libraryAlbums)).put(album.browseId, album.toJson());

  @override
  Future<void> deleteAlbum(String albumId) async =>
      (await _open(BoxNames.libraryAlbums)).delete(albumId);

  @override
  Future<List<Artist>> getArtists() async =>
      (await _open(BoxNames.libraryArtists)).values
          .map<Artist?>((item) => Artist.fromJson(item))
          .whereType<Artist>()
          .toList();

  @override
  Future<void> saveArtist(Artist artist) async => (await _open(
    BoxNames.libraryArtists,
  )).put(artist.browseId, artist.toJson());

  @override
  Future<void> deleteArtist(String artistId) async =>
      (await _open(BoxNames.libraryArtists)).delete(artistId);

  @override
  Future<List<String>> getSearches() async => (await _open(
    BoxNames.librarySearches,
  )).values.whereType<String>().toList();

  @override
  Future<void> addSearch(String query) async {
    final box = await _open(BoxNames.librarySearches);
    if (!box.values.contains(query)) await box.add(query);
  }

  @override
  Future<void> deleteSearch(String query) async {
    final box = await _open(BoxNames.librarySearches);
    final key = box.keys.firstWhereOrNull((key) => box.get(key) == query);
    if (key != null) await box.delete(key);
  }

  @override
  Future<void> rewriteSongEntries(
    Map<dynamic, dynamic>? Function(Map<dynamic, dynamic> song) transform,
  ) async {
    const songBoxNames = [
      BoxNames.libFav,
      BoxNames.libRP,
      BoxNames.libImportDuplicates,
      BoxNames.libImportReview,
    ];
    for (final boxName in songBoxNames) {
      final box = await _open(boxName);
      for (final key in box.keys.toList()) {
        final value = box.get(key);
        if (value is! Map) continue;
        final rewritten = transform(value);
        if (rewritten != null) {
          await box.put(key, rewritten);
        }
      }
    }
  }
}
