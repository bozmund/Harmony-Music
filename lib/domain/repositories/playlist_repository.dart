import 'package:audio_service/audio_service.dart';

import '../../models/playlist.dart';

abstract class PlaylistRepository {
  Future<List<Playlist>> getPlaylists();
  Future<void> savePlaylist(Playlist playlist);
  Future<void> savePlaylists(List<Playlist> playlists);
  Future<void> updatePlaylist(Playlist playlist);
  Future<void> deletePlaylist(String playlistId);
  Future<List<MediaItem>> getPlaylistSongs(String playlistId);
  Future<void> addSongsToPlaylist(String playlistId, List<MediaItem> songs);
  Future<void> putSongInPlaylist(String playlistId, MediaItem song);
  Future<void> removeSongsFromPlaylist(
    String playlistId,
    List<MediaItem> songs,
  );
  Future<void> clearPlaylistSongs(String playlistId);
  Future<void> replacePlaylistSongs(String playlistId, List<MediaItem> songs);
  Future<Set<String>> getPlaylistSongIds(String playlistId);
  Future<bool> playlistContainsSong(String playlistId, String songId);
  Future<void> deletePlaylistSongBox(String playlistId);
  Future<List<String>> getBlacklistedPlaylistIds();
  Future<void> addBlacklistedPlaylistId(String playlistId);
  Future<void> removeBlacklistedPlaylistId(String playlistId);
}
