import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

import '../../domain/repositories/playlist_repository.dart';
import '../../models/media_Item_builder.dart';
import '../../models/playlist.dart';
import '../../services/constant.dart';
import 'hive_repository_helpers.dart';

class HivePlaylistRepository implements PlaylistRepository {
  Future<Box> get _playlistBox => Hive.openBox(BoxNames.libraryPlaylists);

  Future<Box> _songBox(String playlistId) => Hive.openBox(playlistId);

  @override
  Future<Playlist?> getPlaylist(String playlistId) async {
    final box = await _playlistBox;
    final value = box.get(playlistId);
    return value == null ? null : Playlist.fromJson(value);
  }

  @override
  Future<List<Playlist>> getPlaylists() async {
    final box = await _playlistBox;
    return box.values
        .map<Playlist?>((item) => Playlist.fromJson(item))
        .whereType<Playlist>()
        .toList();
  }

  @override
  Future<void> savePlaylist(Playlist playlist) async {
    final box = await _playlistBox;
    await box.put(playlist.playlistId, playlist.toJson());
  }

  @override
  Future<void> savePlaylists(List<Playlist> playlists) async {
    final box = await _playlistBox;
    for (final playlist in playlists) {
      await box.put(playlist.playlistId, playlist.toJson());
    }
  }

  @override
  Future<void> updatePlaylist(Playlist playlist) => savePlaylist(playlist);

  @override
  Future<void> deletePlaylist(String playlistId) async {
    final box = await _playlistBox;
    await box.delete(playlistId);
    await deletePlaylistSongBox(playlistId);
  }

  @override
  Future<List<MediaItem>> getPlaylistSongs(String playlistId) async {
    final box = await _songBox(playlistId);
    return box.values
        .map<MediaItem?>((item) => MediaItemBuilder.fromJson(item))
        .whereType<MediaItem>()
        .toList();
  }

  @override
  Future<void> addSongsToPlaylist(
    String playlistId,
    List<MediaItem> songs,
  ) async {
    final box = await _songBox(playlistId);
    final existingIds = box.values
        .map((item) => item is Map ? item['videoId'] : null)
        .whereType<String>()
        .toSet();
    for (final song in songs) {
      if (!existingIds.contains(song.id)) {
        await box.add(MediaItemBuilder.toJson(song));
      }
    }
  }

  @override
  Future<void> putSongInPlaylist(String playlistId, MediaItem song) async {
    final box = await _songBox(playlistId);
    await box.put(song.id, MediaItemBuilder.toJson(song));
  }

  @override
  Future<void> removeSongsFromPlaylist(
    String playlistId,
    List<MediaItem> songs,
  ) async {
    final ids = songs.map((song) => song.id).toSet();
    final box = await _songBox(playlistId);
    final keysToRemove = box.keys.where((key) {
      final value = box.get(key);
      return value is Map && ids.contains(value['videoId']);
    }).toList();
    for (final key in keysToRemove) {
      await box.delete(key);
    }
  }

  @override
  Future<void> clearPlaylistSongs(String playlistId) async {
    final box = await _songBox(playlistId);
    await box.clear();
  }

  @override
  Future<void> replacePlaylistSongs(
    String playlistId,
    List<MediaItem> songs,
  ) async {
    final box = await _songBox(playlistId);
    await box.clear();
    for (final song in songs) {
      await box.add(MediaItemBuilder.toJson(song));
    }
  }

  @override
  Future<Set<String>> getPlaylistSongIds(String playlistId) async {
    final box = await _songBox(playlistId);
    return box.values
        .map((item) => item is Map ? item['videoId'] : null)
        .whereType<String>()
        .toSet();
  }

  @override
  Future<bool> playlistContainsSong(String playlistId, String songId) async =>
      (await getPlaylistSongIds(playlistId)).contains(songId);

  @override
  Future<void> deletePlaylistSongBox(String playlistId) async {
    final box = await _songBox(playlistId);
    await box.deleteFromDisk();
  }

  Future<Box> get _blacklistBox => Hive.openBox('blacklistedPlaylist');

  @override
  Future<List<String>> getBlacklistedPlaylistIds() async =>
      (await _blacklistBox).values.whereType<String>().toList();

  @override
  Future<void> addBlacklistedPlaylistId(String playlistId) async {
    final box = await _blacklistBox;
    if (!box.values.contains(playlistId)) await box.add(playlistId);
  }

  @override
  Future<void> removeBlacklistedPlaylistId(String playlistId) async {
    final box = await _blacklistBox;
    final key = box.keys.firstWhereOrNull((key) => box.get(key) == playlistId);
    if (key != null) await box.delete(key);
  }

  @override
  Future<void> clearBlacklistedPlaylistIds() async =>
      (await _blacklistBox).clear();

  @override
  Future<void> rewritePlaylistSongEntries(
    Map<dynamic, dynamic>? Function(Map<dynamic, dynamic> song) transform,
  ) async {
    final playlistBox = await _playlistBox;
    for (final playlistKey in playlistBox.keys.toList()) {
      final songBox = await _songBox(playlistKey.toString());
      for (final key in songBox.keys.toList()) {
        final value = songBox.get(key);
        if (value is! Map) continue;
        final rewritten = transform(value);
        if (rewritten != null) {
          await songBox.put(key, rewritten);
        }
      }
    }
  }
}
