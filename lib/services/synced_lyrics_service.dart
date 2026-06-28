import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/domain/repositories/app_repositories.dart';
import 'package:harmonymusic/utils/helper.dart';

class SyncedLyricsService {
  static Future<Map<String, dynamic>?> getSyncedLyrics(
    MediaItem song,
    int durInSec,
  ) async {
    final lyricsRepository = Get.find<LyricsRepository>();
    // check if lyrics available in local database
    final cachedLyrics = await lyricsRepository.getLyrics(song.id);
    if (cachedLyrics != null) {
      return Map<String, dynamic>.from(cachedLyrics);
    }

    final dur = song.duration?.inSeconds ?? durInSec;
    final url =
        'https://lrclib.net/api/get?artist_name=${song.artist?.replaceAll(" ", "+")}&track_name=${song.title.replaceAll(" ", "+")}&album_name=${song.album?.replaceAll(" ", "+")}&duration=$dur';
    try {
      final response = (await Dio().get(url)).data;
      if (response["syncedLyrics"] != null) {
        printINFO("Synced Available");
        final lyricsData = {
          "synced": response["syncedLyrics"],
          "plainLyrics": response["plainLyrics"],
        };
        await lyricsRepository.saveLyrics(song.id, lyricsData);
        return lyricsData;
      }
    } on DioException catch (e) {
      printERROR(e.response);
    }
    return null;
  }
}
