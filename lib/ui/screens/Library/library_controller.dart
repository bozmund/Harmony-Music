import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:harmonymusic/l10n/l10n.dart';
import 'package:harmonymusic/l10n/app_localizations_en.dart';
import 'package:harmonymusic/ui/widgets/snackbar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_selector/file_selector.dart';
import '../../../domain/repositories/library_repository.dart';
import '../../../app/navigation/app_navigator.dart';
import '../../../domain/repositories/playlist_repository.dart';
import '../../../domain/repositories/settings_repository.dart';
import '../../../domain/repositories/download_repository.dart';
import '../../../domain/repositories/song_cache_repository.dart';
import '/services/file_picker_service.dart';
import 'dart:convert';

import '/utils/search_filter.dart';
import '/services/constant.dart';
import '../../../utils/house_keeping.dart';
import '../../widgets/add_to_playlist.dart';
import '/ui/widgets/sort_widget.dart';
import '/services/app_contracts.dart';
import '/services/piped_service.dart';
import '/services/utils.dart';
import '../../../utils/helper.dart';
import '/models/album.dart';
import '/models/artist.dart';
import '/models/media_Item_builder.dart';
import '/models/playlist.dart';
import '/models/thumbnail.dart';
import '/utils/playlist_art.dart';
import '../../../utils/observable_state.dart';

class LibrarySongsController extends ChangeNotifier {
  LibrarySongsController({
    required DownloadRepository downloadRepository,
    required LibraryRepository libraryRepository,
    required SongCacheRepository songCacheRepository,
  }) : _downloadRepository = downloadRepository,
       _songCacheRepository = songCacheRepository,
       _libraryRepository = libraryRepository;

  final DownloadRepository _downloadRepository;
  final SongCacheRepository _songCacheRepository;
  final LibraryRepository _libraryRepository;
  LibraryRepository get _library => _libraryRepository;

  static const sortWidgetTag = "LibSongSort";
  static const defaultSortType = SortType.date;
  static const defaultSortAscending = false;

  List<MediaItem> librarySongsList = [];
  bool isSongFetched = false;
  List<MediaItem> tempListContainer = [];
  SortWidgetController? sortWidgetController;
  OperationMode additionalOperationMode = OperationMode.none;
  String _activeSearchQuery = '';
  String _supportDirPath = '';

  Future<void> init() async {
    _supportDirPath = (await getApplicationSupportDirectory()).path;
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

    final cachedSongs = await _library.getCachedSongs();
    for (var element in cachedSongs.map((song) => song.id)) {
      if (!songsList.contains(element)) {
        await _library.deleteCachedSong(element);
      }
    }

    final songs = await _library.getAllLibrarySongs();
    sortSongsNVideos(songs, defaultSortType, defaultSortAscending);
    librarySongsList = songs;
    isSongFetched = true;
    notifyListeners();

    //Remove deleted songs and expired songUrl from database
    await startHouseKeeping(
      songCacheRepository: _songCacheRepository,
      downloadRepository: _downloadRepository,
      libraryRepository: _library,
      librarySongsController: this,
    );
  }

  void addSongToLibraryList(MediaItem song) {
    final activeSortController =
        SortWidgetRegistry.maybeOf(sortWidgetTag) ?? sortWidgetController;
    final isSearching =
        activeSortController?.isSearchingEnabled == true ||
        tempListContainer.isNotEmpty;
    final songlist =
        (isSearching ? tempListContainer : librarySongsList)
            .where((item) => item.id != song.id)
            .toList()
          ..add(song);
    final activeSortType = activeSortController?.sortType ?? defaultSortType;
    final activeSortAscending =
        activeSortController?.isAscending ?? defaultSortAscending;
    sortSongsNVideos(songlist, activeSortType, activeSortAscending);
    if (isSearching) {
      tempListContainer = songlist;
      _applyLibrarySongSearch(_activeSearchQuery);
    } else {
      librarySongsList = songlist;
      notifyListeners();
    }
  }

  void onSort(SortType sortType, bool isAscending) {
    final songlist = List<MediaItem>.from(librarySongsList);
    sortSongsNVideos(songlist, sortType, isAscending);
    librarySongsList = songlist;
    notifyListeners();
  }

