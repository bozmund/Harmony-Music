import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:harmonymusic/l10n/l10n.dart';
import 'package:path_provider/path_provider.dart';

import '../app/navigation/app_navigator.dart';
import '../domain/repositories/download_repository.dart';
import '../domain/repositories/download_retry_repository.dart';
import '../domain/repositories/settings_repository.dart';
import 'resolver/resolver_client.dart';
import 'resolver/resolver_configuration.dart';
import '../utils/runtime_platform.dart';
import '../utils/observable_state.dart';
import '/services/constant.dart';
import '/services/crash_diagnostics_service.dart';
import '/services/app_contracts.dart';
import '../ui/screens/Album/album_screen_controller.dart';
import '../ui/screens/Playlist/playlist_screen_controller.dart';
import '/services/stream_service.dart';
import '../ui/widgets/snackbar.dart';
import '/services/permission_service.dart';
import '/utils/helper.dart';
import '/models/media_Item_builder.dart';
import '../ui/screens/Library/library_controller.dart';
//import '../models/thumbnail.dart' as th;

class Downloader extends ChangeNotifier implements DownloaderContract {
  Downloader(
    this._downloadRepository,
    this._settingsRepository,
    this._resolverClient,
    this._retryRepository,
  ) : failedDownloadCount = ObservableValue(_retryRepository.count);

