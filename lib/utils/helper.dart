import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '/services/constant.dart';
import '/ui/navigator.dart';
import '/ui/widgets/sort_widget.dart';

void printERROR(dynamic text, {String tag = "Harmony Music"}) {
  if (kReleaseMode) return;
  debugPrint("\x1B[31m[$tag]: $text\x1B[0m");
}

void printWarning(dynamic text, {String tag = 'Harmony Music'}) {
  if (kReleaseMode) return;
  debugPrint("\x1B[33m[$tag]: $text\x1B[34m");
}

void printINFO(dynamic text, {String tag = 'Harmony Music'}) {
  if (kReleaseMode) return;
  debugPrint("\x1B[32m[$tag]: $text\x1B[34m");
}

String? getCurrentRouteName() {
  String? currentPath;
  Get.nestedKey(ScreenNavigationSetup.id)?.currentState?.popUntil((route) {
    currentPath = route.settings.name;
    return true;
  });
  return currentPath;
}

void sortSongsNVideos(List songlist, SortType sortType, bool isAscending) {
  Comparator compareFunction;

  switch (sortType) {
    case SortType.Date:
      compareFunction = (a, b) {
        if (a.extras!['date'] == null || b.extras!['date'] == null) {
          return 0.compareTo(0);
        }
        return a.extras!['date'].compareTo(b.extras!['date']);
      };
      break;
    case SortType.Duration:
      compareFunction = (a, b) =>
          (a.duration ?? Duration.zero).compareTo(b.duration ?? Duration.zero);
    case SortType.Name:
    default:
      compareFunction = (a, b) =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase());
      break;
  }

  songlist.sort(compareFunction);

  if (!isAscending) {
    List reversed = songlist.reversed.toList();
    songlist.clear();
    songlist.addAll(reversed);
  }
}

void sortAlbumNSingles(List albumList, SortType sortType, bool isAscending) {
  Comparator compareFunction;

  switch (sortType) {
    case SortType.Date:
      compareFunction = (a, b) =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase());
      break;
    case SortType.Name:
    default:
      compareFunction = (a, b) {
        if (a.year == null || b.year == null) {
          return 0.compareTo(0);
        }
        return a.year!.compareTo(b.year!);
      };
      break;
  }

  albumList.sort(compareFunction);

  if (!isAscending) {
    List reversed = albumList.reversed.toList();
    albumList.clear();
    albumList.addAll(reversed);
  }
}

void sortPlayLists(List playlists, SortType sortType, bool isAscending) {
  Comparator compareFunction;
  int titleSort(a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());

  switch (sortType) {
    case SortType.RecentlyPlayed:
      compareFunction = (a, b) {
        DateTime? alp = a.lastPlayed;
        DateTime? blp = b.lastPlayed;
        if (alp == null && blp == null) {
          return titleSort(a, b);
        }
        if (alp == null) {
          return 1;
        }
        if (blp == null) {
          return -1;
        }
        return blp.compareTo(alp);
      };
      break;
    case SortType.Name:
    default:
      compareFunction = titleSort;
      break;
  }

  playlists.sort(compareFunction);

  if (!isAscending) {
    List reversed = playlists.reversed.toList();
    playlists.clear();
    playlists.addAll(reversed);
  }
}

void sortArtist(List artistList, SortType sortType, bool isAscending) {
  Comparator compareFunction;

  switch (sortType) {
    case SortType.Name:
    default:
      compareFunction = (a, b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase());
      break;
  }

  artistList.sort(compareFunction);

  if (!isAscending) {
    List reversed = artistList.reversed.toList();
    artistList.clear();
    artistList.addAll(reversed);
  }
}

enum UpdateChannel { stable, rolling }

class UpdateInfo {
  const UpdateInfo({
    required this.channel,
    required this.version,
    required this.downloadUrl,
    this.releaseUrl,
    this.sha,
  });

  final UpdateChannel channel;
  final String version;
  final String downloadUrl;
  final String? releaseUrl;
  final String? sha;
}

