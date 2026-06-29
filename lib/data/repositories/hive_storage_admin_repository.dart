import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/repositories/storage_admin_repository.dart';
import '../../services/constant.dart';

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
    BoxNames.libRP,
    BoxNames.libraryPlaylists,
    BoxNames.libraryAlbums,
    BoxNames.libraryArtists,
    BoxNames.librarySearches,
  ];

  @override
  Future<void> flushBox(String boxName) async {
    if (Hive.isBoxOpen(boxName)) await Hive.box(boxName).flush();
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
    if (GetPlatform.isDesktop) {
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
}
