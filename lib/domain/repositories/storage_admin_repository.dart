abstract class StorageAdminRepository {
  List<String> get backupBoxNames;
  Future<void> flushBox(String boxName);
  Future<void> flushBackupBoxes();
  Future<void> clearBoxes(List<String> boxNames);
  Future<void> closeAll();
  Future<String> databaseDirectoryPath();
  Future<void> reopenCoreBoxes();
  Future<void> clearPlaybackAndCacheData();
  Future<void> rewriteDownloadUrls(String Function(String currentPath) rewrite);
  Future<void> rewriteClonePaths({
    required String oldMusicPath,
    required String newMusicPath,
  });
}
