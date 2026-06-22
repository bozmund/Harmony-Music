import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/widgets/snackbar.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_selector/file_selector.dart';
import 'dart:convert';

import '/utils/search_filter.dart';
import '/services/constant.dart';
import '../../../utils/house_keeping.dart';
import '../../widgets/add_to_playlist.dart';
import '/ui/widgets/sort_widget.dart';
import '../Settings/settings_screen_controller.dart';
import '/services/music_service.dart';
import '/services/piped_service.dart';
import '/services/utils.dart';
import '../../../utils/helper.dart';
import '/models/album.dart';
import '/models/artist.dart';
import '/models/media_Item_builder.dart';
import '/models/playlist.dart';

class LibrarySongsController extends GetxController {
  late RxList<MediaItem> librarySongsList = RxList();
  final isSongFetched = false.obs;
  List<MediaItem> tempListContainer = [];
  SortWidgetController? sortWidgetController;
  final additionalOperationMode = OperationMode.none.obs;

  @override
  void onInit() {
    init();
    super.onInit();
  }

  Future<void> init() async {
    // Make sure that song cached in system or not cleared by system
    // if cleared then it will remove from database as well
    List<String> songsList = [];
    final cacheDir = (await getTemporaryDirectory()).path;
    if (Directory("$cacheDir/cachedSongs/").existsSync()) {
      final downloadedFiles = Directory("$cacheDir/cachedSongs")
          .listSync()
          .where(
            (f) => ![
              'mime',
              'part',
            ].contains(f.path.replaceAll(RegExp(r'^.*\.'), '')),
          );
      songsList.addAll(
        downloadedFiles
            .map((e) {
              RegExpMatch? match = RegExp(
                ".cachedSongs/([^#]*)?.mp3",
              ).firstMatch(e.path);
              if (match != null) {
                return match[1]!;
              }
            })
            .whereType<String>()
            .toList(),
      );
      //printINFO("all files: $downloadedFiles \n $songsList");
    }

    final box = Hive.box(BoxNames.songsCache);
    for (var element in box.keys) {
      if (!songsList.contains(element)) {
        box.delete(element);
      }
    }

    librarySongsList.value = box.values
        .map<MediaItem?>((item) => MediaItemBuilder.fromJson(item))
        .whereType<MediaItem>()
        .toList();

    librarySongsList.addAll(
      Hive.box(BoxNames.songDownloads).values
          .map<MediaItem?>((item) => MediaItemBuilder.fromJson(item))
          .whereType<MediaItem>()
          .toList(),
    );
    isSongFetched.value = true;

    //Remove deleted songs and expired songUrl from database
    startHouseKeeping();
  }

  void onSort(SortType sortType, bool isAscending) {
    final songlist = librarySongsList.toList();
    sortSongsNVideos(songlist, sortType, isAscending);
    librarySongsList.value = songlist;
  }

  void onSearchStart(String? tag) {
    tempListContainer = librarySongsList.toList();
  }

  void onSearch(String value, String? tag) {
    librarySongsList.value = tempListContainer.where((song) {
      return SearchFilter.matches({
        'title': song.title,
        'artist': song.artist,
      }, value);
    }).toList();
  }

  void onSearchClose(String? tag) {
    librarySongsList.value = tempListContainer.toList();
    // Clear search bar text when closing
    final sortWidgetController =
        Get.isRegistered<SortWidgetController>(tag: tag)
        ? Get.find<SortWidgetController>(tag: tag)
        : null;
    sortWidgetController?.textEditingController.clear();
    // onSearch is called with empty string via widget logic indirectly,
    // but here we ensure internal state is clean
    tempListContainer.clear();
  }

  /// remove song from library list and from storage only, not from database
  Future<void> removeSong(
    MediaItem item,
    bool isDownloaded, {
    String? url,
  }) async {
    if (tempListContainer.isNotEmpty) {
      tempListContainer.remove(item);
    }
    librarySongsList.remove(item);
    String filePath = "";
    if (isDownloaded) {
      filePath = item.extras!['url'] ?? url;
    } else {
      final cacheDir = (await getTemporaryDirectory()).path;
      filePath = "$cacheDir/cachedSongs/${item.id}.mp3";
    }

    if (await (File(filePath)).exists()) {
      await (File(filePath)).delete();
    }

    final thumbFile = File(
      "${Get.find<SettingsScreenController>().supportDirPath}/thumbnails/${item.id}.png",
    );
    if (await thumbFile.exists()) {
      await thumbFile.delete();
    }
  }

  //Additional operations
  final additionalOperationTempList = [].obs;
  final additionalOperationTempMap = <int, bool>{}.obs;