  void onSearchStart(String? tag) {
    tempListContainer = librarySongsList.toList();
    _activeSearchQuery = '';
  }

  void onSearch(String value, String? tag) {
    _activeSearchQuery = value;
    _applyLibrarySongSearch(value);
  }

  /// Fills in the on-screen duration for a song that was loaded without one,
  /// once playback resolves the real duration. The provider only runs
  /// [init] once, so without this the list would keep showing no duration
  /// until an app restart even after the value is persisted.
  void applyResolvedDuration(String songId, Duration duration) {
    if (duration <= Duration.zero) return;
    var changed = false;
    List<MediaItem> patch(List<MediaItem> source) {
      return source.map((song) {
        if (song.id != songId ||
            (song.duration != null && song.duration! > Duration.zero)) {
          return song;
        }
        changed = true;
        return song.copyWith(duration: duration);
      }).toList();
    }

    final patchedMain = patch(librarySongsList);
    if (tempListContainer.isNotEmpty) {
      tempListContainer = patch(tempListContainer);
    }
    if (!changed) return;
    librarySongsList = patchedMain;
    notifyListeners();
  }

  /// This controller outlives the sort widget holding the search bar, so a
  /// filter can survive navigation while the search UI comes back empty.
  /// Called when a fresh sort widget mounts to drop such a stale filter.
  void clearStaleSearch() {
    if (tempListContainer.isEmpty) return;
    librarySongsList = tempListContainer.toList();
    tempListContainer.clear();
    _activeSearchQuery = '';
    notifyListeners();
  }

  void _applyLibrarySongSearch(String value) {
    librarySongsList = tempListContainer.where((song) {
      return SearchFilter.matches({
        'title': song.title,
        'artist': song.artist,
      }, value);
    }).toList();
    notifyListeners();
  }

  void onSearchClose(String? tag) {
    librarySongsList = tempListContainer.toList();
    // Clear search bar text when closing
    final sortWidgetController = SortWidgetRegistry.maybeOf(tag);
    sortWidgetController?.textEditingController.clear();
    // onSearch is called with empty string via widget logic indirectly,
    // but here we ensure internal state is clean
    tempListContainer.clear();
    _activeSearchQuery = '';
    notifyListeners();
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
    librarySongsList = librarySongsList
        .where((song) => song.id != item.id)
        .toList();
    String filePath = "";
    if (isDownloaded) {
      // Restored downloads may carry no local path at all (file missing on
      // this install); there is nothing on disk to delete for them.
      filePath = item.extras!['url'] ?? url ?? "";
    } else {
      final cacheDir = (await getTemporaryDirectory()).path;
      filePath = "$cacheDir/cachedSongs/${item.id}.mp3";
    }

    if (filePath.isNotEmpty && await File(filePath).exists()) {
      await File(filePath).delete();
    }

    final thumbFile = File("$_supportDirPath/thumbnails/${item.id}.png");
    if (await thumbFile.exists()) {
      await thumbFile.delete();
    }
    notifyListeners();
  }

  //Additional operations
  List<MediaItem> additionalOperationTempList = <MediaItem>[];
  final additionalOperationTempMap = <int, bool>{};

  void startAdditionalOperation(
    SortWidgetController sortWidgetController_,
    OperationMode mode,
  ) {
    sortWidgetController = sortWidgetController_;
    additionalOperationTempList = List<MediaItem>.from(librarySongsList);
    if (mode == OperationMode.addToPlaylist || mode == OperationMode.delete) {
      for (int i = 0; i < additionalOperationTempList.length; i++) {
        additionalOperationTempMap[i] = false;
      }
    }
    additionalOperationMode = mode;
    notifyListeners();
  }

  void checkIfAllSelected() {
    sortWidgetController!.toggleSelectAll(
      !additionalOperationTempMap.containsValue(false),
    );
    notifyListeners();
  }

  void selectAll(bool selected) {
    for (int i = 0; i < additionalOperationTempList.length; i++) {
      additionalOperationTempMap[i] = selected;
    }
    notifyListeners();
  }

