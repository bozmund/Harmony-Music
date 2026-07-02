import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/utils/get_localization.dart';

import '../../app/providers/controller_providers.dart';
import '../../app/providers/repository_providers.dart';
import '/ui/widgets/common_dialog_widget.dart';

class SongInfoDialog extends StatelessWidget {
  final MediaItem song;
  final bool includePlaybackDebug;
  const SongInfoDialog({
    super.key,
    required this.song,
    this.includePlaybackDebug = false,
  });

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      child: FutureBuilder<_SongInfoDetails>(
        future: _getDetails(context, song.id),
        builder: (context, snapshot) {
          final details = snapshot.data;
          final streamInfo = details?.streamInfo ?? _nullStreamInfo;
          final playbackDebug = details?.playbackDebug;
          return SizedBox(
            height: MediaQuery.of(context).size.height * .7,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                  child: Text(
                    "songInfo".tr,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    children: [
                      InfoItem(title: "id".tr, value: song.id),
                      InfoItem(title: "title".tr, value: song.title),
                      InfoItem(title: "album".tr, value: song.album ?? "NA"),
                      InfoItem(title: "artists".tr, value: song.artist ?? "NA"),
                      InfoItem(
                        title: "duration".tr,
                        value:
                            "${streamInfo["approxDurationMs"] ?? song.duration?.inMilliseconds ?? "NA"} ms",
                      ),
                      InfoItem(
                        title: "audioCodec".tr,
                        value: streamInfo["audioCodec"] ?? "NA",
                      ),
                      InfoItem(
                        title: "bitrate".tr,
                        value: "${streamInfo["bitrate"] ?? "NA"}",
                      ),
                      InfoItem(
                        title: "loudnessDb".tr,
                        value: "${streamInfo["loudnessDb"] ?? "NA"}",
                      ),
                      if (includePlaybackDebug) ...[
                        const Divider(),
                        InfoItem(
                          title: "Playback and handler state",
                          value: playbackDebug == null
                              ? "Loading..."
                              : const JsonEncoder.withIndent(
                                  '  ',
                                ).convert(playbackDebug),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(),
                SizedBox(
                  height: 50,
                  child: Align(
                    alignment: Alignment.center,
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10.0,
                          horizontal: 25,
                        ),
                        child: Text("close".tr),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static const _nullStreamInfo = {
    "audioCodec": null,
    "bitrate": null,
    "loudnessDb": null,
    "approxDurationMs": null,
  };

  Future<Map<dynamic, dynamic>> _getStreamInfo(
    BuildContext context,
    String id,
  ) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final downloadRepository = container.read(downloadRepositoryProvider);
    final songCacheRepository = container.read(songCacheRepositoryProvider);
    final settingsRepository = container.read(settingsRepositoryProvider);

    if (await downloadRepository.containsDownload(id)) {
      final song = await downloadRepository.getDownloadJson(id);
      final streamInfo = song is Map ? song["streamInfo"] : null;
      final audioJson = streamInfo is List && streamInfo.length > 1
          ? streamInfo[1]
          : null;
      return audioJson is Map ? audioJson : _nullStreamInfo;
    }

    final streamInfo = await songCacheRepository.getStreamInfo(
      id,
      settingsRepository.getStreamingQualityIndex(),
    );
    final audio = streamInfo?.audio;
    return audio == null ? _nullStreamInfo : audio.toJson();
  }

  Future<_SongInfoDetails> _getDetails(BuildContext context, String id) async {
    final streamInfo = await _getStreamInfo(context, id);
    if (!includePlaybackDebug) {
      return _SongInfoDetails(streamInfo: streamInfo);
    }

    final container = ProviderScope.containerOf(context, listen: false);
    final playerController = container.read(playerControllerProvider);
    final playbackDebug = await playerController
        .detailedPlaybackDebugSnapshot();
    return _SongInfoDetails(
      streamInfo: streamInfo,
      playbackDebug: playbackDebug,
    );
  }
}

class _SongInfoDetails {
  const _SongInfoDetails({required this.streamInfo, this.playbackDebug});

  final Map<dynamic, dynamic> streamInfo;
  final Map<String, dynamic>? playbackDebug;
}

class InfoItem extends StatelessWidget {
  final String title;
  final String value;
  const InfoItem({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, textAlign: TextAlign.start),
          TextSelectionTheme(
            data: Theme.of(context).textSelectionTheme,
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}
