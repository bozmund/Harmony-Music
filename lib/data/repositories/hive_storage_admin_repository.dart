import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/repositories/storage_admin_repository.dart';
import '../../services/constant.dart';
import '../../utils/platform_utils.dart';

class HiveStorageAdminRepository implements StorageAdminRepository {
  @override
  List<String> get backupBoxNames => const [
    BoxNames.songsCache,
    BoxNames.songDownloads,
    BoxNames.songsUrlCache,
    BoxNames.appPrefs,
    BoxNames.homeScreenData,
    BoxNames.prevSessionData,
    BoxNames.libFav,
    BoxNames.libFavNotDownloaded,
    BoxNames.libRP,
    BoxNames.libImportDuplicates,
    BoxNames.libImportReview,
    BoxNames.libraryPlaylists,
    BoxNames.libraryAlbums,
    BoxNames.libraryArtists,
    BoxNames.librarySearches,
    BoxNames.blacklistedPlaylist,
    BoxNames.searchQuery,
    BoxNames.lyrics,
  ];

  @override
  Future<void> flushBox(String boxName) async {
    if (Hive.isBoxOpen(boxName)) await Hive.box(boxName).flush();
  }

  @override
  Future<void> flushBackupBoxes() async {
    for (final boxName in backupBoxNames) {
      await flushBox(boxName);
    }
  }

  @override
  Future<void> clearBoxes(List<String> boxNames) async {
    for (final boxName in boxNames) {
      final box = Hive.isBoxOpen(boxName)
          ? Hive.box(boxName)
          : await Hive.openBox(boxName);
      await box.clear();
    }
  }

  @override
  Future<void> closeAll() => Hive.close();

  @override
  Future<String> databaseDirectoryPath() async {
    if (isDesktopPlatform) {
      return '${(await getApplicationSupportDirectory()).path}/db';
    }
    return (await getApplicationDocumentsDirectory()).path;
  }

  @override
  Future<void> reopenCoreBoxes() async {
    await Hive.openBox(BoxNames.songsCache);
    await Hive.openBox(BoxNames.songDownloads);
    await Hive.openBox(BoxNames.songsUrlCache);
    await Hive.openBox(BoxNames.appPrefs);
  }

  @override
  Future<void> clearPlaybackAndCacheData() async {
    await clearBoxes([
      BoxNames.homeScreenData,
      BoxNames.prevSessionData,
      BoxNames.songsUrlCache,
    ]);
    await Hive.box(BoxNames.appPrefs).delete(PrefKeys.homeScreenDataTime);
  }

  @override
  Future<void> rewriteDownloadUrls(
    String Function(String currentPath) rewrite,
  ) async {
    final box = Hive.isBoxOpen(BoxNames.songDownloads)
        ? Hive.box(BoxNames.songDownloads)
        : await Hive.openBox(BoxNames.songDownloads);
    for (final key in box.keys.toList()) {
      final value = box.get(key);
      if (value is Map && value['url'] is String) {
        final updated = Map<String, dynamic>.from(value);
        updated['url'] = rewrite(value['url'] as String);
        await box.put(key, updated);
      }
    }
  }

  @override
  Future<void> rewriteClonePaths({
    required String oldMusicPath,
    required String newMusicPath,
  }) async {
    final downloadsBox = Hive.isBoxOpen(BoxNames.songDownloads)
        ? Hive.box(BoxNames.songDownloads)
        : await Hive.openBox(BoxNames.songDownloads);
    for (final key in downloadsBox.keys.toList()) {
      final song = downloadsBox.get(key);
      if (song is! Map) continue;

      final updatedSong = Map<dynamic, dynamic>.from(song);
      updatedSong['url'] = _rewriteClonePath(
        updatedSong['url'],
        oldMusicPath,
        newMusicPath,
      );

      final streamInfo = updatedSong['streamInfo'];
      if (streamInfo is List && streamInfo.length > 1 && streamInfo[1] is Map) {
        final streamInfoData = Map<dynamic, dynamic>.from(streamInfo[1]);
        streamInfoData['url'] = _rewriteClonePath(
          streamInfoData['url'],
          oldMusicPath,
          newMusicPath,
        );
        final updatedStreamInfo = List<dynamic>.from(streamInfo);
        updatedStreamInfo[1] = streamInfoData;
        updatedSong['streamInfo'] = updatedStreamInfo;
      }

      await downloadsBox.put(key, updatedSong);
    }

    final appPrefsBox = Hive.isBoxOpen(BoxNames.appPrefs)
        ? Hive.box(BoxNames.appPrefs)
        : await Hive.openBox(BoxNames.appPrefs);
    final downloadPath = appPrefsBox.get(PrefKeys.downloadLocationPath);
    final updatedDownloadPath = _rewriteClonePath(
      downloadPath,
      oldMusicPath,
      newMusicPath,
    );
    if (updatedDownloadPath != downloadPath) {
      await appPrefsBox.put(PrefKeys.downloadLocationPath, updatedDownloadPath);
    }

    await downloadsBox.flush();
    await appPrefsBox.flush();
  }

  dynamic _rewriteClonePath(
    dynamic value,
    String oldMusicPath,
    String newMusicPath,
  ) {
    if (value is! String || value.isEmpty) return value;
    return value.replaceFirst(oldMusicPath, newMusicPath);
  }
}
