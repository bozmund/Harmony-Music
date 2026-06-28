import 'dart:io';

import 'package:get/get.dart';
import '../domain/repositories/app_repositories.dart';
import '/ui/screens/Library/library_controller.dart';
import 'package:path_provider/path_provider.dart';
import '../services/utils.dart';
import 'helper.dart';

Future<void> startHouseKeeping() async {
  await removeExpiredSongsUrlFromDb();
}

Future<void> removeExpiredSongsUrlFromDb() async {
  try {
    final songCacheRepository = Get.find<SongCacheRepository>();
    final entries = await songCacheRepository.getAllStreamCacheEntries();
    for (final entry in entries.entries) {
      final songUrlKey = entry.key;
      final cacheValue = entry.value;
      if (cacheValue is! List || cacheValue.isEmpty) continue;
      final streamData = cacheValue.length > 1 ? cacheValue[1] : null;
      if (streamData == null ||
          streamData.runtimeType == String ||
          (streamData != null && isExpired(url: streamData['url'] as String))) {
        await songCacheRepository.deleteStreamCacheEntry(songUrlKey);
      }
    }
  } catch (e) {
    printERROR("Error in removeExpiredSongsUrlFromDb: $e");
  } finally {
    await removeDeletedOfflineSongsFromDb();
  }
}

Future<void> removeDeletedOfflineSongsFromDb() async {
  final supportDir = (await getApplicationSupportDirectory()).path;
  try {
    final downloadRepository = Get.find<DownloadRepository>();
    final downloadedSongs = await Get.find<LibraryRepository>()
        .getDownloadedSongs();
    final LibrarySongsController librarySongsController =
        Get.find<LibrarySongsController>();
    for (final downloadedSong in downloadedSongs) {
      final songKey = downloadedSong.id;
      final songUrl = downloadedSong.extras?['url'];
      if (songUrl is! String) continue;
      if (await File(songUrl).exists() == false) {
        await downloadRepository.deleteDownloadedSong(songKey);
        await librarySongsController.removeSong(downloadedSong, true);
        final thumbNailPath = "$supportDir/thumbnails/$songKey.png";
        if (await File(thumbNailPath).exists()) {
          await File(thumbNailPath).delete();
        }
      }
    }
  } catch (e) {
    printERROR("Error in removeDeletedOfflineSongsFromDb: $e");
  }
}
