import 'dart:async';

import 'dart:convert';
import 'dart:io';
import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/material.dart';
import 'package:harmonymusic/l10n/l10n.dart';
import 'package:harmonymusic/models/thumbnail.dart';
import 'package:harmonymusic/services/permission_service.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/widgets/snackbar.dart';
import 'package:harmonymusic/utils/helper.dart';
import 'package:harmonymusic/utils/observable_state.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

import '../../../mixins/additional_operation_mixin.dart';
import '../../../services/constant.dart';
import '../../../base_class/playlist_album_screen_con_base.dart';
import '../../../models/album.dart' show Album;
import '../../../models/media_Item_builder.dart';
import '../../../models/playlist.dart';
import '../../../services/piped_service.dart';
import '../Home/home_screen_controller.dart';
import '../Library/library_controller.dart';

class PlaylistScreenControllerRegistry {
  static final _controllers = <String, PlaylistScreenController>{};

  static void register(String tag, PlaylistScreenController controller) {
    _controllers[tag] = controller;
  }

  static void unregister(String tag, PlaylistScreenController controller) {
    if (_controllers[tag] == controller) {
      _controllers.remove(tag);
    }
  }

  static PlaylistScreenController? maybeOf(String? tag) =>
      tag == null ? null : _controllers[tag];
}

