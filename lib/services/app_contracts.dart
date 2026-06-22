import 'package:audio_service/audio_service.dart';
import 'package:file_selector/file_selector.dart';

import '../utils/helper.dart';

abstract class MusicServiceContract {
  set hlCode(String code);

  Future<dynamic> getHome({int limit = 4});

  Future<List<Map<String, dynamic>>> getCharts(
    String catogory, {
    String? countryCode,
  });

  dynamic getContentRelatedToSong(String videoId, String hlCode);

  Future<Map<String, dynamic>> getPlaylistOrAlbumSongs({
    String? playlistId,
    String? albumId,
    int limit = 3000,
    bool related = false,
    int suggestionsLimit = 0,
  });

  Future<List> getSongWithId(String songId);

  Future<Map<String, dynamic>> getWatchPlaylist({
    String videoId = "",
    String? playlistId,
    int limit = 25,
    bool radio = false,
    bool shuffle = false,
    String? additionalParamsNext,
    bool onlyRelated = false,
  });

  dynamic getLyrics(String browseId);

  Future<List<String>> getSearchSuggestion(String queryStr);

  Future<Map<String, dynamic>> getSearchContinuation(
    Map additionalParamsNext, {
    int limit = 10,
  });

  Future<Map<String, dynamic>> getArtist(String channelId);

  Future<Map<String, dynamic>> getArtistRealtedContent(
    Map<String, dynamic> browseEndpoint,
    String category, {
    String additionalParams = "",
  });

  Future<Map<String, dynamic>> search(
    String query, {
    String? filter,
    String? scope,
    int limit = 30,
    bool ignoreSpelling = false,
    String? filterParams,
  });
}

abstract class DownloaderContract {
  MediaItem? get currentSong;

  Future<void> download(MediaItem? song, {List<MediaItem>? songList});

  Future<void> downloadPlaylist(String playlistId, List<MediaItem> songList);

  void cancelSongDownload(MediaItem song);
}

abstract class UpdateServiceContract {
  Future<UpdateInfo?> checkNewVersion(
    String currentVersion, {
    UpdateChannel channel = UpdateChannel.stable,
  });
}

abstract class AppPlatformContract {
  Future<AppPlatformInfo> getAppInfo();

  Future<void> setKeepScreenAwake(bool enable);

  Future<void> shareText(String text);

  Future<void> openUrl(String url);

  Future<void> installApk(String path);

  Future<void> restartApp({bool terminate = true});
}

class AppPlatformInfo {
  const AppPlatformInfo({
    required this.appName,
    required this.packageName,
    required this.version,
    required this.buildNumber,
  });

  final String appName;
  final String packageName;
  final String version;
  final String buildNumber;
}

abstract class FilePickerContract {
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  });

  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  });
}