  final DownloadRepository _downloadRepository;
  final SettingsRepository _settingsRepository;
  final ResolverClient _resolverClient;
  final DownloadRetryRepository _retryRepository;

  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 3),
      sendTimeout: const Duration(seconds: 20),
    ),
  );
  @override
  MediaItem? currentSong;
  ObservableMap<String, List<MediaItem>> playlistQueue = ObservableMap();
  final currentPlaylistId = ObservableValue("");
  final songDownloadingProgress = ObservableValue(0);
  final playlistDownloadingProgress = ObservableValue(0);
  final isJobRunning = ObservableValue(false);
  final currentDownloadPhase = ObservableValue("");
  final currentDownloadDebugMessage = ObservableValue("");
  final lastDownloadError = ObservableValue("");
  final ObservableValue<int> failedDownloadCount;
  CancelToken? _activeCancelToken;

  static const _streamFetchTimeout = Duration(seconds: 45);
  static const _audioDownloadTimeout = Duration(minutes: 5);
  static const _thumbnailDownloadTimeout = Duration(seconds: 20);
  static const _audioDownloadMaxAttempts = 3;
  static const _playlistDownloadDelay = Duration(seconds: 1);
  static const _resolverPrefetchTimeout = Duration(seconds: 5);

  ObservableList<MediaItem> songQueue = ObservableList();

  void _notifyDownloaderChanged() {
    notifyListeners();
  }

  Future<bool> checkPermissionNDir() async {
    final supportDownloadDir = await _supportDownloadDirPath();
    final dirPath = await _downloadLocationPath();
    if (dirPath != supportDownloadDir &&
        !await PermissionService.getExtStoragePermission()) {
      return false;
    }

    final directory = Directory(dirPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return true;
  }

  @override
  Future<void> downloadPlaylist(
    String playlistId,
    List<MediaItem> songList,
  ) async {
    if (!(await checkPermissionNDir())) return;

    // for toggle between downloading request & cancelling
    if (playlistQueue.containsKey(playlistId)) {
      songQueue.removeWhere((element) => songList.contains(element));
      playlistQueue.remove(playlistId);
      _notifyDownloaderChanged();
      if (currentSong != null && songList.contains(currentSong)) {
        _cancelActiveDownload("Playlist download cancelled");
      }
      return;
    }

    playlistQueue[playlistId] = songList;
    songQueue.addAll(songList);
    _notifyDownloaderChanged();

    if (!isJobRunning.value) {
      await triggerDownloadingJob();
    }
  }

  @override
  Future<void> download(MediaItem? song, {List<MediaItem>? songList}) async {
    if (!(await checkPermissionNDir())) return;
    if (songList != null) {
      songQueue.addAll(songList);
    } else if (songQueue.contains(song)) {
      cancelSongDownload(song!);
      return;
    } else {
      songQueue.add(song!);
    }
    _notifyDownloaderChanged();
    if (!isJobRunning.value) {
      await triggerDownloadingJob();
    }
  }

  Future<void> triggerDownloadingJob() async {
    if (isJobRunning.value) return;

    isJobRunning.value = true;
    _notifyDownloaderChanged();
    try {
      while (playlistQueue.isNotEmpty || songQueue.isNotEmpty) {
        //check if playlist download in queue => download playlist/songs else download from general songs queue
        if (playlistQueue.isNotEmpty) {
          for (String playlistId in playlistQueue.keys.toList()) {
            //checked in case download cancel request
            if (playlistQueue.containsKey(playlistId)) {
              currentPlaylistId.value = playlistId;
              _notifyDownloaderChanged();
              await downloadSongList(
                (playlistQueue[playlistId]!).toList(),
                isPlaylist: true,
              );
              final playlistController =
                  PlaylistScreenControllerRegistry.maybeOf(
                    Key(playlistId).hashCode.toString(),
                  );
              if (playlistController != null &&
                  playlistQueue.containsKey(playlistId)) {
                playlistController.isDownloaded.value = true;
              }
              // in case of album
              else {
                final albumController = AlbumScreenControllerRegistry.maybeOf(
                  Key(playlistId).hashCode.toString(),
                );
                if (albumController != null &&
                    playlistQueue.containsKey(playlistId)) {
                  albumController.isDownloaded.value = true;
                }
              }
              playlistQueue.remove(playlistId);
            }
            currentPlaylistId.value = "";
            playlistDownloadingProgress.value = 0;
            _notifyDownloaderChanged();
          }
        } else {
          await downloadSongList(songQueue.toList());
        }
      }
    } catch (e, stackTrace) {
      _setFailed("Download job failed", e, stackTrace);
    } finally {
      isJobRunning.value = false;
      currentSong = null;
      currentPlaylistId.value = "";
      playlistDownloadingProgress.value = 0;
      songDownloadingProgress.value = 0;
      currentDownloadPhase.value = "";
      currentDownloadDebugMessage.value = "";
      _activeCancelToken = null;
      _notifyDownloaderChanged();
    }
  }

  Future<void> downloadSongList(
    List<MediaItem> jobSongList, {
    bool isPlaylist = false,
  }) async {
    for (MediaItem song in jobSongList) {
      // interrupt downloading task in case of playlist download cancel request
      if (isPlaylist && !playlistQueue.containsKey(currentPlaylistId.value)) {
        currentPlaylistId.value = "";
        playlistDownloadingProgress.value = 0;
        _notifyDownloaderChanged();
        return;
      }

      if (!await _downloadRepository.containsDownload(song.id)) {
        currentSong = song;
        songDownloadingProgress.value = 0;
        _notifyDownloaderChanged();
        try {
          await writeFileStream(song);
        } on DioException catch (e, stackTrace) {
          if (CancelToken.isCancel(e)) {
            _setFailed("Download cancelled", e, stackTrace, showSnack: false);
          } else {
            _setFailed("Network/stream error", e, stackTrace);
          }
        } on TimeoutException catch (e, stackTrace) {
          _setFailed("Download timed out", e, stackTrace);
        } catch (e, stackTrace) {
          _setFailed("Download failed", e, stackTrace);
        } finally {
          _activeCancelToken = null;
        }
      }
      songQueue.remove(song);
      _notifyDownloaderChanged();
      //for playlist downloading counter update
      if (isPlaylist) {
        playlistDownloadingProgress.value = jobSongList.indexOf(song) + 1;
        _notifyDownloaderChanged();
      }
      if (isPlaylist &&
          playlistQueue.containsKey(currentPlaylistId.value) &&
          jobSongList.last != song) {
        await Future.delayed(_playlistDownloadDelay);
      }
    }
  }

  /// Requeues every persisted local-download failure. Entries remain in the
  /// retry list until the song completes successfully, so an interrupted retry
  /// never loses work.
  Future<void> retryFailedDownloads() async {
    if (!(await checkPermissionNDir())) return;
    final failedSongs = _retryRepository.getAll();
    for (final song in failedSongs) {
      if (!songQueue.contains(song) &&
          !await _downloadRepository.containsDownload(song.id)) {
        songQueue.add(song);
      }
    }
    _notifyDownloaderChanged();
    if (!isJobRunning.value && songQueue.isNotEmpty) {
      await triggerDownloadingJob();
    }
  }

  Future<void> writeFileStream(MediaItem song) async {
    final traceId = "${song.id}-${DateTime.now().millisecondsSinceEpoch}";
    final stopwatch = Stopwatch()..start();
    final downloadingFormat = _settingsRepository.getDownloadingFormat();

    await _requestResolverPrefetch(song, traceId);
    _setPhase("resolvingStream", "Resolving stream", song, traceId);
    final playerResponse = await StreamProvider.fetch(
      song.id,
    ).timeout(_streamFetchTimeout);

    if (!playerResponse.playable) {
      currentDownloadPhase.value = "failed";
      currentDownloadDebugMessage.value = "Stream not playable";
      lastDownloadError.value = "${song.title}: ${playerResponse.statusMSG}";
      _notifyDownloaderChanged();
      _showDownloadError(
        song,
        playerResponse.statusMSG,
        localizeNetworkError: playerResponse.statusMSG == "networkError",
      );
      printINFO(
        "[$traceId] Requested song ${song.title} is not downloadable: ${playerResponse.statusMSG}",
        tag: LogTags.downloader,
      );
      await _rememberFailedDownload(song);
      return;
    }

    final requiredAudioStream = _selectAudioStream(
      playerResponse,
      downloadingFormat,
    );
    if (requiredAudioStream == null) {
      throw StateError(
        "No audio streams available for ${song.title} (${song.id})",
      );
    }

    final dirPath = await _downloadLocationPath();
    final actualDownFormat = requiredAudioStream.audioCodec.name.contains("mp")
        ? "m4a"
        : "opus";
    final RegExp invalidChar = RegExp(r'[/\\"<>*?:!\[\]¡|%#]');
    final songTitle = "${song.title.trim()} (${song.artist?.trim()})"
        .replaceAll(invalidChar, "");
    String filePath = "$dirPath/$songTitle.$actualDownFormat";
    printINFO(
      "[$traceId] Downloading ${song.title} as $actualDownFormat to $filePath",
      tag: LogTags.downloader,
    );
    _setPhase("downloadingAudio", "Downloading audio", song, traceId);
    await _downloadAudioWithRetries(
      song: song,
      traceId: traceId,
      stream: requiredAudioStream,
      filePath: filePath,
    );

    // Save Thumbnail
    try {
      _setPhase("savingThumbnail", "Saving thumbnail", song, traceId);
      final thumbnailPath =
          "${(await getApplicationSupportDirectory()).path}/thumbnails/${song.id}.png";
      await _dio
          .downloadUri(song.artUri!, thumbnailPath)
          .timeout(_thumbnailDownloadTimeout);
    } catch (e) {
      printWarning(
        "[$traceId] Thumbnail download failed: $e",
        tag: LogTags.downloader,
      );
    }

    _setPhase("savingLibraryEntry", "Saving library entry", song, traceId);
    final songJson = MediaItemBuilder.toJson(song);
    songJson['date'] ??= DateTime.now().millisecondsSinceEpoch;
    songJson['url'] = filePath;
    songJson['extras'] = Map<String, dynamic>.from(songJson['extras'] ?? {})
      ..['url'] = filePath;
    final streamInfoJson = Map<String, dynamic>.from(
      requiredAudioStream.toJson(),
    );
    streamInfoJson['url'] = filePath;
    // [playability status, info map]
    songJson["streamInfo"] = [true, streamInfoJson];
    final downloadedSong = MediaItemBuilder.fromJson(songJson);

    await _downloadRepository.saveDownloadedSongJson(song.id, songJson);
    await _removeFailedDownload(song.id);
    printINFO(
      "[$traceId] Saved download metadata for ${song.id}; streamInfo=${songJson["streamInfo"] != null}",
      tag: LogTags.downloader,
    );
    LibrarySongsControllerRegistry.current?.addSongToLibraryList(
      downloadedSong,
    );
    try {
      await PlaylistScreenControllerRegistry.maybeOf(
        const Key(BoxNames.libFavNotDownloaded).hashCode.toString(),
      )?.addNRemoveItemsInList(song, action: 'remove');
      // ignore: empty_catches
    } catch (e) {}

    _setPhase("completed", "Downloaded", song, traceId);
    printINFO(
      "[$traceId] Downloaded ${song.title} successfully in ${stopwatch.elapsed}",
      tag: LogTags.downloader,
    );
  }

  Future<String> _supportDownloadDirPath() async =>
      "${(await getApplicationSupportDirectory()).path}/Music";

  Future<String> _downloadLocationPath() async =>
      _settingsRepository.getDownloadLocationPath() ??
      await _supportDownloadDirPath();

  @override
  void cancelSongDownload(MediaItem song) {
    songQueue.remove(song);
    for (final playlistId in playlistQueue.keys.toList()) {
      playlistQueue[playlistId]?.remove(song);
      if (playlistQueue[playlistId]?.isEmpty ?? false) {
        playlistQueue.remove(playlistId);
      }
    }
    _notifyDownloaderChanged();
    if (currentSong == song) {
      _cancelActiveDownload("Song download cancelled");
    }
  }

  void _cancelActiveDownload(String reason) {
    if (_activeCancelToken?.isCancelled == false) {
      _activeCancelToken?.cancel(reason);
    }
    currentDownloadPhase.value = "cancelled";
    currentDownloadDebugMessage.value = reason;
    _notifyDownloaderChanged();
    printINFO(reason, tag: LogTags.downloader);
  }

  Audio? _selectAudioStream(
    StreamProvider playerResponse,
    String downloadingFormat,
  ) {
    final audioFormats = playerResponse.audioFormats;
    if (audioFormats == null || audioFormats.isEmpty) return null;

    final preferredCodec = downloadingFormat == "opus"
        ? Codec.opus
        : Codec.mp4a;
    final preferredStreams = audioFormats.where(
      (audio) => audio.audioCodec == preferredCodec,
    );

    return _highestBitrate(preferredStreams) ?? _highestBitrate(audioFormats);
  }

  Audio? _highestBitrate(Iterable<Audio> streams) {
    Audio? selected;
    for (final stream in streams) {
      if (selected == null || stream.bitrate > selected.bitrate) {
        selected = stream;
      }
    }
    return selected;
  }

  Future<void> _downloadAudioWithRetries({
    required MediaItem song,
    required String traceId,
    required Audio stream,
    required String filePath,
  }) async {
    DioException? lastDioError;

    for (var attempt = 1; attempt <= _audioDownloadMaxAttempts; attempt++) {
      if (currentDownloadPhase.value == "cancelled") {
        throw DioException(
          requestOptions: RequestOptions(path: stream.url),
          type: DioExceptionType.cancel,
          error: "Download cancelled",
        );
      }
      _activeCancelToken = CancelToken();
      songDownloadingProgress.value = 0;
      final attemptLabel = "attempt $attempt/$_audioDownloadMaxAttempts";
      currentDownloadDebugMessage.value = "Downloading audio ($attemptLabel)";
      _notifyDownloaderChanged();
      printINFO(
        "[$traceId] Audio download $attemptLabel",
        tag: LogTags.downloader,
      );

      try {
        await _deletePartialFile(filePath);
        await _dio.download(
          stream.url,
          filePath,
          cancelToken: _activeCancelToken,
          options: Options(receiveTimeout: _audioDownloadTimeout),
          onReceiveProgress: (count, total) {
            if (total <= 0) return;
            songDownloadingProgress.value = ((count / total) * 100).toInt();
            currentDownloadDebugMessage.value =
                "Downloading audio ${songDownloadingProgress.value}%";
            _notifyDownloaderChanged();
          },
        );
        return;
      } on DioException catch (e) {
        lastDioError = e;
        if (CancelToken.isCancel(e) ||
            attempt == _audioDownloadMaxAttempts ||
            !_isRetryableAudioDownloadError(e)) {
          rethrow;
        }

        final delay = Duration(seconds: attempt * 2);
        currentDownloadDebugMessage.value =
            "Retrying audio download in ${delay.inSeconds}s";
        _notifyDownloaderChanged();
        printWarning(
          "[$traceId] Audio download failed on $attemptLabel, retrying in ${delay.inSeconds}s: ${_dioErrorSummary(e)}",
          tag: LogTags.downloader,
        );
        await _deletePartialFile(filePath);
        await Future.delayed(delay);
      }
    }

    if (lastDioError != null) {
      throw lastDioError;
    }
  }

  Future<void> _requestResolverPrefetch(MediaItem song, String traceId) async {
    final configuration = ResolverConfiguration.load(_settingsRepository);
    final baseUrl = configuration.baseUrl;
    if (!configuration.enabled || baseUrl == null) return;

    _setPhase("requestingResolver", "Requesting Resolver", song, traceId);
    try {
      await _resolverClient
          .prefetch(baseUrl, [song.id])
          .timeout(_resolverPrefetchTimeout);
      printINFO(
        "[$traceId] Requested Resolver prefetch for ${song.id}",
        tag: LogTags.downloader,
      );
    } catch (error) {
      // Resolver preparation improves later playback but never blocks the
      // established local downloader.
      printWarning(
        "[$traceId] Resolver prefetch unavailable; continuing local download: $error",
        tag: LogTags.downloader,
      );
    }
  }

  Future<void> _rememberFailedDownload(MediaItem song) async {
    await _retryRepository.remember(song);
    failedDownloadCount.value = _retryRepository.count;
    _notifyDownloaderChanged();
  }

  Future<void> _removeFailedDownload(String songId) async {
    await _retryRepository.remove(songId);
    failedDownloadCount.value = _retryRepository.count;
    _notifyDownloaderChanged();
  }

  bool _isRetryableAudioDownloadError(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.unknown) {
      return true;
    }

    final statusCode = error.response?.statusCode;
    return statusCode == 408 ||
        statusCode == 425 ||
        statusCode == 429 ||
        (statusCode != null && statusCode >= 500);
  }

  String _dioErrorSummary(DioException error) {
    final statusCode = error.response?.statusCode;
    final statusText = statusCode == null ? "" : " status=$statusCode";
    return "${error.type}$statusText ${error.error ?? error.message}";
  }

  Future<void> _deletePartialFile(String filePath) async {
    final partialFile = File(filePath);
    if (await partialFile.exists()) {
      await partialFile.delete();
    }
  }

  void _setPhase(
    String phase,
    String debugMessage,
    MediaItem song,
    String traceId,
  ) {
    if (phase == "resolvingStream") {
      lastDownloadError.value = "";
    }
    currentDownloadPhase.value = phase;
    currentDownloadDebugMessage.value = debugMessage;
    _notifyDownloaderChanged();
    printINFO(
      "[$traceId] $debugMessage: ${song.title} (${song.id})",
      tag: LogTags.downloader,
    );
    CrashDiagnosticsService.instance.record(
      'download',
      'phase=$phase trace=$traceId song=${song.id} title=${song.title}',
      includeMemory: true,
      flush: phase == 'savingLibraryEntry' || phase == 'completed',
    );
  }

  void _setFailed(
    String message,
    Object error,
    StackTrace stackTrace, {
    bool showSnack = true,
  }) {
    final song = currentSong;
    currentDownloadPhase.value = "failed";
    lastDownloadError.value = "$message: $error";
    currentDownloadDebugMessage.value = message;
    _notifyDownloaderChanged();
    printERROR(
      "$message${song == null ? "" : " for ${song.title}"}: $error",
      tag: LogTags.downloader,
    );
    printERROR(stackTrace, tag: LogTags.downloader);
    CrashDiagnosticsService.instance.record(
      'download',
      '$message${song == null ? "" : " song=${song.id}"}',
      error: error,
      stackTrace: stackTrace,
      includeMemory: true,
      flush: true,
    );
    if (song != null && message != "Download cancelled") {
      unawaited(_rememberFailedDownload(song));
    }
    if (showSnack && song != null) {
      _showDownloadError(song, '', localizeGeneralError: true);
    }
  }

  void _showDownloadError(
    MediaItem song,
    String message, {
    bool localizeNetworkError = false,
    bool localizeGeneralError = false,
  }) {
    final context = AppNavigator.context;
    if (context == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      snackbar(
        context,
        "${song.title}: ${localizeNetworkError
            ? context.l10n.networkError
            : localizeGeneralError
            ? context.l10n.downloadError3
            : message}",
        size: SanckBarSize.BIG,
        duration: const Duration(seconds: 2),
        top: !RuntimePlatform.isDesktop,
      ),
    );
  }
}
