import 'dart:async';

import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/material.dart';
import 'package:harmonymusic/base_class/playlist_album_screen_con_base.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/utils/helper.dart';
import 'package:harmonymusic/utils/observable_state.dart';

import '../../../mixins/additional_operation_mixin.dart';
import '../Home/home_screen_controller.dart';
import '../Library/library_controller.dart';

class AlbumScreenControllerRegistry {
  static final _controllers = <String, AlbumScreenController>{};

  static void register(String tag, AlbumScreenController controller) {
    _controllers[tag] = controller;
  }

  static void unregister(String tag, AlbumScreenController controller) {
    if (_controllers[tag] == controller) {
      _controllers.remove(tag);
    }
  }

  static AlbumScreenController? maybeOf(String? tag) =>
      tag == null ? null : _controllers[tag];
}

///AlbumScreenController handles album screen
///
///Album title,image,songs
class AlbumScreenController extends PlaylistAlbumScreenControllerBase
    with AdditionalOperationMixin {
  AlbumScreenController({
    required super.musicServices,
    required super.playlistRepository,
    required super.libraryRepository,
    required HomeScreenController homeScreenController,
  }) : _homeScreenController = homeScreenController;

  final HomeScreenController _homeScreenController;

  final album = ObservableValue(Album(
    title: "",
    browseId: "",
    thumbnailUrl: "",
    artists: [],
  ));
  final isOfflineAlbum = ObservableValue(false);

  // Title animation
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  AnimationController get animationController => _animationController;
  Animation<double> get scaleAnimation => _scaleAnimation;

  void initialize({
    required (Album?, String) args,
    required TickerProvider vsync,
  }) {
    _animationController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 400),
    );

    _scaleAnimation = Tween<double>(
      begin: 0,
      end: 1.0,
    ).animate(animationController);

    unawaited(fetchAlbumDetails(args.$1, args.$2));
    unawaited(
      Future.delayed(const Duration(milliseconds: 200), () {
        if (isClosed) return;
        _homeScreenController.whenHomeScreenOnTop();
      }),
    );
  }

  @override
  Future<void> fetchAlbumDetails(Album? album_, String albumId) async {
    final generation = beginAsyncLoad();
    try {
      if (album_ != null) {
        album.value = album_;
        notifyListeners();
        await animationController.forward();
        if (!isAsyncLoadActive(generation)) return;
      }
      // Check if the album is offline
      if (!await checkIfAddedToLibrary(albumId)) {
        if (!isAsyncLoadActive(generation)) return;
        // Fetch album details online
        final content = await musicServices.getPlaylistOrAlbumSongs(
          albumId: albumId,
        );
        if (!isAsyncLoadActive(generation)) return;
        content['browseId'] = albumId;
        album.value = Album.fromJson(content);
        notifyListeners();
        await animationController.forward();
        if (!isAsyncLoadActive(generation)) return;
        songList.value = List<MediaItem>.from(content['tracks']);
        notifyListeners();
      } else {
        if (!isAsyncLoadActive(generation)) return;
        // If the album is offline, fetch the songs from the local database
        // Album details are already fetched in _checkIfAddedToLibrary method
        final songs = await playlistRepository.getPlaylistSongs(albumId);
        if (!isAsyncLoadActive(generation)) return;
        songList.value = songs;
        notifyListeners();
      }
      checkDownloadStatus();
      if (!isAsyncLoadActive(generation)) return;
      isContentFetched.value = true;
      notifyListeners();
    } catch (e) {
      // Handle any errors that occur during the fetch
      printERROR("Error fetching album details: $e");
    }
  }

  @override
  Future<bool> checkIfAddedToLibrary(String id) async {
    final albums = await libraryRepository.getAlbums();
    if (isClosed) return false;
    Album? savedAlbum;
    for (final album in albums) {
      if (album.browseId == id) {
        savedAlbum = album;
        break;
      }
    }
    isAddedToLibrary.value = savedAlbum != null;
    if (savedAlbum != null) album.value = savedAlbum;
    notifyListeners();
    return isAddedToLibrary.value;
  }

  @override
  Future<bool> addNRemoveFromLibrary(content, {bool add = true}) async {
    try {
      final id = content.browseId;
      if (add) {
        await libraryRepository.saveAlbum(content);
        await updateSongsIntoDb();
      } else {
        await libraryRepository.deleteAlbum(id);
        await playlistRepository.deletePlaylistSongBox(id);
      }
      isAddedToLibrary.value = add;
      notifyListeners();

      //Update frontend
      await LibraryAlbumsControllerRegistry.current?.refreshLib();

      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> updateSongsIntoDb() async {
    await playlistRepository.replacePlaylistSongs(
      album.value.browseId,
      songList.toList(),
    );
  }

  void close() {
    closeController();
    tempListContainer.clear();
    _animationController.dispose();
    _homeScreenController.whenHomeScreenOnTop();
  }

  @override
  Future<void> deleteMultipleSongs(List<MediaItem> songs) async {}

  @override
  void fetchPlaylistDetails(Playlist? playlist_, String playlistId) {}

  @override
  void syncPlaylistSongs() {}
}