  void startAdditionalOperation(
    SortWidgetController sortWidgetController_,
    OperationMode mode,
  ) {
    sortWidgetController = sortWidgetController_;
    additionalOperationTempList.value = librarySongsList.toList();
    if (mode == OperationMode.addToPlaylist || mode == OperationMode.delete) {
      for (int i = 0; i < additionalOperationTempList.length; i++) {
        additionalOperationTempMap[i] = false;
      }
    }
    additionalOperationMode.value = mode;
  }

  void checkIfAllSelected() {
    sortWidgetController!.isAllSelected.value = !additionalOperationTempMap
        .containsValue(false);
  }

  void selectAll(bool selected) {
    for (int i = 0; i < additionalOperationTempList.length; i++) {
      additionalOperationTempMap[i] = selected;
    }
  }

  void performAdditionalOperation() {
    final currMode = additionalOperationMode.value;
    if (currMode == OperationMode.delete) {
      deleteMultipleSongs(selectedSongs()).then((value) {
        sortWidgetController?.setActiveMode(OperationMode.none);
        cancelAdditionalOperation();
      });
    } else if (currMode == OperationMode.addToPlaylist) {
      showDialog(
        context: Get.context!,
        builder: (context) => AddToPlaylist(selectedSongs()),
      ).whenComplete(() {
        Get.delete<AddToPlaylistController>();
        sortWidgetController?.setActiveMode(OperationMode.none);
        cancelAdditionalOperation();
      });
    }
  }

  Future<void> deleteMultipleSongs(List<MediaItem> songs) async {
    final downloadsBox = await Hive.openBox(BoxNames.songDownloads);
    final cacheBox = await Hive.openBox(BoxNames.songsCache);
    for (MediaItem element in songs) {
      if (downloadsBox.containsKey(element.id)) {
        await downloadsBox.delete(element.id);
        removeSong(element, true);
      } else {
        await cacheBox.delete(element.id);
        removeSong(element, false);
      }
    }
  }

  List<MediaItem> selectedSongs() {
    return additionalOperationTempMap.entries
        .map((item) {
          if (item.value) {
            return additionalOperationTempList[item.key];
          }
        })
        .whereType<MediaItem>()
        .toList();
  }

  void cancelAdditionalOperation() {
    sortWidgetController!.isAllSelected.value = false;
    sortWidgetController = null;
    additionalOperationMode.value = OperationMode.none;
    additionalOperationTempList.clear();
    additionalOperationTempMap.clear();
  }
}

class YouTubePlaylistImportResult {
  const YouTubePlaylistImportResult({
    required this.playlist,
    required this.importedSongCount,
    required this.conflictAddedCount,
  });

  final Playlist playlist;
  final int importedSongCount;
  final int conflictAddedCount;
}

class YouTubePlaylistImportException implements Exception {
  const YouTubePlaylistImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SpotifyImportTrack {
  const SpotifyImportTrack({
    required this.trackName,
    required this.artistName,
    this.albumName,
    this.trackUri,
  });

  final String trackName;
  final String artistName;
  final String? albumName;
  final String? trackUri;

  String get query => "$trackName $artistName";
}

class SpotifyImportPlaylist {
  const SpotifyImportPlaylist({
    required this.name,
    required this.tracks,
    this.description,
  });

  final String name;
  final String? description;
  final List<SpotifyImportTrack> tracks;
}

class SpotifyPlaylistImportResult {
  const SpotifyPlaylistImportResult({
    required this.playlistsImported,
    required this.importedSongCount,
    required this.conflictAddedCount,
    required this.reviewAddedCount,
    required this.skippedTrackCount,
  });