  Future<void> performAdditionalOperation() async {
    final currMode = additionalOperationMode;
    if (currMode == OperationMode.delete) {
      await deleteMultipleSongs(selectedSongs()).then((value) {
        sortWidgetController?.setActiveMode(OperationMode.none);
        cancelAdditionalOperation();
      });
    } else if (currMode == OperationMode.addToPlaylist) {
      final context = AppNavigator.context;
      if (context == null) return;
      await showDialog(
        context: context,
        builder: (context) => AddToPlaylist(selectedSongs()),
      ).whenComplete(() async {
        sortWidgetController?.setActiveMode(OperationMode.none);
        cancelAdditionalOperation();
      });
    }
  }

  Future<void> deleteMultipleSongs(List<MediaItem> songs) async {
    for (MediaItem element in songs) {
      if (await _library.isDownloaded(element.id)) {
        await _library.deleteDownloadedSong(element.id);
        await removeSong(element, true);
      } else {
        await _library.deleteCachedSong(element.id);
        await removeSong(element, false);
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
    sortWidgetController!.toggleSelectAll(false);
    sortWidgetController = null;
    additionalOperationMode = OperationMode.none;
    additionalOperationTempList = <MediaItem>[];
    additionalOperationTempMap.clear();
    notifyListeners();
  }
}

class LibrarySongsControllerRegistry {
  LibrarySongsControllerRegistry._();

  static LibrarySongsController? _controller;

  static LibrarySongsController? get current => _controller;

  static void register(LibrarySongsController controller) {
    _controller = controller;
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

class LibraryPlaylistsController extends ChangeNotifier
    implements TickerProvider {
  LibraryPlaylistsController({
    required PlaylistRepository playlistRepository,
    required LibraryRepository libraryRepository,
    required MusicServiceContract musicService,
    required SettingsRepository settingsRepository,
    required PipedServices pipedServices,
  }) : _playlistRepository = playlistRepository,
       _libraryRepository = libraryRepository,
       _musicService = musicService,
       _settingsRepository = settingsRepository,
       _pipedServices = pipedServices;

  final PlaylistRepository _playlistRepository;
  final LibraryRepository _libraryRepository;
  final MusicServiceContract _musicService;
  final SettingsRepository _settingsRepository;
  final PipedServices _pipedServices;

  late AnimationController controller;

  String playlistCreationMode = "local";
  static final initialPlaylists = [
    Playlist(
      title: AppLocalizationsEn().recentlyPlayed,
      playlistId: BoxNames.libRP,
      thumbnailUrl: Playlist.thumbPlaceholderUrl,
      isCloudPlaylist: false,
    ),
    Playlist(
      title: AppLocalizationsEn().favorites,
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
      title: AppLocalizationsEn().cachedOrOffline,
      playlistId: BoxNames.songsCache,
      thumbnailUrl: Playlist.thumbPlaceholderUrl,
      isCloudPlaylist: false,
    ),
    Playlist(
      title: AppLocalizationsEn().downloads,
      playlistId: BoxNames.songDownloads,
      thumbnailUrl: Playlist.thumbPlaceholderUrl,
      isCloudPlaylist: false,
    ),
  ];

  static bool isInitialPlaylistId(String playlistId) {
    return initialPlaylists.any(
      (playlist) => playlist.playlistId == playlistId,
    );
  }

  static List<Playlist> withInitialPlaylistsTail(Iterable<Playlist> playlists) {
    return [
      ...playlists.where(
        (playlist) => !isInitialPlaylistId(playlist.playlistId),
      ),
      ...initialPlaylists,
    ];
  }

  late ObservableList<Playlist> libraryPlaylists = ObservableList(
    initialPlaylists,
  );
  final isContentFetched = ObservableValue(false);
  bool creationInProgress = false;
  final textInputController = TextEditingController();
  List<Playlist> tempListContainer = [];

  bool isImporting = false;
  double importProgress = 0.0;

  Future<void> init() async {
    controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    await refreshLib();
  }

  @override
  Ticker createTicker(TickerCallback onTick) {
    return Ticker(onTick, debugLabel: 'LibraryPlaylistsController');
  }

  Future<void> refreshLib() async {
    final localPlaylists = (await _playlistRepository.getPlaylists()).reversed;
    libraryPlaylists.value = withInitialPlaylistsTail(localPlaylists);
    await refreshInitialPlaylistThumbs();

    if (_settingsRepository.getPiped()?['isLoggedIn'] == true) {
      await syncPipedPlaylist();
    }

    isContentFetched.value = true;
    notifyListeners();
  }

  /// Derive each built-in playlist's tile artwork from its first song (in
  /// display order). Empty built-ins fall back to the placeholder, which the
  /// tile renders as the original icon look. The static [initialPlaylists]
  /// instances are mutated in place — [withInitialPlaylistsTail] re-spreads
  /// the same objects, so every screen sees the update; built-ins are never
  /// persisted.
  ///
  /// Known limitation: download/cache completion doesn't call this; those
  /// tiles refresh on the next [refreshLib] (library visit / app start).
  Future<void> refreshInitialPlaylistThumbs() async {
    var changed = false;
    for (final playlist in initialPlaylists) {
      final songs = await _songsForInitialPlaylist(playlist.playlistId);
      // LIBRP is displayed newest-first (see fetchSongsFromDatabase).
      final displayOrdered = playlist.playlistId == BoxNames.libRP
          ? songs.reversed.toList()
          : songs;
      final newThumb = resolvePlaylistArt(
        currentUrl: playlist.thumbnailUrl,
        songs: displayOrdered,
        emptyFallbackUrl: Playlist.thumbPlaceholderUrl,
      );
      if (playlist.thumbnailUrl != newThumb) {
        playlist.thumbnailUrl = newThumb;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  Future<List<MediaItem>> _songsForInitialPlaylist(String id) async =>
      switch (id) {
        BoxNames.songDownloads => await _libraryRepository.getDownloadedSongs(),
        BoxNames.songsCache => await _libraryRepository.getCachedSongs(),
        BoxNames.libFav => await _libraryRepository.getFavoriteSongs(),
        BoxNames.libRP => await _libraryRepository.getRecentlyPlayedSongs(),
        BoxNames.libFavNotDownloaded =>
          await _libraryRepository.getFavoriteNotDownloadedSongs(),
        BoxNames.libImportDuplicates =>
          await _libraryRepository.getImportDuplicateSongs(),
        BoxNames.libImportReview =>
          await _libraryRepository.getImportReviewSongs(),
        _ => const <MediaItem>[],
      };

  /// Recompute a local playlist's stored artwork from its first song after
  /// its songs changed outside the playlist screen (e.g. the "Add to
  /// playlist" sheet). Built-in ids delegate to
  /// [refreshInitialPlaylistThumbs]; cloud playlists keep their own covers;
  /// an emptied user playlist keeps its last artwork.
  Future<void> recomputeLocalPlaylistThumb(String playlistId) async {
    if (isInitialPlaylistId(playlistId)) {
      await refreshInitialPlaylistThumbs();
      return;
    }
    final playlist = await _playlistRepository.getPlaylist(playlistId);
    if (playlist == null || playlist.isCloudPlaylist) return;
    final songs = await _playlistRepository.getPlaylistSongs(playlistId);
    final newThumb = resolvePlaylistArt(
      currentUrl: playlist.thumbnailUrl,
      songs: songs,
      emptyFallbackUrl: playlist.thumbnailUrl,
    );
    if (Thumbnail(playlist.thumbnailUrl).extraHigh ==
        Thumbnail(newThumb).extraHigh) {
      return;
    }
    await updatePlaylistIntoDb(playlist.copyWith(thumbnailUrl: newThumb));
  }

  Future<void> updatePlaylistIntoDb(Playlist playlist) async {
    await _playlistRepository.updatePlaylist(playlist);
    await refreshLib();
  }

  void removePipedPlaylists() {
    for (Playlist playlist in libraryPlaylists.toList()) {
      if (playlist.isPipedPlaylist) {
        libraryPlaylists.remove(playlist);
      }
    }
    notifyListeners();
  }

  Future<void> syncPipedPlaylist() async {
    final res = await _pipedServices.getAllPlaylists();
    final blacklistedPlaylist = await _playlistRepository
        .getBlacklistedPlaylistIds();
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
      final cloudPipedPlaylistsId = res.response
          .map((e) {
            return e['id'];
          })
          .whereType<String>()
          .toList();
      //add new playlist from cloud
      for (dynamic playlist in res.response) {
        if (!libPipedPlaylistsId.contains(playlist['id'])) {
          _insertBeforeInitialPlaylists(
            Playlist(
              title: playlist['name'],
              playlistId: playlist['id'],
              description: "Piped Playlist",
              thumbnailUrl: playlist['thumbnail'],
              isPipedPlaylist: true,
            ),
          );
        }
      }

      //remove playlist if removed from cloud
      for (Playlist playlist in libraryPlaylists.toList()) {
        if (!cloudPipedPlaylistsId.contains(playlist.playlistId) &&
            playlist.isPipedPlaylist) {
          libraryPlaylists.removeWhere(
            (element) => element.playlistId == playlist.playlistId,
          );
        }
      }
      notifyListeners();
    }
  }

  Future<bool> renamePlaylist(Playlist playlist) async {
    String title = textInputController.text;
    if (title.trim().isNotEmpty) {
      if (playlist.isPipedPlaylist) {
        final res = await _pipedServices.renamePlaylist(
          playlist.playlistId,
          title,
        );
        if (res.code == 0) return false;
        playlist.newTitle = title;
      } else {
        title = "${title[0].toUpperCase()}${title.substring(1).toLowerCase()}";
        playlist.newTitle = title;
        await _playlistRepository.updatePlaylist(playlist);
      }
      await refreshLib();
      return true;
    }
    return false;
  }

  void changeCreationMode(String? val) {
    playlistCreationMode = val!;
    notifyListeners();
  }

  Future<bool> createNewPlaylist({
    bool createPlaylistNAddSong = false,
    List<MediaItem>? songItems,
  }) async {
    String title = textInputController.text;
    if (title.trim().isNotEmpty) {
      dynamic newPlaylist;

      if (playlistCreationMode == "piped") {
        creationInProgress = true;
        notifyListeners();
        final res = await _pipedServices.createPlaylist(title);
        if (res.code == 1) {
          newPlaylist = Playlist(
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
          creationInProgress = false;
          notifyListeners();
          return false;
        }
      } else {
        newPlaylist = Playlist(
          title: title,
          playlistId: "LIB${DateTime.now().millisecondsSinceEpoch}",
          thumbnailUrl: songItems != null
              ? songItems[0].artUri.toString()
              : Playlist.thumbPlaceholderUrl,
          description: "Library Playlist",
          isCloudPlaylist: false,
        );
        await _playlistRepository.savePlaylist(newPlaylist);
      }

      libraryPlaylists.insert(0, newPlaylist);

      if (createPlaylistNAddSong && playlistCreationMode == "local") {
        await _playlistRepository.addSongsToPlaylist(
          newPlaylist.playlistId,
          songItems!,
        );
      } else if (createPlaylistNAddSong && playlistCreationMode == "piped") {
        final songIds = songItems!.map((e) => e.id).toList();
        await _pipedServices.addToPlaylist(newPlaylist.playlistId, songIds);
      }
      creationInProgress = false;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> blacklistPipedPlaylist(Playlist playlist) async {
    await _playlistRepository.addBlacklistedPlaylistId(playlist.playlistId);
    libraryPlaylists.remove(playlist);
    notifyListeners();
  }

  Future<void> resetBlacklistedPlaylist() async {
    await _playlistRepository.clearBlacklistedPlaylistIds();
    await syncPipedPlaylist();
    notifyListeners();
  }

  void onSort(SortType sortType, bool isAscending) {
    final playlists = libraryPlaylists
        .where((playlist) => !isInitialPlaylistId(playlist.playlistId))
        .toList();
    sortPlayLists(playlists, sortType, isAscending);
    libraryPlaylists.value = withInitialPlaylistsTail(playlists);
    notifyListeners();
  }

  void _insertBeforeInitialPlaylists(Playlist playlist) {
    final firstInitialPlaylistIndex = libraryPlaylists.indexWhere(
      (playlist) => isInitialPlaylistId(playlist.playlistId),
    );
    libraryPlaylists.insert(
      firstInitialPlaylistIndex == -1
          ? libraryPlaylists.length
          : firstInitialPlaylistIndex,
      playlist,
    );
    notifyListeners();
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
      content = await _musicService.getPlaylistOrAlbumSongs(
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

    await refreshLib();
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

    await refreshLib();
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
    final results = await _musicService.search(
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
    final existingTitles = [
      ...initialPlaylists.map((playlist) => playlist.title),
      ...(await _playlistRepository.getPlaylists()).map(
        (playlist) => playlist.title,
      ),
    ];

    var newPlaylistId = "LIB${DateTime.now().microsecondsSinceEpoch}";
    while (await _playlistRepository.getPlaylist(newPlaylistId) != null) {
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

    await _playlistRepository.savePlaylist(newPlaylist);
    await _playlistRepository.replacePlaylistSongs(newPlaylistId, tracks);
    return newPlaylist;
  }

  Future<int> _addImportedConflicts(List<MediaItem> tracks) async {
    final favoriteIds = (await _libraryRepository.getFavoriteSongs())
        .map((song) => song.id)
        .toSet();
    final downloadedIds = (await _libraryRepository.getDownloadedSongs())
        .map((song) => song.id)
        .toSet();
    final conflictIds = (await _libraryRepository.getImportDuplicateSongs())
        .map((song) => song.id)
        .toSet();

    var conflictAddedCount = 0;
    for (final song in tracks) {
      final alreadyKnown =
          favoriteIds.contains(song.id) || downloadedIds.contains(song.id);
      if (alreadyKnown && !conflictIds.contains(song.id)) {
        await _libraryRepository.addImportDuplicate(song);
        conflictIds.add(song.id);
        conflictAddedCount++;
      }
    }

    return conflictAddedCount;
  }

  Future<int> _addImportReviewCandidates(List<MediaItem> tracks) async {
    final reviewIds = (await _libraryRepository.getImportReviewSongs())
        .map((song) => song.id)
        .toSet();

    var reviewAddedCount = 0;
    for (final song in tracks) {
      if (!reviewIds.contains(song.id)) {
        await _libraryRepository.addImportReview(song);
        reviewIds.add(song.id);
        reviewAddedCount++;
      }
    }

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
    final sortWidgetController = SortWidgetRegistry.maybeOf(tag);
    sortWidgetController?.textEditingController.clear();
    tempListContainer.clear();
  }

  /// See [LibrarySongsController.clearStaleSearch].
  void clearStaleSearch() {
    if (tempListContainer.isEmpty) return;
    libraryPlaylists.value = tempListContainer.toList();
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
      _setImportState(isImporting: true, importProgress: 0.1);

      // Show progress dialog
      if (context.mounted) {
        await _showImportProgressDialog(context);
      }

      final result = await FilePickerService.openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
        confirmButtonText: context.l10n.importPlaylist,
      );

      if (result == null) {
        // User cancelled the picker
        _closeImportProgressDialog(context);
        _setImportState(isImporting: false, importProgress: 0.0);
        return;
      }

      _setImportProgress(0.2);

      final file = File(result.path);
      if (!await file.exists()) {
        throw FileSystemException(context.l10n.fileNotFound);
      }

      final jsonString = await file.readAsString();
      _setImportProgress(0.3);

      final jsonData = jsonDecode(jsonString);
      _setImportProgress(0.4);

      // Validate JSON structure
      if (!jsonData.containsKey('playlistInfo') ||
          !jsonData.containsKey('songs')) {
        throw FormatException(context.l10n.invalidPlaylistFile);
      }

      // Create new playlist ID
      final playlistInfo = jsonData['playlistInfo'];
      final newPlaylistId = "LIB${DateTime.now().millisecondsSinceEpoch}";
      _setImportProgress(0.5);

      // Create playlist object
      final newPlaylist = Playlist(
        title: "${playlistInfo['title']} (${context.l10n.imported})",
        playlistId: newPlaylistId,
        thumbnailUrl:
            playlistInfo['thumbnailUrl'] ??
            (playlistInfo['thumbnails'] != null &&
                    playlistInfo['thumbnails'].isNotEmpty
                ? playlistInfo['thumbnails'][0]['url']
                : Playlist.thumbPlaceholderUrl),
        description:
            playlistInfo['description'] ?? context.l10n.importedPlaylist,
        isCloudPlaylist: false,
      );
      _setImportProgress(0.6);

      // Save playlist to database
      await _playlistRepository.savePlaylist(newPlaylist);
      _setImportProgress(0.7);

      // Save songs to playlist
      final songsList = jsonData['songs'] as List;

      // Update progress as songs are added
      final totalSongs = songsList.length;
      final importedSongs = <MediaItem>[];
      for (int i = 0; i < totalSongs; i++) {
        importedSongs.add(MediaItemBuilder.fromJson(songsList[i]));
        // Update progress from 70% to 95% based on song import progress
        _setImportProgress(0.7 + (0.25 * (i + 1) / totalSongs));
      }

      await _playlistRepository.replacePlaylistSongs(
        newPlaylistId,
        importedSongs,
      );
      _setImportProgress(1.0);

      // Close progress dialog if it's still open
      _closeImportProgressDialog(context);

      // Refresh library to show the new playlist
      await refreshLib();

      // Show success message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          snackbar(
            context,
            "${context.l10n.playlistImportedMsg}: ${newPlaylist.title}",
            size: SanckBarSize.MEDIUM,
          ),
        );
      }
    } catch (e) {
      // Close progress dialog if it's still open
      _closeImportProgressDialog(context);

      printERROR("Error importing playlist: $e");

      String errorMsg = context.l10n.importError;
      if (e is FileSystemException) {
        errorMsg = context.l10n.importErrorFileAccess;
      } else if (e is FormatException) {
        errorMsg = context.l10n.importErrorFormat;
      } else if (e.toString().contains("invalidPlaylistFile")) {
        errorMsg = context.l10n.invalidPlaylistFile;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(snackbar(context, errorMsg, size: SanckBarSize.MEDIUM));
      }
    } finally {
      _setImportState(isImporting: false, importProgress: 0.0);
    }
  }

  void _setImportState({
    required bool isImporting,
    required double importProgress,
  }) {
    this.isImporting = isImporting;
    this.importProgress = importProgress;
    notifyListeners();
  }

  void _setImportProgress(double value) {
    importProgress = value;
    notifyListeners();
  }

  // Helper method to show import progress dialog
  Future<void> _showImportProgressDialog(BuildContext context) async {
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Theme.of(dialogContext).cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Text(
            context.l10n.importingPlaylist,
            style: Theme.of(dialogContext).textTheme.titleLarge,
          ),
          content: AnimatedBuilder(
            animation: this,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: importProgress,
                  backgroundColor: Theme.of(
                    dialogContext,
                  ).colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(dialogContext).colorScheme.secondary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "${(importProgress * 100).toInt()}%",
                  style: Theme.of(dialogContext).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
  }

  void _closeImportProgressDialog(BuildContext context) {
    if (!context.mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }
}

class LibraryPlaylistsControllerRegistry {
  LibraryPlaylistsControllerRegistry._();

  static LibraryPlaylistsController? _controller;

  static LibraryPlaylistsController? get current => _controller;

  static void register(LibraryPlaylistsController controller) {
    _controller = controller;
  }
}

class LibraryAlbumsController extends ChangeNotifier {
  LibraryAlbumsController({required LibraryRepository libraryRepository})
    : _libraryRepository = libraryRepository;

  final LibraryRepository _libraryRepository;

  List<Album> libraryAlbums = [];
  bool isContentFetched = false;
  List<Album> tempListContainer = [];

  Future<void> init() async {
    await refreshLib();
  }

  Future<void> refreshLib() async {
    libraryAlbums = await _libraryRepository.getAlbums();
    isContentFetched = true;
    notifyListeners();
  }

  void onSort(SortType sortType, bool isAscending) {
    final albumList = List<Album>.from(libraryAlbums);
    sortAlbumNSingles(albumList, sortType, isAscending);
    libraryAlbums = albumList;
    notifyListeners();
  }

  void onSearchStart(String? tag) {
    tempListContainer = libraryAlbums.toList();
  }

  void onSearch(String value, String? tag) {
    libraryAlbums = tempListContainer
        .where(
          (element) => SearchFilter.matches({'title': element.title}, value),
        )
        .toList();
    notifyListeners();
  }

  void onSearchClose(String? tag) {
    libraryAlbums = tempListContainer.toList();
    // Clear search bar text when closing
    final sortWidgetController = SortWidgetRegistry.maybeOf(tag);
    sortWidgetController?.textEditingController.clear();
    tempListContainer.clear();
    notifyListeners();
  }

  /// See [LibrarySongsController.clearStaleSearch].
  void clearStaleSearch() {
    if (tempListContainer.isEmpty) return;
    libraryAlbums = tempListContainer.toList();
    tempListContainer.clear();
    notifyListeners();
  }
}

class LibraryArtistsController extends ChangeNotifier {
  LibraryArtistsController({required LibraryRepository libraryRepository})
    : _libraryRepository = libraryRepository;

  final LibraryRepository _libraryRepository;

  List<Artist> libraryArtists = [];
  bool isContentFetched = false;
  List<Artist> tempListContainer = [];

  Future<void> init() async {
    await refreshLib();
  }

  Future<void> refreshLib() async {
    libraryArtists = await _libraryRepository.getArtists();
    isContentFetched = true;
    notifyListeners();
  }

  void onSort(SortType sortType, bool isAscending) {
    final artistList = List<Artist>.from(libraryArtists);
    sortArtist(artistList, sortType, isAscending);
    libraryArtists = artistList;
    notifyListeners();
  }

  void onSearchStart(String? tag) {
    tempListContainer = libraryArtists.toList();
  }

  void onSearch(String value, String? tag) {
    libraryArtists = tempListContainer
        .where(
          (element) => SearchFilter.matches({'title': element.name}, value),
        )
        .toList();
    notifyListeners();
  }

  void onSearchClose(String? tag) {
    libraryArtists = tempListContainer.toList();
    // Clear search bar text when closing
    final sortWidgetController = SortWidgetRegistry.maybeOf(tag);
    sortWidgetController?.textEditingController.clear();
    tempListContainer.clear();
    notifyListeners();
  }

  /// See [LibrarySongsController.clearStaleSearch].
  void clearStaleSearch() {
    if (tempListContainer.isEmpty) return;
    libraryArtists = tempListContainer.toList();
    tempListContainer.clear();
    notifyListeners();
  }
}

class LibraryAlbumsControllerRegistry {
  LibraryAlbumsControllerRegistry._();

  static LibraryAlbumsController? _controller;

  static LibraryAlbumsController? get current => _controller;

  static void register(LibraryAlbumsController controller) {
    _controller = controller;
  }
}

class LibraryArtistsControllerRegistry {
  LibraryArtistsControllerRegistry._();

  static LibraryArtistsController? _controller;

  static LibraryArtistsController? get current => _controller;

  static void register(LibraryArtistsController controller) {
    _controller = controller;
  }
}

class LibrarySearchesController extends ChangeNotifier {
  LibrarySearchesController({required LibraryRepository libraryRepository})
    : _libraryRepository = libraryRepository;

  final LibraryRepository _libraryRepository;
  final savedSearches = <String>[];
  var isContentFetched = false;

  Future<void> init() async {
    await refreshLib();
  }

  Future<void> refreshLib() async {
    savedSearches
      ..clear()
      ..addAll(await _libraryRepository.getSearches());
    isContentFetched = true;
    notifyListeners();
  }

  Future<void> saveSearch(String query) async {
    if (query.trim().isEmpty || savedSearches.contains(query)) return;
    await _libraryRepository.addSearch(query);
    savedSearches.add(query);
    notifyListeners();
  }

  Future<void> deleteSearch(String query) async {
    await _libraryRepository.deleteSearch(query);
    savedSearches.remove(query);
    notifyListeners();
  }
}
