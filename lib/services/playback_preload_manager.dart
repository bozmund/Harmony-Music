import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';

import '../domain/repositories/song_cache_repository.dart';
import '../utils/platform_utils.dart';
import '/models/hm_streaming_data.dart';
import '/services/constant.dart';
import '/services/crash_diagnostics_service.dart';
import '/services/stream_service.dart';
import '/utils/helper.dart';

typedef StreamInfoResolver =
    Future<HMStreamingData> Function(
      String songId, {
      bool generateNewUrl,
      bool offlineReplacementUrl,
    });

bool isPreloadableNetworkUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return false;

  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}

class PreloadedAudioPrefix {
  const PreloadedAudioPrefix({
    required this.songId,
    required this.url,
    required this.prefixFile,
    required this.contentType,
    required this.streamInfo,
    required this.targetBytes,
  });

  final String songId;
  final String url;
  final File prefixFile;
  final String contentType;
  final HMStreamingData streamInfo;
  final int targetBytes;

  Future<bool> get isReady async =>
      await prefixFile.exists() && await prefixFile.length() > 0;
}

class PlaybackPreloadManager {
  PlaybackPreloadManager({
    required Directory preloadDirectory,
    required StreamInfoResolver resolveStreamInfo,
    SongCacheRepository? songCacheRepository,
  }) : _preloadDirectory = preloadDirectory,
       _resolveStreamInfo = resolveStreamInfo,
       _songCacheRepository = songCacheRepository ?? _NoopSongCacheRepository();

  final Directory _preloadDirectory;
  final StreamInfoResolver _resolveStreamInfo;
  final SongCacheRepository _songCacheRepository;
  final Map<String, PreloadedAudioPrefix> _entries = {};
  final Set<String> _queuedIds = {};
  final List<MediaItem> _queue = [];
  Future<void>? _activeTask;
  int _generation = 0;
  int _queueGeneration = 0;
  String? _lastWindowKey;

  Future<void> init() async {
    await _preloadDirectory.create(recursive: true);
  }

  HMStreamingData? streamInfoFor(String songId) => _entries[songId]?.streamInfo;

  PreloadedAudioPrefix? prefixForSync(String songId) {
    final entry = _entries[songId];
    if (entry == null ||
        !entry.prefixFile.existsSync() ||
        entry.prefixFile.lengthSync() <= 0) {
      return null;
    }
    return entry;
  }

  Future<PreloadedAudioPrefix?> prefixFor(String songId) async {
    final entry = _entries[songId];
    if (entry == null || !await entry.isReady) return null;
    return entry;
  }

  Future<void> update({
    required List<MediaItem> queue,
    required List<int> candidateIndices,
    required int range,
    required bool isPlaying,
    required int? currentIndex,
  }) async {
    if (!isAndroidPlatform || range <= 0 || !isPlaying) {
      await clear();
      return;
    }

    final candidateIds = candidateIndices
        .where((index) => index >= 0 && index < queue.length)
        .map((index) => queue[index].id)
        .toList();
    final windowKey =
        '$range|$isPlaying|$currentIndex|${candidateIds.join(',')}';
    if (windowKey == _lastWindowKey) return;
    _lastWindowKey = windowKey;

    final generation = ++_generation;
    _queueGeneration = generation;
    final validIds = candidateIds.toSet();
    await _disposeOutside(validIds);

    _queue.clear();
    _queuedIds.clear();
    for (final index in candidateIndices) {
      if (index < 0 || index >= queue.length) continue;
      if (index == currentIndex) continue;
      final song = queue[index];
      final existing = _entries[song.id];
      if (existing != null && await existing.isReady) continue;
      if (_queuedIds.add(song.id)) {
        _queue.add(song);
      }
    }
    _pumpQueue();
  }

