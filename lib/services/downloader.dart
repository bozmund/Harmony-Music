import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/services/constant.dart';
import '/services/app_contracts.dart';
import '../ui/screens/Album/album_screen_controller.dart';
import '../ui/screens/Playlist/playlist_screen_controller.dart';
import '/services/stream_service.dart';
import '../ui/widgets/snackbar.dart';
import '/services/permission_service.dart';
import '../ui/screens/Settings/settings_screen_controller.dart';
import '/utils/helper.dart';
import '/models/media_Item_builder.dart';
import '../ui/screens/Library/library_controller.dart';
//import '../models/thumbnail.dart' as th;

class Downloader extends GetxService implements DownloaderContract {
  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 3),
      sendTimeout: const Duration(seconds: 20),
    ),
  );
  @override
  MediaItem? currentSong;
  RxMap<String, List<MediaItem>> playlistQueue =
      <String, List<MediaItem>>{}.obs;
  final currentPlaylistId = "".obs;
  final songDownloadingProgress = 0.obs;
  final playlistDownloadingProgress = 0.obs;
  final isJobRunning = false.obs;
  final currentDownloadPhase = "".obs;
  final currentDownloadDebugMessage = "".obs;
  final lastDownloadError = "".obs;
  CancelToken? _activeCancelToken;

  static const _streamFetchTimeout = Duration(seconds: 45);
  static const _audioDownloadTimeout = Duration(minutes: 5);
  static const _thumbnailDownloadTimeout = Duration(seconds: 20);
  static const _audioDownloadMaxAttempts = 3;
  static const _playlistDownloadDelay = Duration(seconds: 1);

  RxList<MediaItem> songQueue = <MediaItem>[].obs;

  Future<bool> checkPermissionNDir() async {
    final settingsScreenController = Get.find<SettingsScreenController>();

    if (!settingsScreenController.isCurrentPathsupportDownDir &&
        !await PermissionService.getExtStoragePermission()) {
      return false;
    }

    final dirPath =
        Get.find<SettingsScreenController>().downloadLocationPath.string;
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
      if (currentSong != null && songList.contains(currentSong)) {
        _cancelActiveDownload("Playlist download cancelled");
      }
      return;
    }

    playlistQueue[playlistId] = songList;
    songQueue.addAll(songList);

    if (isJobRunning.isFalse) {
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
    if (isJobRunning.isFalse) {
      await triggerDownloadingJob();
    }
  }

  Future<void> triggerDownloadingJob() async {
    if (isJobRunning.isTrue) return;

    isJobRunning.value = true;
    try {
      while (playlistQueue.isNotEmpty || songQueue.isNotEmpty) {
        //check if playlist download in queue => download playlist/songs else download from general songs queue
        if (playlistQueue.isNotEmpty) {
          for (String playlistId in playlistQueue.keys.toList()) {
            //checked in case download cancel request
            if (playlistQueue.containsKey(playlistId)) {
              currentPlaylistId.value = playlistId;
              await downloadSongList(
                (playlistQueue[playlistId]!).toList(),
                isPlaylist: true,
              );
              if (Get.isRegistered<PlaylistScreenController>(
                    tag: Key(playlistId).hashCode.toString(),
                  ) &&
                  playlistQueue.containsKey(playlistId)) {
                Get.find<PlaylistScreenController>(
                  tag: Key(playlistId).hashCode.toString(),
                ).isDownloaded.value = true;
              }
              // in case of album
              else if (Get.isRegistered<AlbumScreenController>(
                    tag: Key(playlistId).hashCode.toString(),
                  ) &&
                  playlistQueue.containsKey(playlistId)) {
                Get.find<AlbumScreenController>(
                  tag: Key(playlistId).hashCode.toString(),
                ).isDownloaded.value = true;
              }
              playlistQueue.remove(playlistId);
            }
            currentPlaylistId.value = "";
            playlistDownloadingProgress.value = 0;
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
        return;
      }

      if (!Hive.box(BoxNames.songDownloads).containsKey(song.id)) {
        currentSong = song;
        songDownloadingProgress.value = 0;
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
      //for playlist downloading counter update
      if (isPlaylist) {
        playlistDownloadingProgress.value = jobSongList.indexOf(song) + 1;
      }
      if (isPlaylist &&
          playlistQueue.containsKey(currentPlaylistId.value) &&
          jobSongList.last != song) {
        await Future.delayed(_playlistDownloadDelay);
      }
    }
  }

  Future<void> writeFileStream(MediaItem song) async {
    final traceId = "${song.id}-${DateTime.now().millisecondsSinceEpoch}";
    final stopwatch = Stopwatch()..start();
    final settingsScreenController = Get.find<SettingsScreenController>();
    final downloadingFormat = settingsScreenController.downloadingFormat.string;

    _setPhase("resolvingStream", "Resolving stream", song, traceId);
    final playerResponse = await StreamProvider.fetch(
      song.id,
    ).timeout(_streamFetchTimeout);

    if (!playerResponse.playable) {
      currentDownloadPhase.value = "failed";
      currentDownloadDebugMessage.value = "Stream not playable";
      lastDownloadError.value =
          "${song.title}: ${playerResponse.statusMSG == "networkError" ? playerResponse.statusMSG.tr : playerResponse.statusMSG}";
      _showDownloadError(
        song,
        playerResponse.statusMSG == "networkError"
            ? playerResponse.statusMSG.tr
            : playerResponse.statusMSG,
      );
      printINFO(
        "[$traceId] Requested song ${song.title} is not downloadable: ${playerResponse.statusMSG}",
        tag: LogTags.downloader,
      );
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

    final dirPath = settingsScreenController.downloadLocationPath.string;
    final actualDownFormat = requiredAudioStream.audioCodec.name.contains("mp")
        ? "m4a"
        : "opus";
    final RegExp invalidChar = RegExp(r'[\/\\"<>\*\?:!\[\]¡\|%]');
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
          "${settingsScreenController.supportDirPath}/thumbnails/${song.id}.png";
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
    song.extras?['url'] = filePath;
    final songJson = MediaItemBuilder.toJson(song);
    final streamInfoJson = requiredAudioStream.toJson();
    streamInfoJson['url'] = filePath;
    // [playability status, info map]
    songJson["streamInfo"] = [true, streamInfoJson];

    Hive.box(BoxNames.songDownloads).put(song.id, songJson);
    Get.find<LibrarySongsController>().librarySongsList.add(song);
    try {
      Get.find<PlaylistScreenController>(
        tag: const Key(BoxNames.libFavNotDownloaded).hashCode.toString(),
      ).addNRemoveItemsinList(song, action: 'remove');
      // ignore: empty_catches
    } catch (e) {}

    _setPhase("completed", "Downloaded", song, traceId);
    printINFO(
      "[$traceId] Downloaded ${song.title} successfully in ${stopwatch.elapsed}",
      tag: LogTags.downloader,
    );
  }

  @override
  void cancelSongDownload(MediaItem song) {
    songQueue.remove(song);
    for (final playlistId in playlistQueue.keys.toList()) {
      playlistQueue[playlistId]?.remove(song);
      if (playlistQueue[playlistId]?.isEmpty ?? false) {
        playlistQueue.remove(playlistId);
      }
    }
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
    printINFO(
      "[$traceId] $debugMessage: ${song.title} (${song.id})",
      tag: LogTags.downloader,
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
    printERROR(
      "$message${song == null ? "" : " for ${song.title}"}: $error",
      tag: LogTags.downloader,
    );
    printERROR(stackTrace, tag: LogTags.downloader);
    if (showSnack && song != null) {
      _showDownloadError(song, "downloadError3".tr);
    }
  }

  void _showDownloadError(MediaItem song, String message) {
    final context = Get.context;
    if (context == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      snackbar(
        context,
        "${song.title}: $message",
        size: SanckBarSize.BIG,
        duration: const Duration(seconds: 2),
        top: !GetPlatform.isDesktop,
      ),
    );
  }
}