/// Return update metadata when a new version is available.
Future<UpdateInfo?> newVersionCheck(
  String currentVersion, {
  UpdateChannel channel = UpdateChannel.stable,
}) async {
  try {
    if (channel == UpdateChannel.rolling) {
      return await _rollingVersionCheck();
    }

    final tags = (await Dio().get(
      "https://api.github.com/repos/bozmund/Harmony-Music/tags",
    )).data;

    final versionTagPattern = RegExp(r'^v\d+\.\d+\.\d+$');
    final semanticTags = (tags as List)
        .map((tag) => tag['name'])
        .whereType<String>()
        .where((tag) => versionTagPattern.hasMatch(tag))
        .toList();
    if (semanticTags.isEmpty) return null;
    semanticTags.sort((a, b) => _compareSemanticVersions(b, a));

    final currentVersion_ = currentVersion
        .toLowerCase()
        .replaceFirst('v', '')
        .split(".");
    final latestTag = semanticTags.first;
    final availableVersion_ = latestTag.substring(1).split(".");
    final isNewer =
        int.parse(availableVersion_[0]) > int.parse(currentVersion_[0]) ||
        (int.parse(availableVersion_[1]) > int.parse(currentVersion_[1]) &&
            int.parse(availableVersion_[0]) == int.parse(currentVersion_[0])) ||
        (int.parse(availableVersion_[2]) > int.parse(currentVersion_[2]) &&
            int.parse(availableVersion_[0]) == int.parse(currentVersion_[0]) &&
            int.parse(availableVersion_[1]) == int.parse(currentVersion_[1]));
    if (!isNewer) return null;

    final releasePage =
        "https://github.com/bozmund/Harmony-Music/releases/tag/$latestTag";
    String? downloadUrl;
    String? releaseUrl;
    try {
      final release = (await Dio().get(
        "https://api.github.com/repos/bozmund/Harmony-Music/releases/tags/$latestTag",
      )).data;
      downloadUrl = _releaseApkDownloadUrl(release);
      releaseUrl = release['html_url'] as String?;
    } catch (_) {
      // Keep the update notification useful even if release metadata fails.
    }

    return UpdateInfo(
      channel: UpdateChannel.stable,
      version: latestTag,
      downloadUrl: downloadUrl ?? releaseUrl ?? releasePage,
      releaseUrl: releaseUrl ?? releasePage,
    );
  } catch (e) {
    return null;
  }
}

Future<UpdateInfo?> _rollingVersionCheck() async {
  final release = (await Dio().get(
    "https://api.github.com/repos/bozmund/Harmony-Music/releases/tags/main-latest",
  )).data;
  final remoteSha = _rollingReleaseSha(release);
  if (remoteSha == null || remoteSha.isEmpty || remoteSha == BuildInfo.sha) {
    return null;
  }

  final browserDownloadUrl = _releaseApkDownloadUrl(release);

  return UpdateInfo(
    channel: UpdateChannel.rolling,
    version: release['tag_name'] ?? 'main-latest',
    downloadUrl:
        browserDownloadUrl ??
        release['html_url'] ??
        'https://github.com/bozmund/Harmony-Music/releases/tag/main-latest',
    releaseUrl:
        release['html_url'] ??
        'https://github.com/bozmund/Harmony-Music/releases/tag/main-latest',
    sha: remoteSha,
  );
}

String? _releaseApkDownloadUrl(dynamic release) {
  final assets = (release['assets'] as List?) ?? [];
  final apkAsset = assets.cast<dynamic>().firstWhere(
    (asset) =>
        asset is Map &&
        (asset['name'] as String? ?? '').toLowerCase().endsWith('.apk'),
    orElse: () => null,
  );
  return apkAsset is Map ? apkAsset['browser_download_url'] as String? : null;
}

String? _rollingReleaseSha(dynamic release) {
  final body = release['body'] as String?;
  final bodySha = body == null
      ? null
      : RegExp(r'Build SHA:\s*([a-fA-F0-9]{7,40})').firstMatch(body)?.group(1);
  if (bodySha != null && bodySha.isNotEmpty) return bodySha;

  final targetCommitish = release['target_commitish'] as String?;
  if (targetCommitish != null &&
      RegExp(r'^[a-fA-F0-9]{7,40}$').hasMatch(targetCommitish)) {
    return targetCommitish;
  }
  return null;
}

int _compareSemanticVersions(String a, String b) {
  final aParts = a.substring(1).split('.').map(int.parse).toList();
  final bParts = b.substring(1).split('.').map(int.parse).toList();
  for (int i = 0; i < 3; i++) {
    final diff = aParts[i].compareTo(bParts[i]);
    if (diff != 0) return diff;
  }
  return 0;
}

String getTimeString(Duration time) {
  final minutes = time.inMinutes.remainder(Duration.minutesPerHour).toString();
  final seconds = time.inSeconds
      .remainder(Duration.secondsPerMinute)
      .toString()
      .padLeft(2, '0');
  return time.inHours > 0
      ? "${time.inHours}:${minutes.padLeft(2, "0")}:$seconds"
      : "$minutes:$seconds";
}
