import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/utils/get_localization.dart';

import '../../app/providers/controller_providers.dart';
import '../../app/providers/repository_providers.dart';
import '../../app/providers/service_providers.dart';

import 'loader.dart';
import 'snackbar.dart';

class SongDownloadButton extends ConsumerWidget {
  const SongDownloadButton({
    super.key,
    this.calledFromPlayer = false,
    this.song_,
    this.isDownloadingDoneCallback,
    this.showDebugStatus = true,
  });
  final bool calledFromPlayer;
  final MediaItem? song_;
  final void Function(bool)? isDownloadingDoneCallback;
  final bool showDebugStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloader = ref.watch(downloaderProvider);
    final downloadRepository = ref.read(downloadRepositoryProvider);
    final songCacheRepository = ref.read(songCacheRepositoryProvider);
    final playerController = ref.read(playerControllerProvider);
    return AnimatedBuilder(
      animation: Listenable.merge([downloader, playerController.currentSong]),
      builder: (context, _) {
        final song = calledFromPlayer
            ? playerController.currentSong.value
            : song_;
        if (song == null && calledFromPlayer) return const SizedBox.shrink();
        final isDownloadingDone =
            downloader.songQueue.contains(song) &&
            downloader.currentSong == song &&
            downloader.songDownloadingProgress.value == 100;
        if (isDownloadingDoneCallback != null) {
          isDownloadingDoneCallback!(isDownloadingDone);
        }

        return FutureBuilder<bool>(
          future: downloadRepository.containsDownload(song!.id),
          builder: (context, snapshot) {
            final isDownloaded = snapshot.data ?? false;
            return (isDownloadingDone || isDownloaded)
                ? Icon(
                    Icons.download_done,
                    color: Theme.of(context).textTheme.titleMedium!.color,
                  )
                : downloader.songQueue.contains(song) &&
                      downloader.isJobRunning.value &&
                      downloader.currentSong == song
                ? Tooltip(
                    message: kDebugMode
                        ? downloader.currentDownloadDebugMessage.value
                        : "",
                    child: SizedBox(
                      width: showDebugStatus && kDebugMode ? 96 : 40,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              Align(
                                alignment: Alignment.center,
                                child: Text(
                                  "${downloader.songDownloadingProgress.value}%",
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium!
                                      .copyWith(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ),
                              LoadingIndicator(
                                dimension: 30,
                                strokeWidth: 4,
                                value:
                                    (downloader.songDownloadingProgress.value) /
                                    100,
                              ),
                            ],
                          ),
                          if (showDebugStatus &&
                              kDebugMode &&
                              downloader
                                  .currentDownloadDebugMessage
                                  .value
                                  .isNotEmpty)
                            Flexible(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                  downloader.currentDownloadDebugMessage.value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(fontSize: 10),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                : downloader.songQueue.contains(song)
                ? Tooltip(
                    message:
                        kDebugMode &&
                            downloader
                                .currentDownloadDebugMessage
                                .value
                                .isNotEmpty
                        ? downloader.currentDownloadDebugMessage.value
                        : "",
                    child: SizedBox(
                      width: showDebugStatus && kDebugMode ? 96 : 40,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const LoadingIndicator(),
                          if (showDebugStatus &&
                              kDebugMode &&
                              downloader
                                  .currentDownloadDebugMessage
                                  .value
                                  .isNotEmpty)
                            Flexible(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                  downloader.currentDownloadDebugMessage.value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(fontSize: 10),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                : IconButton(
                    icon: Icon(
                      Icons.download,
                      color: Theme.of(context).textTheme.titleMedium!.color,
                    ),
                    onPressed: () async {
                      if (await songCacheRepository.containsCachedSong(
                        song.id,
                      )) {
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          snackbar(
                            context,
                            "songAlreadyOfflineAlert".tr,
                            size: SanckBarSize.BIG,
                          ),
                        );
                      } else {
                        await downloader.download(song);
                      }
                    },
                  );
          },
        );
      },
    );
  }
}