  final int playlistsImported;
  final int importedSongCount;
  final int conflictAddedCount;
  final int reviewAddedCount;
  final int skippedTrackCount;
}

class SpotifyPlaylistImportException implements Exception {
  const SpotifyPlaylistImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _SpotifyTrackMatch {
  const _SpotifyTrackMatch({required this.song, required this.isConfident});

  final MediaItem song;
  final bool isConfident;
}

class LibraryPlaylistsController extends GetxController
    with GetTickerProviderStateMixin {
  late AnimationController controller;

  final playlistCreationMode = "local".obs;
  static final initPlst = [
    Playlist(
      title: "recentlyPlayed".tr,
      playlistId: BoxNames.libRP,
      thumbnailUrl: Playlist.thumbPlaceholderUrl,
      isCloudPlaylist: false,
    ),
    Playlist(
      title: "favorites".tr,
      playlistId: BoxNames.libFav,
      thumbnailUrl: Playlist.thumbPlaceholderUrl,
      isCloudPlaylist: false,
    ),
    Playlist(
      title: "Liked not downloaded",
      playlistId: BoxNames.libFavNotDownloaded,
      thumbnailUrl: Playlist.thumbPlaceholderUrl,
      isCloudPlaylist: false,
    ),
    Playlist(
      title: "Import conflicts",
      playlistId: BoxNames.libImportDuplicates,
      thumbnailUrl: Playlist.thumbPlaceholderUrl,
      isCloudPlaylist: false,
    ),
    Playlist(
      title: "Import needs review",
      playlistId: BoxNames.libImportReview,
      thumbnailUrl: Playlist.thumbPlaceholderUrl,
      isCloudPlaylist: false,
    ),
    Playlist(
      title: "cachedOrOffline".tr,
      playlistId: BoxNames.songsCache,
      thumbnailUrl: Playlist.thumbPlaceholderUrl,
      isCloudPlaylist: false,
    ),
    Playlist(
      title: "downloads".tr,
      playlistId: BoxNames.songDownloads,
      thumbnailUrl: Playlist.thumbPlaceholderUrl,
      isCloudPlaylist: false,
    ),
  ];
  late RxList<Playlist> libraryPlaylists = RxList(initPlst);
  final isContentFetched = false.obs;
  final creationInProgress = false.obs;
  final textInputController = TextEditingController();
  List<Playlist> tempListContainer = [];

  // Add these RxBool to track import progress
  final isImporting = false.obs;
  final importProgress = 0.0.obs;

  @override
  void onInit() {
    controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    refreshLib();
    super.onInit();
  }

  void refreshLib() async {
    final box = await Hive.openBox(BoxNames.libraryPlaylists);
    libraryPlaylists.value = [
      ...initPlst,
      ...(box.values
          .map<Playlist?>((item) => Playlist.fromJson(item))
          .whereType<Playlist>()
          .toList()),
    ];

    final appPrefsBox = Hive.box(BoxNames.appPrefs);
    if (appPrefsBox.containsKey(PrefKeys.piped)) {
      if (appPrefsBox.get(PrefKeys.piped)['isLoggedIn']) {
        await syncPipedPlaylist();
      }
    }

    isContentFetched.value = true;
    await box.close();
  }

  void updatePlaylistIntoDb(Playlist playlist) async {
    final box = await Hive.openBox(BoxNames.libraryPlaylists);
    box.put(playlist.playlistId, playlist.toJson());
    refreshLib();
  }

  void removePipedPlaylists() {
    for (Playlist plst in libraryPlaylists.toList()) {
      if (plst.isPipedPlaylist) {
        libraryPlaylists.remove(plst);
      }
    }
  }

  Future<void> syncPipedPlaylist() async {
    final res = await Get.find<PipedServices>().getAllPlaylists();
    final box = await Hive.openBox('blacklistedPlaylist');
    final blacklistedPlaylist = box.values.whereType<String>().toList();
    final libPipedPlaylistsId =
        libraryPlaylists
            .toList()
            .map((e) {
              if (e.isPipedPlaylist) {
                return e.playlistId;
              }
            })
            .whereType<String>()
            .toList() +
        blacklistedPlaylist;

    if (res.code == 1) {
      final cloudpipedPlaylistsId = res.response
          .map((e) {
            return e['id'];
          })
          .whereType<String>()
          .toList();
      //add new playlist from cloud
      for (dynamic playlist in res.response) {
        if (!libPipedPlaylistsId.contains(playlist['id'])) {
          final plst = Playlist(
            title: playlist['name'],
            playlistId: playlist['id'],
            description: "Piped Playlist",
            thumbnailUrl: playlist['thumbnail'],
            isPipedPlaylist: true,
          );
          libraryPlaylists.add(plst);
        }
      }

      //remove playist if removed from cloud
      for (Playlist playlist in libraryPlaylists.toList()) {
        if (!cloudpipedPlaylistsId.contains(playlist.playlistId) &&
            playlist.isPipedPlaylist) {
          libraryPlaylists.removeWhere(
            (element) => element.playlistId == playlist.playlistId,
          );
        }
      }
    }
    box.close();
  }

  Future<bool> renamePlaylist(Playlist playlist) async {
    String title = textInputController.text;
    if (title.trim().isNotEmpty) {
      if (playlist.isPipedPlaylist) {
        final res = await Get.find<PipedServices>().renamePlaylist(
          playlist.playlistId,
          title,
        );
        if (res.code == 0) return false;
        playlist.newTitle = title;
      } else {
        final box = await Hive.openBox(BoxNames.libraryPlaylists);
        title = "${title[0].toUpperCase()}${title.substring(1).toLowerCase()}";
        playlist.newTitle = title;
        box.put(playlist.playlistId, playlist.toJson());
      }
      refreshLib();
      return true;
    }
    return false;
  }

  void changeCreationMode(String? val) {
    playlistCreationMode.value = val!;
  }

  Future<bool> createNewPlaylist({
    bool createPlaylistNaddSong = false,
    List<MediaItem>? songItems,
  }) async {
    String title = textInputController.text;
    if (title.trim().isNotEmpty) {
      dynamic newplst;

      if (playlistCreationMode.value == "piped") {
        creationInProgress.value = true;
        final res = await Get.find<PipedServices>().createPlaylist(title);
        if (res.code == 1) {
          newplst = Playlist(
            title: title,
            playlistId: "${res.response['playlistId']}",
            thumbnailUrl: songItems != null
                ? songItems[0].artUri.toString()
                : Playlist.thumbPlaceholderUrl,
            description: "Piped Playlist",
            isCloudPlaylist: true,
            isPipedPlaylist: true,
          );
        } else {
          creationInProgress.value = false;
          return false;
        }
      } else {
        newplst = Playlist(
          title: title,
          playlistId: "LIB${DateTime.now().millisecondsSinceEpoch}",
          thumbnailUrl: songItems != null
              ? songItems[0].artUri.toString()
              : Playlist.thumbPlaceholderUrl,
          description: "Library Playlist",
          isCloudPlaylist: false,
        );
        final box = await Hive.openBox(BoxNames.libraryPlaylists);
        box.put(newplst.playlistId, newplst.toJson());
        await box.close();
      }

      libraryPlaylists.add(newplst);

      if (createPlaylistNaddSong && playlistCreationMode.value == "local") {
        final plastbox = await Hive.openBox(newplst.playlistId);
        for (MediaItem item in songItems!) {
          plastbox.add(MediaItemBuilder.toJson(item));
        }
        plastbox.close();
      } else if ((createPlaylistNaddSong &&
          playlistCreationMode.value == "piped")) {
        final songIds = songItems!.map((e) => e.id).toList();
        await Get.find<PipedServices>().addToPlaylist(
          newplst.playlistId,
          songIds,
        );
      }
      creationInProgress.value = false;
      return true;
    }
    return false;
  }

  Future<void> blacklistPipedPlaylist(Playlist playlist) async {
    final box = await Hive.openBox('blacklistedPlaylist');
    box.add(playlist.playlistId);
    libraryPlaylists.remove(playlist);
    box.close();
  }

  Future<void> resetBlacklistedPlaylist() async {
    final box = await Hive.openBox('blacklistedPlaylist');
    box.clear();
    syncPipedPlaylist();
  }

  void onSort(SortType sortType, bool isAscending) {
    final playlists = libraryPlaylists.toList();
    playlists.removeRange(0, initPlst.length);
    sortPlayLists(playlists, sortType, isAscending);
    playlists.insertAll(0, initPlst);
    libraryPlaylists.value = playlists;
  }

  Future<YouTubePlaylistImportResult> importPlaylistFromYouTubeMusic(
    String input, {
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call("Parsing playlist URL");
    final playlistId = _extractYouTubePlaylistId(input);
    if (playlistId == null) {
      throw const YouTubePlaylistImportException("Invalid URL or playlist ID");
    }

    onStatus?.call("Fetching playlist");
    late Map<String, dynamic> content;
    try {
      content = await Get.find<MusicServices>().getPlaylistOrAlbumSongs(
        playlistId: playlistId,
      );
    } catch (e) {
      printERROR("YouTube Music playlist import fetch failed: $e");
      throw const YouTubePlaylistImportException(
        "Playlist not found, private, or unavailable",
      );
    }

    final tracks =
        (content['tracks'] as List?)?.whereType<MediaItem>().toList(
          growable: false,
        ) ??
        const <MediaItem>[];
    if (tracks.isEmpty) {
      throw const YouTubePlaylistImportException("No songs found");
    }

    final rawTitle = (content['title'] as String?)?.trim();
    final newPlaylist = await _saveLocalImportedPlaylist(
      title: rawTitle == null || rawTitle.isEmpty
          ? "Imported YouTube Music playlist"
          : rawTitle,
      description: content['description'] ?? "Imported YouTube Music playlist",
      thumbnailUrl: _thumbnailUrlFromContent(content, tracks),
      tracks: tracks,
    );

    onStatus?.call("Checking conflicts");
    final conflictAddedCount = await _addImportedConflicts(tracks);

    refreshLib();
    onStatus?.call("Completed");
    return YouTubePlaylistImportResult(
      playlist: newPlaylist,
      importedSongCount: tracks.length,
      conflictAddedCount: conflictAddedCount,
    );
  }

  Future<SpotifyPlaylistImportResult> importSpotifyPlaylists(
    List<SpotifyImportPlaylist> playlists, {
    void Function(String status)? onStatus,
  }) async {
    if (playlists.isEmpty) {
      throw const SpotifyPlaylistImportException("No selected playlists");
    }

    var playlistsImported = 0;
    var importedSongCount = 0;
    var conflictAddedCount = 0;
    var reviewAddedCount = 0;
    var skippedTrackCount = 0;

    for (final spotifyPlaylist in playlists) {
      onStatus?.call("Matching ${spotifyPlaylist.name}");
      final matchedSongs = <MediaItem>[];
      final reviewSongs = <MediaItem>[];

      for (final track in spotifyPlaylist.tracks) {
        onStatus?.call("Matching ${track.trackName}");
        final match = await _matchSpotifyTrack(track);
        if (match == null) {
          skippedTrackCount++;
        } else if (match.isConfident) {
          matchedSongs.add(match.song);
        } else {
          reviewSongs.add(match.song);
        }
      }

      reviewAddedCount += await _addImportReviewCandidates(reviewSongs);

      if (matchedSongs.isEmpty) {
        continue;
      }

      onStatus?.call("Saving ${spotifyPlaylist.name}");
      await _saveLocalImportedPlaylist(
        title: spotifyPlaylist.name,
        description:
            spotifyPlaylist.description ?? "Imported Spotify playlist export",
        thumbnailUrl: _thumbnailUrlFromContent({}, matchedSongs),
        tracks: matchedSongs,
      );
      conflictAddedCount += await _addImportedConflicts(matchedSongs);
      importedSongCount += matchedSongs.length;
      playlistsImported++;
    }

    refreshLib();
    onStatus?.call("Completed");

    if (playlistsImported == 0 && reviewAddedCount == 0) {
      throw const SpotifyPlaylistImportException("No songs found");
    }

    return SpotifyPlaylistImportResult(
      playlistsImported: playlistsImported,
      importedSongCount: importedSongCount,
      conflictAddedCount: conflictAddedCount,
      reviewAddedCount: reviewAddedCount,
      skippedTrackCount: skippedTrackCount,
    );
  }

  Future<_SpotifyTrackMatch?> _matchSpotifyTrack(
    SpotifyImportTrack track,
  ) async {
    final results = await Get.find<MusicServices>().search(
      track.query,
      filter: 'songs',
      limit: 5,
    );
    final candidates = _songsFromSearchResults(results);
    if (candidates.isEmpty) return null;

    for (final candidate in candidates) {
      if (_isConfidentSpotifyMatch(track, candidate)) {
        return _SpotifyTrackMatch(song: candidate, isConfident: true);
      }
    }

    return _SpotifyTrackMatch(song: candidates.first, isConfident: false);
  }

  List<MediaItem> _songsFromSearchResults(Map<String, dynamic> results) {
    final songs = <MediaItem>[];
    for (final entry in results.entries) {
      final value = entry.value;
      if (value is! List) continue;
      for (final item in value) {
        if (item is MediaItem) songs.add(item);
      }
    }
    return songs;
  }

  bool _isConfidentSpotifyMatch(SpotifyImportTrack track, MediaItem song) {
    final spotifyTitle = _normalizeImportText(track.trackName);
    final candidateTitle = _normalizeImportText(song.title);
    final candidateArtist = _normalizeImportText(song.artist ?? "");

    final titleMatches =
        candidateTitle == spotifyTitle ||
        candidateTitle.contains(spotifyTitle) ||
        spotifyTitle.contains(candidateTitle);
    if (!titleMatches) return false;

    final spotifyArtists = track.artistName
        .split(
          RegExp(r'\s+(?:and|x|with|feat|ft)\s+|,\s*|&', caseSensitive: false),
        )
        .map(_normalizeImportText)
        .map((artist) => artist.trim())
        .where((artist) => artist.isNotEmpty)
        .toList();
    if (spotifyArtists.isEmpty) return false;

    return spotifyArtists.any((artist) => candidateArtist.contains(artist));
  }

  String _normalizeImportText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ')
        .replaceAll(
          RegExp(r'\b(feat|ft|with|official|audio|video|lyrics?)\b'),
          ' ',
        )
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<Playlist> _saveLocalImportedPlaylist({
    required String title,
    required String description,
    required String thumbnailUrl,
    required List<MediaItem> tracks,
  }) async {
    final libraryBoxWasOpen = Hive.isBoxOpen(BoxNames.libraryPlaylists);
    final libraryBox = libraryBoxWasOpen
        ? Hive.box(BoxNames.libraryPlaylists)
        : await Hive.openBox(BoxNames.libraryPlaylists);

    final existingTitles = [
      ...initPlst.map((playlist) => playlist.title),
      ...libraryBox.values
          .map<Playlist?>((item) => Playlist.fromJson(item))
          .whereType<Playlist>()
          .map((playlist) => playlist.title),
    ];

    var newPlaylistId = "LIB${DateTime.now().microsecondsSinceEpoch}";
    while (libraryBox.containsKey(newPlaylistId)) {
      newPlaylistId = "LIB${DateTime.now().microsecondsSinceEpoch}";
    }
    final newPlaylist = Playlist(
      title: _uniqueImportedPlaylistTitle(title, existingTitles),
      playlistId: newPlaylistId,
      thumbnailUrl: thumbnailUrl,
      description: description,
      songCount: tracks.length.toString(),
      isCloudPlaylist: false,
    );

    await libraryBox.put(newPlaylistId, newPlaylist.toJson());
    final songsBox = await Hive.openBox(newPlaylistId);
    await songsBox.clear();
    for (int i = 0; i < tracks.length; i++) {
      await songsBox.put(i, MediaItemBuilder.toJson(tracks[i]));
    }
    await songsBox.close();

    if (!libraryBoxWasOpen) await libraryBox.close();
    return newPlaylist;
  }

  Future<int> _addImportedConflicts(List<MediaItem> tracks) async {
    final favBoxWasOpen = Hive.isBoxOpen(BoxNames.libFav);
    final downloadsBoxWasOpen = Hive.isBoxOpen(BoxNames.songDownloads);
    final conflictsBoxWasOpen = Hive.isBoxOpen(BoxNames.libImportDuplicates);
    final favBox = favBoxWasOpen
        ? Hive.box(BoxNames.libFav)
        : await Hive.openBox(BoxNames.libFav);
    final downloadsBox = downloadsBoxWasOpen
        ? Hive.box(BoxNames.songDownloads)
        : await Hive.openBox(BoxNames.songDownloads);
    final conflictsBox = conflictsBoxWasOpen
        ? Hive.box(BoxNames.libImportDuplicates)
        : await Hive.openBox(BoxNames.libImportDuplicates);

    var conflictAddedCount = 0;
    for (final song in tracks) {
      final alreadyKnown =
          favBox.containsKey(song.id) || downloadsBox.containsKey(song.id);
      if (alreadyKnown && !conflictsBox.containsKey(song.id)) {
        await conflictsBox.put(song.id, MediaItemBuilder.toJson(song));
        conflictAddedCount++;
      }
    }

    if (!conflictsBoxWasOpen) await conflictsBox.close();
    if (!downloadsBoxWasOpen) await downloadsBox.close();
    if (!favBoxWasOpen) await favBox.close();
    return conflictAddedCount;
  }

  Future<int> _addImportReviewCandidates(List<MediaItem> tracks) async {
    final reviewBoxWasOpen = Hive.isBoxOpen(BoxNames.libImportReview);
    final reviewBox = reviewBoxWasOpen
        ? Hive.box(BoxNames.libImportReview)
        : await Hive.openBox(BoxNames.libImportReview);

    var reviewAddedCount = 0;
    for (final song in tracks) {
      if (!reviewBox.containsKey(song.id)) {
        await reviewBox.put(song.id, MediaItemBuilder.toJson(song));
        reviewAddedCount++;
      }
    }

    if (!reviewBoxWasOpen) await reviewBox.close();
    return reviewAddedCount;
  }

  String? _extractYouTubePlaylistId(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;

    final uri = Uri.tryParse(value);
    final listParam = uri?.queryParameters['list'];
    if (listParam != null && listParam.trim().isNotEmpty) {
      return validatePlaylistId(listParam.trim());
    }

    final match = RegExp(r'(?:^|[?&])list=([^&#\s]+)').firstMatch(value);
    if (match != null) return validatePlaylistId(match.group(1)!.trim());

    if (value.contains('/') || value.contains('?') || value.contains('&')) {
      return null;
    }

    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) return null;
    return validatePlaylistId(value);
  }

  String _uniqueImportedPlaylistTitle(String baseTitle, List<String> titles) {
    final existing = titles.map((title) => title.toLowerCase()).toSet();
    if (!existing.contains(baseTitle.toLowerCase())) return baseTitle;

    var suffix = 2;
    var candidate = "$baseTitle (Imported)";
    while (existing.contains(candidate.toLowerCase())) {
      candidate = "$baseTitle (Imported $suffix)";
      suffix++;
    }
    return candidate;
  }

  String _thumbnailUrlFromContent(
    Map<String, dynamic> content,
    List<MediaItem> tracks,
  ) {
    final thumbnails = content['thumbnails'];
    if (thumbnails is List && thumbnails.isNotEmpty) {
      final first = thumbnails.first;
      if (first is Map && first['url'] is String) {
        final url = (first['url'] as String).trim();
        if (url.isNotEmpty) return url;
      }
    }
    if (tracks.isNotEmpty) {
      final artUri = tracks.first.artUri?.toString();
      if (artUri != null && artUri.isNotEmpty) return artUri;
    }
    return Playlist.thumbPlaceholderUrl;
  }

  void onSearchStart(String? tag) {
    tempListContainer = libraryPlaylists.toList();
  }

  void onSearch(String value, String? tag) {
    libraryPlaylists.value = tempListContainer
        .where(
          (element) => SearchFilter.matches({'title': element.title}, value),
        )
        .toList();
  }

  void onSearchClose(String? tag) {
    libraryPlaylists.value = tempListContainer.toList();
    // Clear search bar text when closing
    final sortWidgetController =
        Get.isRegistered<SortWidgetController>(tag: tag)
        ? Get.find<SortWidgetController>(tag: tag)
        : null;
    sortWidgetController?.textEditingController.clear();
    tempListContainer.clear();
  }

  @override
  void dispose() {
    textInputController.dispose();
    controller.dispose();
    super.dispose();
  }

  Future<void> importPlaylistFromJson(BuildContext context) async {
    try {
      isImporting.value = true;
      importProgress.value = 0.1;

      // Show progress dialog
      if (context.mounted) {
        _showImportProgressDialog(context);
      }

      final result = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
        confirmButtonText: 'importPlaylist'.tr,
      );

      if (result == null) {
        // User cancelled the picker
        if (Get.isDialogOpen ?? false) {
          Get.back();
        }
        isImporting.value = false;
        importProgress.value = 0.0;
        return;
      }

      importProgress.value = 0.2;

      final file = File(result.path);
      if (!await file.exists()) {
        throw FileSystemException("fileNotFound".tr);
      }

      final jsonString = await file.readAsString();
      importProgress.value = 0.3;

      final jsonData = jsonDecode(jsonString);
      importProgress.value = 0.4;

      // Validate JSON structure
      if (!jsonData.containsKey('playlistInfo') ||
          !jsonData.containsKey('songs')) {
        throw FormatException("invalidPlaylistFile".tr);
      }

      // Create new playlist ID
      final playlistInfo = jsonData['playlistInfo'];
      final newPlaylistId = "LIB${DateTime.now().millisecondsSinceEpoch}";
      importProgress.value = 0.5;

      // Create playlist object
      final newPlaylist = Playlist(
        title: "${playlistInfo['title']} (${"imported".tr})",
        playlistId: newPlaylistId,
        thumbnailUrl:
            playlistInfo['thumbnailUrl'] ??
            (playlistInfo['thumbnails'] != null &&
                    playlistInfo['thumbnails'].isNotEmpty
                ? playlistInfo['thumbnails'][0]['url']
                : Playlist.thumbPlaceholderUrl),
        description: playlistInfo['description'] ?? "importedPlaylist".tr,
        isCloudPlaylist: false,
      );
      importProgress.value = 0.6;

      // Save playlist to database
      final box = await Hive.openBox(BoxNames.libraryPlaylists);
      box.put(newPlaylistId, newPlaylist.toJson());
      importProgress.value = 0.7;

      // Save songs to playlist
      final songsBox = await Hive.openBox(newPlaylistId);
      final songsList = jsonData['songs'] as List;

      // Update progress as songs are added
      final totalSongs = songsList.length;
      for (int i = 0; i < totalSongs; i++) {
        await songsBox.put(i, songsList[i]);
        // Update progress from 70% to 95% based on song import progress
        importProgress.value = 0.7 + (0.25 * (i + 1) / totalSongs);
      }

      await songsBox.close();
      await box.close();
      importProgress.value = 1.0;

      // Close progress dialog if it's still open
      if (Get.isDialogOpen ?? false) {
        Get.back();
      }

      // Refresh library to show the new playlist
      refreshLib();

      // Show success message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          snackbar(
            context,
            "${"playlistImportedMsg".tr}: ${newPlaylist.title}",
            size: SanckBarSize.MEDIUM,
          ),
        );
      }
    } catch (e) {
      // Close progress dialog if it's still open
      if (Get.isDialogOpen ?? false) {
        Get.back();
      }

      printERROR("Error importing playlist: $e");

      String errorMsg = "importError".tr;
      if (e is FileSystemException) {
        errorMsg = "importErrorFileAccess".tr;
      } else if (e is FormatException) {
        errorMsg = "importErrorFormat".tr;
      } else if (e.toString().contains("invalidPlaylistFile")) {
        errorMsg = "invalidPlaylistFile".tr;
      } else if (e is HiveError) {
        errorMsg = "importErrorDatabase".tr;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(snackbar(context, errorMsg, size: SanckBarSize.MEDIUM));
      }
    } finally {
      isImporting.value = false;
      importProgress.value = 0.0;
    }
  }

  // Helper method to show import progress dialog
  void _showImportProgressDialog(BuildContext context) {
    Get.dialog(
      AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          "importingPlaylist".tr,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: Obx(
          () => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: Get.isRegistered<LibraryPlaylistsController>()
                    ? importProgress.value
                    : 0,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "${(Get.isRegistered<LibraryPlaylistsController>() ? importProgress.value * 100 : 0).toInt()}%",
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
    );
  }
}

