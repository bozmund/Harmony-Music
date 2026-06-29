import 'dart:io';

import 'package:get/get.dart';
import '../domain/repositories/download_repository.dart';
import '../domain/repositories/library_repository.dart';
import '../domain/repositories/song_cache_repository.dart';
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
      if (shouldDeleteStreamCacheEntry(entry.value)) {
        await songCacheRepository.deleteStreamCacheEntry(songUrlKey);
      }
    }
  } catch (e) {
    printERROR("Error in removeExpiredSongsUrlFromDb: $e");
  } finally {
    await removeDeletedOfflineSongsFromDb();
  }
}

bool shouldDeleteStreamCacheEntry(dynamic cacheValue) {
  if (cacheValue is Map) {
    final audioEntries = [
      cacheValue['lowQualityAudio'],
      cacheValue['highQualityAudio'],
    ];
    final urls = <String>[];
    for (final audio in audioEntries) {
      final url = audio is Map ? audio['url'] : null;
      if (url is! String) return true;
      urls.add(url);
    }
    return urls.every((url) => isExpired(url: url));
  }

  if (cacheValue is List && cacheValue.isNotEmpty) {
    final streamData = cacheValue.length > 1 ? cacheValue[1] : null;
    final url = streamData is Map ? streamData['url'] : null;
    return url is! String || isExpired(url: url);
  }

  return true;
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