  Future<void> clear() async {
    _generation++;
    _queueGeneration = _generation;
    _lastWindowKey = null;
    _entries.clear();
    _queuedIds.clear();
    _queue.clear();
    if (!await _preloadDirectory.exists()) return;
    await for (final entity in _preloadDirectory.list()) {
      if (entity is File) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  void _pumpQueue() {
    if (_activeTask != null || _queueGeneration != _generation) return;
    while (_queue.isNotEmpty) {
      final song = _queue.removeAt(0);
      _queuedIds.remove(song.id);
      final existing = _entries[song.id];
      if (existing != null &&
          existing.prefixFile.existsSync() &&
          existing.prefixFile.lengthSync() > 0) {
        continue;
      }

      final task = _preload(song, _queueGeneration);
      _activeTask = task;
      unawaited(
        task.whenComplete(() {
          if (identical(_activeTask, task)) {
            _activeTask = null;
          }
          _pumpQueue();
        }),
      );
      return;
    }
  }

  Future<void> _preload(MediaItem song, int generation) async {
    try {
      final streamInfo = await _resolveStreamInfo(song.id);
      if (generation != _generation || !streamInfo.playable) return;
      final audio = streamInfo.audio;
      if (audio == null || audio.url.isEmpty) return;
      if (!isPreloadableNetworkUrl(audio.url)) {
        printINFO(
          "Skipping preload for non-network source ${song.id}",
          tag: LogTags.preload,
        );
        return;
      }

      await _songCacheRepository.saveStreamCacheEntry(
        song.id,
        streamInfo.toJson(),
      );

      final prefixFile = _prefixFile(song.id);
      final targetBytes = _targetPrefixBytes(audio.bitrate);
      final contentType = await _fetchPrefix(
        uri: Uri.parse(audio.url),
        prefixFile: prefixFile,
        targetBytes: targetBytes,
        fallbackContentType: _fallbackContentType(audio),
      );
      if (generation != _generation) {
        await _deleteFile(prefixFile);
        return;
      }

      _entries[song.id] = PreloadedAudioPrefix(
        songId: song.id,
        url: audio.url,
        prefixFile: prefixFile,
        contentType: contentType,
        streamInfo: streamInfo,
        targetBytes: targetBytes,
      );
      printINFO(
        "Preloaded ${song.id} (${await prefixFile.length()} bytes)",
        tag: LogTags.preload,
      );
      CrashDiagnosticsService.instance.record(
        'preload',
        'ready song=${song.id} bytes=${await prefixFile.length()} entries=${_entries.length}',
        includeMemory: true,
      );
    } catch (error, stackTrace) {
      printERROR("Failed to preload ${song.id}: $error", tag: LogTags.preload);
      printERROR(stackTrace, tag: LogTags.preload);
      CrashDiagnosticsService.instance.record(
        'preload',
        'failed song=${song.id}',
        error: error,
        stackTrace: stackTrace,
        includeMemory: true,
        flush: true,
      );
    }
  }

  Future<void> _disposeOutside(Set<String> validIds) async {
    final staleIds = _entries.keys
        .where((songId) => !validIds.contains(songId))
        .toList();
    for (final songId in staleIds) {
      final entry = _entries.remove(songId);
      if (entry != null) {
        await _deleteFile(entry.prefixFile);
      }
    }

    if (!await _preloadDirectory.exists()) return;
    await for (final entity in _preloadDirectory.list()) {
      if (entity is! File) continue;
      final songId = _songIdFromFile(entity);
      if (songId == null || validIds.contains(songId)) continue;
      await _deleteFile(entity);
    }
  }

  Future<String> _fetchPrefix({
    required Uri uri,
    required File prefixFile,
    required int targetBytes,
    required String fallbackContentType,
  }) async {
    if (await prefixFile.exists() && await prefixFile.length() >= targetBytes) {
      return fallbackContentType;
    }

    final tempFile = File("${prefixFile.path}.tmp");
    await tempFile.parent.create(recursive: true);
    await _deleteFile(tempFile);

    final client = HttpClient();
    IOSink? sink;
    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.rangeHeader,
        "bytes=0-${targetBytes - 1}",
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw HttpException(
          "Unexpected preload status ${response.statusCode}",
          uri: uri,
        );
      }

      final contentType =
          response.headers.contentType?.mimeType ?? fallbackContentType;
      sink = tempFile.openWrite();
      var written = 0;
      await for (final chunk in response) {
        final remaining = targetBytes - written;
        if (remaining <= 0) break;
        final bytesToWrite = chunk.length > remaining
            ? chunk.sublist(0, remaining)
            : chunk;
        sink.add(bytesToWrite);
        written += bytesToWrite.length;
        if (written >= targetBytes) break;
      }
      await sink.close();
      sink = null;
      await _deleteFile(prefixFile);
      await tempFile.rename(prefixFile.path);
      return contentType;
    } finally {
      client.close(force: true);
      await sink?.close();
      await _deleteFile(tempFile);
    }
  }

  int _targetPrefixBytes(int bitrate) {
    final effectiveBitrate = bitrate <= 0 ? 160000 : bitrate;
    final fiveSeconds = (effectiveBitrate / 8 * 5).round();
    final target = fiveSeconds + 64 * 1024;
    return target.clamp(128 * 1024, 1024 * 1024).toInt();
  }

  String _fallbackContentType(Audio audio) {
    return audio.audioCodec == Codec.mp4a ? "audio/mp4" : "audio/webm";
  }

  File _prefixFile(String songId) {
    return File("${_preloadDirectory.path}/${_safeSongId(songId)}.prefix");
  }

  String _safeSongId(String songId) {
    return songId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  }

  String? _songIdFromFile(File file) {
    final name = file.uri.pathSegments.isEmpty
        ? ""
        : file.uri.pathSegments.last;
    if (!name.endsWith(".prefix")) return null;
    return name.substring(0, name.length - ".prefix".length);
  }

  Future<void> _deleteFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}

class _NoopSongCacheRepository implements SongCacheRepository {
  @override
  Future<void> clearStreamCache() async {}

  @override
  Future<bool> containsCachedSong(String songId) async => false;

  @override
  Future<void> deleteCachedSong(String songId) async {}

  @override
  Future<void> deleteStreamCacheEntry(String songId) async {}

  @override
  Future<Map<String, dynamic>> getAllStreamCacheEntries() async => {};

  @override
  Future<MediaItem?> getCachedSong(String songId) async => null;

  @override
  Future<dynamic> getCachedSongJson(String songId) async => null;

  @override
  Future<dynamic> getStreamCacheEntry(String songId) async => null;

  @override
  Future<HMStreamingData?> getStreamInfo(
    String songId,
    int qualityIndex,
  ) async => null;

  @override
  Future<void> saveCachedSong(MediaItem song) async {}

  @override
  Future<void> saveCachedSongJson(
    String songId,
    Map<String, dynamic> json,
  ) async {}

  @override
  Future<void> saveStreamCacheEntry(String songId, dynamic value) async {}
}