class LibraryAlbumsController extends GetxController {
  late RxList<Album> libraryAlbums = RxList();
  final isContentFetched = false.obs;
  List<Album> tempListContainer = [];

  @override
  void onInit() {
    refreshLib();
    super.onInit();
  }

  void refreshLib() async {
    final box = await Hive.openBox(BoxNames.libraryAlbums);
    libraryAlbums.value = box.values
        .map<Album?>((item) => Album.fromJson(item))
        .whereType<Album>()
        .toList();

    isContentFetched.value = true;
    box.close();
  }

  void onSort(SortType sortType, bool isAscending) {
    final albumList = libraryAlbums.toList();
    sortAlbumNSingles(albumList, sortType, isAscending);
    libraryAlbums.value = albumList;
  }

  void onSearchStart(String? tag) {
    tempListContainer = libraryAlbums.toList();
  }

  void onSearch(String value, String? tag) {
    libraryAlbums.value = tempListContainer
        .where(
          (element) => SearchFilter.matches({'title': element.title}, value),
        )
        .toList();
  }

  void onSearchClose(String? tag) {
    libraryAlbums.value = tempListContainer.toList();
    // Clear search bar text when closing
    final sortWidgetController =
        Get.isRegistered<SortWidgetController>(tag: tag)
        ? Get.find<SortWidgetController>(tag: tag)
        : null;
    sortWidgetController?.textEditingController.clear();
    tempListContainer.clear();
  }
}

