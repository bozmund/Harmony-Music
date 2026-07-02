import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/domain/repositories/download_repository.dart';
import 'package:harmonymusic/domain/repositories/playlist_repository.dart';
import 'package:harmonymusic/domain/repositories/settings_repository.dart';
import 'package:harmonymusic/domain/repositories/storage_admin_repository.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/app_contracts.dart';
import 'package:harmonymusic/services/backup/backup_manifest.dart';
import 'package:harmonymusic/services/backup/backup_service.dart';

void main() {
  group('uniqueArchiveName', () {
    test('keeps the plain basename when unused', () {
      expect(uniqueArchiveName('/a/b/song.m4a', <String>{}), 'song.m4a');
    });

    test('renames collisions with a counter', () {
      final used = <String>{};
      expect(uniqueArchiveName('/a/song.m4a', used), 'song.m4a');
      expect(uniqueArchiveName('/b/song.m4a', used), 'song (2).m4a');
      expect(uniqueArchiveName('/c/song.m4a', used), 'song (3).m4a');
    });

    test('treats names case-insensitively for the extraction filesystem', () {
      final used = <String>{};
      expect(uniqueArchiveName('/a/song.m4a', used), 'song.m4a');
      expect(uniqueArchiveName('/b/Song.M4A', used), 'Song (2).M4A');
    });

    test('never hands out the reserved manifest name', () {
      final used = <String>{backupManifestFileName.toLowerCase()};
      expect(
        uniqueArchiveName('/evil/$backupManifestFileName', used),
        'backup_manifest (2).json',
      );
    });
  });

  group('backup service round trip', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('hm_backup_test');
    });

    tearDown(() {
      tempRoot.deleteSync(recursive: true);
    });

    test('scan + createBackup produce a manifest-first streamed archive',
        () async {
      final dbDir = Directory('${tempRoot.path}/db')..createSync();
      final supportDir = Directory('${tempRoot.path}/support')..createSync();
      final musicDir = Directory('${supportDir.path}/Music')
        ..createSync(recursive: true);
      final thumbsDir = Directory('${supportDir.path}/thumbnails')
        ..createSync(recursive: true);
      final externalDir = Directory('${tempRoot.path}/external')..createSync();

      File('${dbDir.path}/box1.hive').writeAsStringSync('hive-data' * 100);
      final audioA = File('${musicDir.path}/song.m4a')
        ..writeAsStringSync('audio-A-content');
      final audioB = File('${externalDir.path}/song.m4a')
        ..writeAsStringSync('audio-B-different-content');
      File('${thumbsDir.path}/thumb.png').writeAsStringSync('png-data');

      final storageAdmin = _FakeStorageAdminRepository(dbDir.path);
      final service = BackupService(
        downloadRepository:
            _FakeDownloadRepository([audioA.path, audioB.path]),
        playlistRepository: _FakePlaylistRepository([
          Playlist(
            title: 'local list',
            playlistId: 'LOCAL_PLAYLIST_1',
            thumbnailUrl: '',
          ),
        ]),
        settingsRepository: _FakeSettingsRepository(),
        storageAdminRepository: storageAdmin,
        supportDirPathProvider: () async => supportDir.path,
        appInfoProvider: () async => const AppPlatformInfo(
          appName: 'HM',
          packageName: 'com.test.harmonymusic',
          version: '9.9.9',
          buildNumber: '7',
        ),
      );

      final entries = await service.scanFilesToBackup(includeAudio: true);

      // Dynamic per-playlist boxes were flushed alongside the static list.
      expect(storageAdmin.flushedStatic, isTrue);
      expect(storageAdmin.flushedBoxes, contains('LOCAL_PLAYLIST_1'));

      final archiveNames = entries.map((e) => e.archiveName).toList();
      expect(archiveNames, contains('box1.hive'));
      expect(archiveNames, contains('song.m4a'));
      expect(archiveNames, contains('song (2).m4a'));
      expect(archiveNames, contains('thumb.png'));

      final zipPath = '${tempRoot.path}/backup.hmb';
      await service.createBackup(entries, zipPath, (_) {});

      final input = InputFileStream(zipPath);
      final archive = ZipDecoder().decodeStream(input);
      try {
        final manifestEntry = archive.find(backupManifestFileName);
        expect(manifestEntry, isNotNull);
        final manifest = BackupManifest.fromJsonString(
          utf8.decode(manifestEntry!.readBytes()!),
        );
        expect(manifest, isNotNull);
        expect(manifest!.packageName, 'com.test.harmonymusic');
        expect(manifest.platform, Platform.operatingSystem);
        expect(manifest.sourceSupportDir, supportDir.path);
        expect(manifest.sourceDbDir, dbDir.path);
        expect(manifest.sourceMusicDir, '${supportDir.path}/Music');
        expect(manifest.includesAudio, isTrue);
        expect(
          manifest.audioEntries['song.m4a'],
          audioA.absolute.path,
        );
        expect(
          manifest.audioEntries['song (2).m4a'],
          audioB.absolute.path,
        );
        expect(manifest.audioEntries.containsKey('thumb.png'), isFalse);

        // Every entry round-trips byte-for-byte (proves the streamed
        // store-mode audio entries and gzip database entries are intact).
        expect(
          utf8.decode(archive.find('song.m4a')!.readBytes()!),
          'audio-A-content',
        );
        expect(
          utf8.decode(archive.find('song (2).m4a')!.readBytes()!),
          'audio-B-different-content',
        );
        expect(
          utf8.decode(archive.find('box1.hive')!.readBytes()!),
          'hive-data' * 100,
        );
        expect(
          utf8.decode(archive.find('thumb.png')!.readBytes()!),
          'png-data',
        );
      } finally {
        await archive.clear();
        await input.close();
      }
    });
  });

  group('backup service source checks', () {
    late String backupServiceSource;

    setUpAll(() {
      backupServiceSource =
          File('lib/services/backup/backup_service.dart').readAsStringSync();
    });

    test('boxes are flushed before the database directory is scanned', () {
      final flushIndex = backupServiceSource.indexOf('flushBackupBoxes()');
      final playlistFlushIndex =
          backupServiceSource.indexOf('flushBox(playlist.playlistId)');
      final scanIndex =
          backupServiceSource.indexOf('processDirectoryInIsolate(dbDir)');
      expect(flushIndex, greaterThan(-1));
      expect(playlistFlushIndex, greaterThan(flushIndex));
      expect(scanIndex, greaterThan(playlistFlushIndex));
    });

    test('manifest is written before any data entry', () {
      final manifestWriteIndex = backupServiceSource
          .indexOf('ArchiveFile.string(backupManifestFileName');
      final entryLoopIndex =
          backupServiceSource.indexOf('for (var i = 0; i < entries.length');
      expect(manifestWriteIndex, greaterThan(-1));
      expect(entryLoopIndex, greaterThan(manifestWriteIndex));
    });

    test('already-compressed files are stored, streamed, uncompressed', () {
      // ZipFileEncoder.store is a deflate *level*, not a compression mode:
      // it buffers each whole entry in memory. Streaming store requires
      // CompressionType.none via addArchiveFile.
      expect(backupServiceSource, contains('CompressionType.none'));
      expect(backupServiceSource, contains('ArchiveFile.stream('));
      expect(
        backupServiceSource.contains('ZipFileEncoder.store'),
        isFalse,
      );
    });
  });
}

class _FakeDownloadRepository implements DownloadRepository {
  _FakeDownloadRepository(this.paths);

  final List<String> paths;

  @override
  Future<List<String>> getDownloadedSongFilePaths() async => paths;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlaylistRepository implements PlaylistRepository {
  _FakePlaylistRepository(this.playlists);

  final List<Playlist> playlists;

  @override
  Future<List<Playlist>> getPlaylists() async => playlists;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsRepository implements SettingsRepository {
  String? downloadLocationPath;

  @override
  String? getDownloadLocationPath() => downloadLocationPath;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStorageAdminRepository implements StorageAdminRepository {
  _FakeStorageAdminRepository(this.dbDirPath);

  final String dbDirPath;
  final List<String> flushedBoxes = [];
  bool flushedStatic = false;

  @override
  Future<void> flushBackupBoxes() async => flushedStatic = true;

  @override
  Future<void> flushBox(String boxName) async => flushedBoxes.add(boxName);

  @override
  Future<String> databaseDirectoryPath() async => dbDirPath;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
