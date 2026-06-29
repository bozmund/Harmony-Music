abstract class LyricsRepository {
  Future<dynamic> getLyrics(String key);
  Future<void> saveLyrics(String key, dynamic lyrics);
}