class LibraryArtistsController extends GetxController {
  RxList<Artist> libraryArtists = RxList();
  final isContentFetched = false.obs;
  List<Artist> tempListContainer = [];

  @override
  void onInit() {
    refreshLib();
    super.onInit();
  }

  void refreshLib() async {
    final box = await Hive.openBox(BoxNames.libraryArtists);
    libraryArtists.value = box.values
        .map<Artist?>((item) => Artist.fromJson(item))
        .whereType<Artist>()
        .toList();
    isContentFetched.value = true;
    box.close();
  }

  void onSort(SortType sortType, bool isAscending) {
    final artistList = libraryArtists.toList();
    sortArtist(artistList, sortType, isAscending);
    libraryArtists.value = artistList;
  }

  void onSearchStart(String? tag) {
    tempListContainer = libraryArtists.toList();
  }

  void onSearch(String value, String? tag) {
    libraryArtists.value = tempListContainer
        .where(
          (element) => SearchFilter.matches({'title': element.name}, value),
        )
        .toList();
  }

  void onSearchClose(String? tag) {
    libraryArtists.value = tempListContainer.toList();
    // Clear search bar text when closing
    final sortWidgetController =
        Get.isRegistered<SortWidgetController>(tag: tag)
        ? Get.find<SortWidgetController>(tag: tag)
        : null;
    sortWidgetController?.textEditingController.clear();
    tempListContainer.clear();
  }
}

class LibrarySearchesController extends GetxController {
  final RxList<String> savedSearches = RxList();
  final isContentFetched = false.obs;

  @override
  void onInit() {
    refreshLib();
    super.onInit();
  }

  void refreshLib() async {
    final box = await Hive.openBox(BoxNames.librarySearches);
    savedSearches.value = box.values.whereType<String>().toList();
    isContentFetched.value = true;
    box.close();
  }

  Future<void> saveSearch(String query) async {
    if (query.trim().isEmpty || savedSearches.contains(query)) return;
    final box = await Hive.openBox(BoxNames.librarySearches);
    await box.add(query);
    savedSearches.add(query);
    await box.close();
  }

  Future<void> deleteSearch(String query) async {
    final box = await Hive.openBox(BoxNames.librarySearches);
    final key = box.keys.firstWhere(
      (k) => box.get(k) == query,
      orElse: () => null,
    );
    if (key != null) {
      await box.delete(key);
      savedSearches.remove(query);
    }
    await box.close();
  }
}
