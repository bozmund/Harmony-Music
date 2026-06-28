import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../domain/repositories/app_repositories.dart';
import '/ui/widgets/common_dialog_widget.dart';

class SongInfoDialog extends StatelessWidget {
  final MediaItem song;
  const SongInfoDialog({super.key, required this.song});

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      child: FutureBuilder<Map<dynamic, dynamic>>(
        future: _getStreamInfo(song.id),
        builder: (context, snapshot) {
          final streamInfo = snapshot.data ?? _nullStreamInfo;
          return SizedBox(
            height: Get.mediaQuery.size.height * .7,
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

  Future<Map<dynamic, dynamic>> _getStreamInfo(String id) async {
    final downloadRepository = Get.find<DownloadRepository>();
    final songCacheRepository = Get.find<SongCacheRepository>();
    final settingsRepository = Get.find<SettingsRepository>();

    if (await downloadRepository.containsDownload(id)) {
      final song = await downloadRepository.getDownloadJson(id);
      return song["streamInfo"] == null
          ? _nullStreamInfo
          : song["streamInfo"][1];
    }

    final dbStreamData = await songCacheRepository.getStreamCacheEntry(id);
    return dbStreamData != null &&
            dbStreamData.runtimeType.toString().contains("Map")
        ? dbStreamData[settingsRepository.getStreamingQualityIndex() == 0
              ? 'lowQualityAudio'
              : "highQualityAudio"]
        : _nullStreamInfo;
  }
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
