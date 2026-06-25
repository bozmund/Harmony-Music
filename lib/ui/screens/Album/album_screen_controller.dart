import 'dart:async';

import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/base_class/playlist_album_screen_con_base.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/utils/helper.dart';
import 'package:hive/hive.dart';

import '../../../mixins/additional_operation_mixin.dart';
import '../../../models/media_Item_builder.dart';
import '../Home/home_screen_controller.dart';
import '../Library/library_controller.dart';

///AlbumScreenController handles album screen
///
///Album title,image,songs
class AlbumScreenController extends PlaylistAlbumScreenControllerBase
    with AdditionalOperationMixin, GetSingleTickerProviderStateMixin {
  final album =
      Album(title: "", browseId: "", thumbnailUrl: "", artists: []).obs;
  final isOfflineAlbum = false.obs;

  // Title animation
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  AnimationController get animationController => _animationController;
  Animation<double> get scaleAnimation => _scaleAnimation;

  @override
  void onInit() {
    super.onInit();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _scaleAnimation =
        Tween<double>(begin: 0, end: 1.0).animate(animationController);

    final args = Get.arguments as (Album?, String);
    unawaited(fetchAlbumDetails(args.$1, args.$2));
    unawaited(
      Future.delayed(const Duration(milliseconds: 200), () {
        if (isClosed) return;
        Get.find<HomeScreenController>().whenHomeScreenOnTop();
      }),
    );
  }

  @override
  Future<void> fetchAlbumDetails(Album? album_, String albumId) async {
    final generation = beginAsyncLoad();
    try {
      if (album_ != null) {
        album.value = album_;
        await animationController.forward();
        if (!isAsyncLoadActive(generation)) return;
      }
      // Check if the album is offline
      if (!await checkIfAddedToLibrary(albumId)) {
        if (!isAsyncLoadActive(generation)) return;
        // Fetch album details online
        final content =
            await musicServices.getPlaylistOrAlbumSongs(albumId: albumId);
        if (!isAsyncLoadActive(generation)) return;
        content['browseId'] = albumId;
        album.value = Album.fromJson(content);
        await animationController.forward();
        if (!isAsyncLoadActive(generation)) return;
        songList.value = List<MediaItem>.from(content['tracks']);
      } else {
        if (!isAsyncLoadActive(generation)) return;
        // If the album is offline, fetch the songs from the local database
        // Album details are already fetched in _checkIfAddedToLibrary method
        final box = await Hive.openBox(albumId);
        final songs = box.values
            .map<MediaItem?>((item) => MediaItemBuilder.fromJson(item))
            .whereType<MediaItem>()
            .toList();
        await box.close();
        if (!isAsyncLoadActive(generation)) return;
        songList.value = songs;
      }
      checkDownloadStatus();
      if (!isAsyncLoadActive(generation)) return;
      isContentFetched.value = true;
    } catch (e) {
      // Handle any errors that occur during the fetch
      printERROR("Error fetching album details: $e");
    }
  }

  @override
  Future<bool> checkIfAddedToLibrary(String id) async {
    final box = await Hive.openBox("LibraryAlbums");
    if (isClosed) {
      await box.close();
      return false;
    }
    isAddedToLibrary.value = box.containsKey(id);
    if (isAddedToLibrary.value) album.value = Album.fromJson(box.get(id));
    await box.close();
    return isAddedToLibrary.value;
  }

  @override
  Future<bool> addNRemoveFromLibrary(content, {bool add = true}) async {
    try {
      final box = await Hive.openBox("LibraryAlbums");
      final id = content.browseId;
      if (add) {
        await box.put(id, content.toJson());
        await updateSongsIntoDb();
      } else {
        await box.delete(id);
        final songsBox = await Hive.openBox(id);
        await songsBox.deleteFromDisk();
      }
      isAddedToLibrary.value = add;

      //Update frontend
      await Get.find<LibraryAlbumsController>().refreshLib();

      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> updateSongsIntoDb() async {
    final songsBox = await Hive.openBox(album.value.browseId);
    await songsBox.clear();
    final songListCopy = songList.toList();
    for (int i = 0; i < songListCopy.length; i++) {
      await songsBox.put(i, MediaItemBuilder.toJson(songListCopy[i]));
    }
    await songsBox.close();
  }

  @override
  void onClose() {
    cancelAsyncLoads();
    tempListContainer.clear();
    _animationController.dispose();
    Get.find<HomeScreenController>().whenHomeScreenOnTop();
    super.onClose();
  }

  @override
  Future<void> deleteMultipleSongs(List<MediaItem> songs) async {}

  @override
  void fetchPlaylistDetails(Playlist? playlist_, String playlistId) {}

  @override
  void syncPlaylistSongs() {}
}