///PlaylistScreenController handles playlist screen
///
///Playlist title,image,songs
class PlaylistScreenController extends PlaylistAlbumScreenControllerBase
    with AdditionalOperationMixin {
  PlaylistScreenController({
    required super.musicServices,
    required super.playlistRepository,
    required super.libraryRepository,
    required HomeScreenController homeScreenController,
    required SettingsScreenController settingsScreenController,
    required PipedServices pipedServices,
  }) : _homeScreenController = homeScreenController,
       _settingsScreenController = settingsScreenController,
       _pipedServices = pipedServices;

  final HomeScreenController _homeScreenController;
  final SettingsScreenController _settingsScreenController;
  final PipedServices _pipedServices;

  final playlist = ObservableValue(
    Playlist(
      title: "",
      playlistId: "",
      thumbnailUrl: Playlist.thumbPlaceholderUrl,
    ),
  );
  final isDefaultPlaylist = ObservableValue(false);

  bool isExporting = false;
  double exportProgress = 0.0;

  String generatedYtmPlaylistUrl = '';

  // Title animation

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  AnimationController get animationController => _animationController;

  Animation<double> get scaleAnimation => _scaleAnimation;

  void initialize({required List args, required TickerProvider vsync}) {
    _animationController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 400),
    );

    _scaleAnimation = Tween<double>(
      begin: 0,
      end: 1.0,
    ).animate(animationController);

    final Playlist? playlist = args[0];
    final playlistId = args[1];
    unawaited(fetchPlaylistDetails(playlist, playlistId));
    unawaited(
      Future.delayed(const Duration(milliseconds: 200), () {
        if (isClosed) return;
        _homeScreenController.whenHomeScreenOnTop();
      }),
    );
  }

  ///Fetches playlist details from the service
  @override
  Future<void> fetchPlaylistDetails(
    Playlist? playlist_,
    String playlistId,
  ) async {
    final generation = beginAsyncLoad();
    final isIdOnly = playlist_ == null;
    final isPipedPlaylist = playlist_?.isPipedPlaylist ?? false;
    isDefaultPlaylist.value =
        playlistId == BoxNames.songDownloads ||
        playlistId == BoxNames.songsCache ||
        playlistId == BoxNames.libRP ||
        playlistId == BoxNames.libFav ||
        playlistId == BoxNames.libFavNotDownloaded ||
        playlistId == BoxNames.libImportDuplicates ||
        playlistId == BoxNames.libImportReview;
    notifyListeners();

    if (!isIdOnly && !playlist_.isCloudPlaylist) {
      playlist.value = playlist_;
      notifyListeners();
      await _animationController.forward();
      if (!isAsyncLoadActive(generation)) return;
      if (playlistId == BoxNames.libFavNotDownloaded) {
        await fetchLikedNotDownloadedSongs(generation: generation);
      } else {
        await fetchSongsFromDatabase(playlistId, generation: generation);
      }
      if (!isAsyncLoadActive(generation)) return;
      isContentFetched.value = true;
      notifyListeners();

      unawaited(
        Future.delayed(const Duration(seconds: 1), () {
          if (!isAsyncLoadActive(generation)) return;
          unawaited(_updatePlaylistThumbSongBased());
        }),
      );

      return;
    }

    if (!isIdOnly) {
      playlist.value = playlist_;
      notifyListeners();
      await _animationController.forward();
      if (!isAsyncLoadActive(generation)) return;
    }

    try {
      // Check if the playlist is offline
      if (await checkIfAddedToLibrary(playlistId)) {
        if (!isAsyncLoadActive(generation)) return;
        final localSongs = await playlistRepository.getPlaylistSongs(
          playlistId,
        );
        if (!isAsyncLoadActive(generation)) return;
        if (localSongs.isEmpty) {
          await _fetchSongOnline(
            playlistId,
            isIdOnly,
            isPipedPlaylist,
            generation: generation,
          ).then((value) async {
            if (!isAsyncLoadActive(generation)) return;
            await updateSongsIntoDb();
          });
        } else {
          // If the playlist is offline, fetch the songs from the local database
          // Playlist details are already fetched in _checkIfAddedToLibrary method
          await fetchSongsFromDatabase(playlistId, generation: generation);
        }
      } else {
        await _fetchSongOnline(
          playlistId,
          isIdOnly,
          isPipedPlaylist,
          generation: generation,
        );
      }
      if (!isAsyncLoadActive(generation)) return;
      isContentFetched.value = true;
      notifyListeners();
    } catch (e) {
      // Handle any errors that occur during the fetch
      printERROR("Error fetching playlist details: $e");
    }
  }

  Future<void> fetchLikedNotDownloadedSongs({int? generation}) async {
    final songs = await libraryRepository.getFavoriteNotDownloadedSongs();
    if (generation != null && !isAsyncLoadActive(generation)) return;
    songList.value = songs;
    notifyListeners();
    checkDownloadStatus();
  }

  Future<void> _fetchSongOnline(
    String id,
    bool isIdOnly,
    bool isPipedPlaylist, {
    int? generation,
  }) async {
    isContentFetched.value = false;
    notifyListeners();

    if (isPipedPlaylist) {
      final songs = await _pipedServices.getPlaylistSongs(id);
      if (generation != null && !isAsyncLoadActive(generation)) return;
      songList.value = songs;
      isContentFetched.value = true;
      notifyListeners();
      checkDownloadStatus();
      return;
    }

    final content = await musicServices.getPlaylistOrAlbumSongs(playlistId: id);
    if (generation != null && !isAsyncLoadActive(generation)) return;

    if (isIdOnly) {
      content['playlistId'] = id;
      playlist.value = Playlist.fromJson(content);
      notifyListeners();
      await _animationController.forward();
      if (generation != null && !isAsyncLoadActive(generation)) return;
    }
    songList.value = List<MediaItem>.from(content['tracks']);
    notifyListeners();
    checkDownloadStatus();
  }

  @override
  Future<void> syncPlaylistSongs() async {
    await _fetchSongOnline(playlist.value.playlistId, false, false).then((
      value,
    ) async {
      await updateSongsIntoDb();
      isContentFetched.value = true;
      notifyListeners();
    });
  }

  @override
  Future<bool> checkIfAddedToLibrary(String id) async {
    final localPlaylist = await playlistRepository.getPlaylist(id);
    if (isClosed) return false;
    isAddedToLibrary.value = localPlaylist != null;
    if (localPlaylist != null) playlist.value = localPlaylist;
    notifyListeners();
    return isAddedToLibrary.value;
  }

  @override
  Future<bool> addNRemoveFromLibrary(dynamic content, {bool add = true}) async {
    try {
      if (content.isPipedPlaylist && !add) {
        //remove piped playlist from lib
        final res = await _pipedServices.deletePlaylist(content.playlistId);
        await LibraryPlaylistsControllerRegistry.current?.syncPipedPlaylist();
        return (res.code == 1);
      } else {
        final id = content.playlistId;
        if (add) {
          await playlistRepository.savePlaylist(content);
          await updateSongsIntoDb();
        } else {
          await playlistRepository.deletePlaylist(id);
        }
        isAddedToLibrary.value = add;
        notifyListeners();
      }
      //Update frontend
      await LibraryPlaylistsControllerRegistry.current?.refreshLib();
      if (!content.isCloudPlaylist && !add) {
        await playlistRepository.deletePlaylistSongBox(content.playlistId);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> updateSongsIntoDb() async {
    await playlistRepository.replacePlaylistSongs(
      playlist.value.playlistId,
      songList.toList(),
    );

    // Update the playlist thumbnail based on the first song's thumbnail
    await _updatePlaylistThumbSongBased();
  }

  @override
  Future<void> deleteMultipleSongs(List<MediaItem> songs) async {
    final id = playlist.value.playlistId;
    if (id == BoxNames.libFavNotDownloaded) {
      for (MediaItem element in songs) {
        await libraryRepository.setFavorite(element, false);
        songList.removeWhere((song) => song.id == element.id);
      }
      await _updatePlaylistThumbSongBased();
      return;
    }
    if (id == BoxNames.libImportDuplicates || id == BoxNames.libImportReview) {
      for (MediaItem element in songs) {
        if (id == BoxNames.libImportDuplicates) {
          await libraryRepository.deleteImportDuplicate(element.id);
        } else {
          await libraryRepository.deleteImportReview(element.id);
        }
        songList.removeWhere((song) => song.id == element.id);
      }
      await _updatePlaylistThumbSongBased();
      return;
    }
    final offline = id == BoxNames.songsCache || id == BoxNames.songDownloads;

    for (MediaItem element in songs) {
      if (offline) {
        if (id == BoxNames.songDownloads) {
          await libraryRepository.deleteDownloadedSong(element.id);
        } else {
          await libraryRepository.deleteCachedSong(element.id);
        }
        await LibrarySongsControllerRegistry.current?.removeSong(
          element,
          id == BoxNames.songDownloads,
        );
      } else {
        await playlistRepository.removeSongsFromPlaylist(id, [element]);
      }

      songList.removeWhere((song) => song.id == element.id);
    }

    // Update the playlist thumbnail based on the first song's thumbnail
    await _updatePlaylistThumbSongBased();
  }

  Future<void> addNRemoveItemsInList(
    MediaItem? item, {
    required String action,
    int? index,
  }) async {
    if (action == 'add') {
      if (tempListContainer.isNotEmpty) {
        index != null
            ? tempListContainer.insert(index, item!)
            : tempListContainer.add(item!);
        return;
      }
      index != null ? songList.insert(index, item!) : songList.add(item!);
    } else {
      if (tempListContainer.isNotEmpty) {
        index != null
            ? tempListContainer.removeAt(index)
            : tempListContainer.remove(item);
      }
      index != null ? songList.removeAt(index) : songList.remove(item);
    }

    // update the playlist thumbnail based on the first song's thumbnail
    await _updatePlaylistThumbSongBased();
  }

  @override
  void fetchAlbumDetails(Album? album_, String albumId) {} // Not used in this class

  /// This function updates the local playlist thumbnail based on the first song's thumbnail
  Future<void> _updatePlaylistThumbSongBased() async {
    final currentPlaylist = playlist.value;

    if (isDefaultPlaylist.value || currentPlaylist.isCloudPlaylist) {
      return;
    }

    Playlist updatedPlaylist;
    if (songList.isNotEmpty) {
      updatedPlaylist = currentPlaylist.copyWith(
        thumbnailUrl: songList[0].artUri.toString(),
      );
    } else {
      updatedPlaylist = currentPlaylist.copyWith(
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
      );
    }

    // Check if the thumbnail URL is the same as the current one
    // If it is, no need to update the playlist
    if (Thumbnail(currentPlaylist.thumbnailUrl).extraHigh ==
        Thumbnail(updatedPlaylist.thumbnailUrl).extraHigh) {
      return;
    }

    // Update the playlist thumbnail URL
    playlist.value = updatedPlaylist;
    notifyListeners();
    await LibraryPlaylistsControllerRegistry.current?.updatePlaylistIntoDb(
      updatedPlaylist,
    );
  }

  void close() {
    closeController();
    tempListContainer.clear();
    _animationController.dispose();
    _homeScreenController.whenHomeScreenOnTop();
  }

  Future<void> exportPlaylistToJson(BuildContext context) async {
    if (!await PermissionService.getExtStoragePermission()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          snackbar(
            context,
            context.l10n.permissionDenied,
            size: SanckBarSize.MEDIUM,
          ),
        );
      }
      return;
    }

    try {
      _setExportState(isExporting: true, exportProgress: 0.1);

      // Show progress dialog
      if (context.mounted) {
        await _showProgressDialog(context, context.l10n.exportingPlaylist);
      }

      // Get appropriate directory based on platform
      final Directory exportDir = await _getExportDirectory();
      _setExportProgress(0.2);

      // Create playlist data map
      final playlistData = {
        "playlistInfo": playlist.value.toJson(),
        "songs": songList.map((song) => MediaItemBuilder.toJson(song)).toList(),
        "exportDate": DateTime.now().toIso8601String(),
        "appVersion": _settingsScreenController.currentVersion,
      };
      _setExportProgress(0.5);

      // Generate filename with playlist name
      final sanitizedName = playlist.value.title.replaceAll(
        RegExp(r'[^\w\s]+'),
        '_',
      );

      // Find available filename with incremental suffix if needed
      String filename = "$sanitizedName.json";
      String filePath = "${exportDir.path}/$filename";
      File file = File(filePath);

      int counter = 1;
      while (await file.exists()) {
        filename = "${sanitizedName}_$counter.json";
        filePath = "${exportDir.path}/$filename";
        file = File(filePath);
        counter++;
      }

      _setExportProgress(0.7);

      // Write JSON to file
      await file.writeAsString(jsonEncode(playlistData));
      _setExportProgress(1.0);

      // Close progress dialog if it's still open
      _closeProgressDialog(context);

      // Show success message with platform-specific path info
      String locationMsg = _getLocationMessage(exportDir.path);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          snackbar(
            context,
            "${context.l10n.playlistExportedMsg}: $locationMsg",
            size: SanckBarSize.MEDIUM,
          ),
        );
      }
    } catch (e) {
      // Close progress dialog if it's still open
      _closeProgressDialog(context);

      printERROR("Error exporting playlist: $e");

      String errorMsg = context.l10n.exportError;
      if (e is FileSystemException) {
        if (e.osError?.errorCode == 13) {
          errorMsg = context.l10n.exportErrorPermission;
        } else if (e.osError?.errorCode == 28) {
          errorMsg = context.l10n.exportErrorStorage;
        }
      } else if (e is FormatException) {
        errorMsg = context.l10n.exportErrorFormat;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(snackbar(context, errorMsg, size: SanckBarSize.MEDIUM));
      }
    } finally {
      _setExportState(isExporting: false, exportProgress: 0.0);
    }
  }

  Future<void> exportPlaylistToCsv(BuildContext context) async {
    if (!await PermissionService.getExtStoragePermission()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          snackbar(
            context,
            context.l10n.permissionDenied,
            size: SanckBarSize.MEDIUM,
          ),
        );
      }
      return;
    }

    try {
      _setExportState(isExporting: true, exportProgress: 0.1);

      // Show progress dialog
      if (context.mounted) {
        await _showProgressDialog(context, context.l10n.exportingPlaylist);
      }

      // Get appropriate directory based on platform
      final Directory exportDir = await _getExportDirectory();
      _setExportProgress(0.2);

      // Build CSV content
      final csvContent = _generateCsvContent();
      _setExportProgress(0.5);

      // Generate filename with playlist name
      final sanitizedName = playlist.value.title.replaceAll(
        RegExp(r'[^\w\s]+'),
        '_',
      );

      // Find available filename with incremental suffix if needed
      String filename = "$sanitizedName.csv";
      String filePath = "${exportDir.path}/$filename";
      File file = File(filePath);

      int counter = 1;
      while (await file.exists()) {
        filename = "${sanitizedName}_$counter.csv";
        filePath = "${exportDir.path}/$filename";
        file = File(filePath);
        counter++;
      }

      _setExportProgress(0.7);

      // Write CSV to file
      await file.writeAsString(csvContent);
      _setExportProgress(1.0);

      // Close progress dialog if it's still open
      _closeProgressDialog(context);

      // Show success message with platform-specific path info
      String locationMsg = _getLocationMessage(exportDir.path);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          snackbar(
            context,
            "${context.l10n.playlistExportedMsg}: $locationMsg",
            size: SanckBarSize.MEDIUM,
          ),
        );
      }
    } catch (e) {
      // Close progress dialog if it's still open
      _closeProgressDialog(context);

      printERROR("Error exporting playlist to CSV: $e");

      String errorMsg = context.l10n.exportError;
      if (e is FileSystemException) {
        if (e.osError?.errorCode == 13) {
          errorMsg = context.l10n.exportErrorPermission;
        } else if (e.osError?.errorCode == 28) {
          errorMsg = context.l10n.exportErrorStorage;
        }
      } else if (e is FormatException) {
        errorMsg = context.l10n.exportErrorFormat;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(snackbar(context, errorMsg, size: SanckBarSize.MEDIUM));
      }
    } finally {
      _setExportState(isExporting: false, exportProgress: 0.0);
    }
  }

  String _generateCsvContent() {
    final buffer = StringBuffer();

    // CSV Header
    buffer.writeln(
      'PlaylistBrowseId,PlaylistName,MediaId,Title,Artists,Duration,ThumbnailUrl,AlbumId,AlbumTitle,ArtistIds',
    );

    // CSV Rows - one for each song
    for (final song in songList) {
      // Keep playlistBrowseId blank for offline/piped playlists
      final playlistBrowseId =
          (!playlist.value.isCloudPlaylist || playlist.value.isPipedPlaylist)
          ? ''
          : _escapeCsvField(playlist.value.playlistId);
      final playlistName = _escapeCsvField(playlist.value.title);
      final mediaId = _escapeCsvField(song.id);
      final title = _escapeCsvField(song.title);

      // Extract artists as comma-separated string
      final artistsList = song.extras?['artists'] as List?;
      final artists = artistsList != null
          ? _escapeCsvField(artistsList.map((a) => a['name']).join(', '))
          : '';

      // Format duration as HH:MM:SS or MM:SS
      final duration = song.duration != null
          ? _formatDuration(song.duration!)
          : '';

      final thumbnailUrl = _escapeCsvField(song.artUri.toString());

      // Extract album information
      final albumData = song.extras?['album'] as Map?;
      final albumId = albumData != null
          ? _escapeCsvField(albumData['id'] ?? '')
          : '';
      final albumTitle = albumData != null
          ? _escapeCsvField(albumData['name'] ?? '')
          : '';

      // Extract all artist IDs (comma-separated)
      final artistIds = artistsList != null && artistsList.isNotEmpty
          ? _escapeCsvField(artistsList.map((a) => a['id'] ?? '').join(','))
          : '';

      buffer.writeln(
        '$playlistBrowseId,$playlistName,$mediaId,$title,$artists,$duration,$thumbnailUrl,$albumId,$albumTitle,$artistIds',
      );
    }

    return buffer.toString();
  }

  String _escapeCsvField(String field) {
    // Escape double quotes by doubling them
    String escaped = field.replaceAll('"', '""');

    // If field contains comma, newline, or double quote, wrap in quotes
    if (escaped.contains(',') ||
        escaped.contains('\n') ||
        escaped.contains('"')) {
      escaped = '"$escaped"';
    }

    return escaped;
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  // Helper method to get the appropriate export directory for each platform
  Future<Directory> _getExportDirectory() async {
    Directory directory;
    const appFolderName = "HarmonyMusic";

    try {
      if (Platform.isAndroid) {
        // Android: use Downloads folder
        directory = Directory('/storage/emulated/0/Download/$appFolderName');
      } else if (Platform.isIOS) {
        // iOS: use Documents directory
        final docDir = await path_provider.getApplicationDocumentsDirectory();
        directory = Directory('${docDir.path}/$appFolderName');
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // Desktop platforms: use Downloads folder in user's home directory
        final homeDir =
            Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'] ??
            '.';
        directory = Directory('$homeDir/Downloads/$appFolderName');
      } else {
        // Fallback: use temporary directory
        final tempDir = await path_provider.getTemporaryDirectory();
        directory = Directory('${tempDir.path}/$appFolderName');
      }

      // Create directory if it doesn't exist
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      return directory;
    } catch (e) {
      // Fallback to app's documents directory if any error occurs
      final appDocDir = await path_provider.getApplicationDocumentsDirectory();
      directory = Directory('${appDocDir.path}/$appFolderName');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory;
    }
  }

  // Helper method to get a user-friendly location message
  String _getLocationMessage(String path) {
    if (Platform.isAndroid) {
      return "Downloads/HarmonyMusic";
    } else if (Platform.isIOS) {
      return "Files App > HarmonyMusic";
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return "Downloads/HarmonyMusic";
    } else {
      return path.split('/').last;
    }
  }

  void _setExportState({
    required bool isExporting,
    required double exportProgress,
  }) {
    this.isExporting = isExporting;
    this.exportProgress = exportProgress;
    notifyListeners();
  }

  void _setExportProgress(double value) {
    exportProgress = value;
    notifyListeners();
  }

  // Helper method to show progress dialog
  Future<void> _showProgressDialog(BuildContext context, String title) async {
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
            title,
            style: Theme.of(dialogContext).textTheme.titleLarge,
          ),
          content: AnimatedBuilder(
            animation: this,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: exportProgress,
                  backgroundColor: Theme.of(
                    dialogContext,
                  ).colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(dialogContext).colorScheme.secondary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "${(exportProgress * 100).toInt()}%",
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

  void _closeProgressDialog(BuildContext context) {
    if (!context.mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }
}
