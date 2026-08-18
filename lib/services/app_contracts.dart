import 'package:audio_service/audio_service.dart';
import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:file_selector/file_selector.dart';

import '../utils/helper.dart';

abstract class MusicServiceContract {
  set hlCode(String code);

  Future<dynamic> getHome({int limit = 4});

  Future<List<Map<String, dynamic>>> getCharts(
    String category, {
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

  /// One round trip, one song. Returns null when the id has no usable metadata.
  Future<MediaItem?> resolveSongMetadata(String songId);

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

  Future<Map<String, dynamic>> getArtistRelatedContent(
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

  Future<SystemNavigationMode> getSystemNavigationMode();

  Future<void> setKeepScreenAwake(bool enable);

  Future<void> setPlaybackWakeLock(bool enable);

  Future<void> shareText(String text);

  Future<void> openUrl(String url);

  Future<void> installApk(String path);

  Future<void> launchWindowsInstaller(String path);

  Future<void> restartApp({bool terminate = true});
}

enum SystemNavigationMode { gesture, buttons, unknown }

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

/// The auth boundary, extracted purely so a fake can stand in for
/// `Auth0Service` in tests — every other external boundary
/// (`MusicServiceContract`, `AppPlatformContract`, ...) already has one for
/// exactly this reason. `Auth0Service` implements this unchanged; production
/// wiring is untouched.
abstract class AuthServiceContract {
  bool get isConfigured;

  bool get isSupportedPlatform;

  bool get isAvailable;

  /// Restores a previously-authenticated session, or null if none exists (or
  /// none could be restored — an expired token reads the same as never having
  /// signed in from this method's point of view).
  Future<UserProfile?> tryRestoreSession();

  Future<UserProfile> login({bool chooseAccount = false});

  Future<void> logout();

  Future<String?> accessToken({bool forceRefresh = false});

  /// Fires when a restored session stops being usable while the app is running,
  /// so the UI can drop to signed-out immediately rather than at the next
  /// launch. Only a credential the identity provider actually rejected counts —
  /// a failed request is not a revocation, and emitting on one would sign users
  /// out every time the network dropped.
  Stream<void> get onSessionRevoked;
}

abstract class FilePickerContract {
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  });

  /// Picks a single file and returns its filesystem path without ever
  /// loading the file contents into memory. [openFile] (file_selector)
  /// eagerly reads the whole file into a byte array on Android and its size
  /// into a 32-bit int, so it fails on multi-gigabyte files — use this for
  /// large files such as .hmb backups.
  Future<String?> pickLargeFilePath({required List<String> extensions});

  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  });
}
