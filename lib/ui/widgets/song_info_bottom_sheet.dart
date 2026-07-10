import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/utils/get_localization.dart';

import '../../app/navigation/app_navigator.dart';
import '../../app/providers/controller_providers.dart';
import '../../app/providers/repository_providers.dart';
import '../../app/providers/service_providers.dart';
import '../../domain/repositories/download_repository.dart';
import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/playlist_repository.dart';
import '../../domain/repositories/song_cache_repository.dart';
import '../../services/constant.dart';
import '../../services/downloader.dart';
import '../screens/Playlist/playlist_screen_controller.dart';
import '../screens/Settings/settings_screen_controller.dart';
import '/utils/helper.dart';
import '../../services/app_platform_service.dart';
import '/services/piped_service.dart';
import '/ui/widgets/sleep_timer_bottom_sheet.dart';
import '/ui/player/player_controller.dart';
import '../screens/Library/library_controller.dart';
import '/ui/widgets/add_to_playlist.dart';
import 'issue_report_dialog.dart';
import '/ui/widgets/snackbar.dart';
import '../../models/playlist.dart';
import '../navigator.dart';
import 'awaitable_button.dart';
import 'song_download_btn.dart';
import 'image_widget.dart';
import 'song_info_dialog.dart';

class SongInfoBottomSheet extends ConsumerStatefulWidget {
  const SongInfoBottomSheet(
    this.song, {
    super.key,
    this.playlist,
    this.calledFromPlayer = false,
    this.calledFromQueue = false,
  });
  final MediaItem song;
  final Playlist? playlist;
  final bool calledFromPlayer;
  final bool calledFromQueue;

  @override
  ConsumerState<SongInfoBottomSheet> createState() =>
      _SongInfoBottomSheetState();
}

class _SongInfoBottomSheetState extends ConsumerState<SongInfoBottomSheet> {
  late final SongInfoController songInfoController;
  bool _initialized = false;

  MediaItem get song => widget.song;
  Playlist? get playlist => widget.playlist;
  bool get calledFromPlayer => widget.calledFromPlayer;
  bool get calledFromQueue => widget.calledFromQueue;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final container = ProviderScope.containerOf(context, listen: false);
    songInfoController = SongInfoController(
      song,
      calledFromPlayer,
      libraryRepository: container.read(libraryRepositoryProvider),
      downloadRepository: container.read(downloadRepositoryProvider),
      playlistRepository: container.read(playlistRepositoryProvider),
      songCacheRepository: container.read(songCacheRepositoryProvider),
      playerController: container.read(playerControllerProvider),
      settingsScreenController: container.read(
        settingsScreenControllerProvider,
      ),
      downloader: container.read(downloaderProvider),
    );
    SongInfoControllerRegistry.open();
    unawaited(songInfoController.init());
    _initialized = true;
  }

  @override
  void dispose() {
    SongInfoControllerRegistry.close();
    songInfoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerController = ref.read(playerControllerProvider);
    final settingsController = ref.read(settingsScreenControllerProvider);
    final showDebugIssueReport =
        calledFromPlayer &&
        kDebugMode &&
        settingsController.developerSettingsEnabled.value;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: const EdgeInsets.only(
                left: 15,
                top: 7,
                right: 10,
                bottom: 0,
              ),
              leading: ImageWidget(song: song, size: 50),
              title: Text(song.title, maxLines: 1),
              subtitle: Text(song.artist!),
              trailing: SizedBox(
                width: 110,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    calledFromPlayer
                        ? IconButton(
                          onPressed: () async {
                            await showDialog(
                              context: context,
                              builder:
                                  (context) => SongInfoDialog(
                                    song: song,
                                    includePlaybackDebug: true,
                                  ),
                            );
                          },
                          icon: Icon(
                            Icons.info,
                            color:
                                Theme.of(context).textTheme.titleMedium!.color,
                          ),
                        )
                        : IconButton(
                          onPressed: songInfoController.toggleFav,
                          icon: AnimatedBuilder(
                            animation: songInfoController,
                            builder:
                                (context, _) => Icon(
                                  !songInfoController.isCurrentSongFav
                                      ? Icons.favorite_border
                                      : Icons.favorite,
                                  color:
                                      Theme.of(
                                        context,
                                      ).textTheme.titleMedium!.color,
                                ),
                          ),
                        ),
                    SongDownloadButton(
                      song_: song,
                      showDebugStatus: false,
                      isDownloadingDoneCallback:
                          songInfoController.setDownloadStatus,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(),
            if (showDebugIssueReport)
              ListTile(
                visualDensity: const VisualDensity(vertical: -1),
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text("Report playback bug"),
                onTap: () async {
                  Navigator.of(context).pop();
                  await showDialog(
                    context: context,
                    builder:
                        (context) => IssueReportDialog(
                          extraDiagnosticsBuilder:
                              () async => {
                                'playback':
                                    await playerController
                                        .detailedPlaybackDebugSnapshot(),
                              },
                        ),
                  );
                },
              ),
            ListTile(
              visualDensity: const VisualDensity(vertical: -1),
              leading: const Icon(Icons.sensors),
              title: Text("startRadio".tr),
              onTap: () async {
                Navigator.of(context).pop();
                await playerController.startRadio(song);
              },
            ),
            (calledFromPlayer || calledFromQueue)
                ? const SizedBox.shrink()
                : ListTile(
                  visualDensity: const VisualDensity(vertical: -1),
                  leading: const Icon(Icons.queue_play_next),
                  title: Text("playNext".tr),
                  onTap: () {
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.of(context).pop();
                    unawaited(
                      playerController.playNext(song).whenComplete(() {
                        if (!context.mounted) return;
                        messenger.showSnackBar(
                          snackbar(
                            context,
                            "${"playNextMsg".tr} ${song.title}",
                            size: SanckBarSize.BIG,
                          ),
                        );
                      }),
                    );
                  },
                ),
            ListTile(
              visualDensity: const VisualDensity(vertical: -1),
              leading: const Icon(Icons.add_circle_outline),
              title: Text("addToPlaylist".tr),
              onTap: () async {
                Navigator.of(context).pop();
                await showDialog(
                  context: context,
                  builder: (context) => AddToPlaylist([song]),
                );
              },
            ),
            (calledFromPlayer || calledFromQueue)
                ? const SizedBox.shrink()
                : ListTile(
                  visualDensity: const VisualDensity(vertical: -1),
                  leading: const Icon(Icons.merge),
                  title: Text("enqueueSong".tr),
                  onTap: () {
                    final messenger = ScaffoldMessenger.of(context);
                    unawaited(
                      playerController.enqueueSong(song).whenComplete(() {
                        if (!context.mounted) return;
                        messenger.showSnackBar(
                          snackbar(
                            context,
                            "songEnqueueAlert".tr,
                            size: SanckBarSize.MEDIUM,
                          ),
                        );
                      }),
                    );
                    Navigator.of(context).pop();
                  },
                ),
            song.extras!['album'] != null
                ? ListTile(
                  visualDensity: const VisualDensity(vertical: -1),
                  leading: const Icon(Icons.album),
                  title: Text("goToAlbum".tr),
                  onTap: () async {
                    Navigator.of(context).pop();
                    if (calledFromPlayer) {
                      await playerController.playerPanelController.close();
                    }
                    if (calledFromQueue) {
                      await playerController.playerPanelController.close();
                    }
                    await ScreenNavigationSetup.navigatorKey.currentState
                        ?.pushNamed(
                          ScreenNavigationSetup.albumScreen,
                          arguments: (null, song.extras!['album']['id']),
                        );
                  },
                )
                : const SizedBox.shrink(),
            ...artistWidgetList(song, context, playerController),
            (playlist != null &&
                        !playlist!.isCloudPlaylist &&
                        !(playlist!.playlistId == "LIBRP")) ||
                    (playlist != null && playlist!.isPipedPlaylist)
                ? ListTile(
                  visualDensity: const VisualDensity(vertical: -1),
                  leading: const Icon(Icons.delete),
                  title:
                      playlist!.title == "Library Songs"
                          ? Text("removeFromLib".tr)
                          : Text("removeFromPlaylist".tr),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await songInfoController
                        .removeSongFromPlaylist(song, playlist!)
                        .whenComplete(() {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            snackbar(
                              context,
                              "Removed from ${playlist!.title}",
                              size: SanckBarSize.MEDIUM,
                            ),
                          );
                        });
                  },
                )
                : const SizedBox.shrink(),
            calledFromQueue
                ? ListTile(
                  visualDensity: const VisualDensity(vertical: -1),
                  leading: const Icon(Icons.delete),
                  title: Text("removeFromQueue".tr),
                  onTap: () {
                    Navigator.of(context).pop();
                    if (playerController.currentSong.value!.id == song.id) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        snackbar(
                          context,
                          "songRemovedFromQueueCurrSong".tr,
                          size: SanckBarSize.BIG,
                        ),
                      );
                    } else {
                      final messenger = ScaffoldMessenger.of(context);
                      unawaited(
                        playerController.removeFromQueue(song).whenComplete(() {
                          if (!context.mounted) return;
                          messenger.showSnackBar(
                            snackbar(
                              context,
                              "songRemovedFromQueue".tr,
                              size: SanckBarSize.MEDIUM,
                            ),
                          );
                        }),
                      );
                    }
                  },
                )
                : const SizedBox.shrink(),
            AnimatedBuilder(
              animation: songInfoController,
              builder:
                  (context, _) =>
                      (songInfoController.isDownloaded &&
                              (playlist?.playlistId != BoxNames.songDownloads &&
                                  playlist?.playlistId != BoxNames.songsCache))
                          ? ListTile(
                            contentPadding: const EdgeInsets.only(left: 15),
                            visualDensity: const VisualDensity(vertical: -1),
                            leading: const Icon(Icons.delete),
                            title: Text("deleteDownloadData".tr),
                            onTap: () async {
                              Navigator.of(context).pop();
                              final downloadJson = await songInfoController
                                  .downloadRepository
                                  .getDownloadJson(song.id);
                              final downloadUrl =
                                  downloadJson is Map
                                      ? downloadJson['url']?.toString()
                                      : null;
                              await LibrarySongsControllerRegistry.current
                                  ?.removeSong(song, true, url: downloadUrl);
                              await songInfoController.downloadRepository
                                  .deleteDownloadedSong(song.id);
                              if (playlist != null) {
                                PlaylistScreenControllerRegistry.maybeOf(
                                  Key(playlist!.playlistId).hashCode.toString(),
                                )?.checkDownloadStatus();
                              }
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  snackbar(
                                    context,
                                    "deleteDownloadedDataAlert".tr,
                                    size: SanckBarSize.BIG,
                                  ),
                                );
                              }
                            },
                          )
                          : const SizedBox.shrink(),
            ),
            ListTile(
              leading: const Icon(Icons.open_with),
              title: Text("openIn".tr),
              trailing: SizedBox(
                width: 200,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    AwaitableIconButton(
                      splashRadius: 10,
                      onPressed: () async {
                        await AppPlatformService.openUrl(
                          "https://youtube.com/watch?v=${song.id}",
                        );
                      },
                      icon: const Icon(Icons.smart_display),
                    ),
                    AwaitableIconButton(
                      splashRadius: 10,
                      onPressed: () async {
                        await AppPlatformService.openUrl(
                          "https://music.youtube.com/watch?v=${song.id}",
                        );
                      },
                      icon: const Icon(Icons.play_circle),
                    ),
                  ],
                ),
              ),
            ),
            if (calledFromPlayer)
              ListTile(
                contentPadding: const EdgeInsets.only(left: 15),
                visualDensity: const VisualDensity(vertical: -1),
                leading: const Icon(Icons.timer),
                title: Text("sleepTimer".tr),
                onTap: () async {
                  Navigator.of(context).pop();
                  await showModalBottomSheet(
                    constraints: const BoxConstraints(maxWidth: 500),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(10.0),
                      ),
                    ),
                    isScrollControlled: true,
                    context:
                        playerController.homeScaffoldKey.currentState!.context,
                    barrierColor: Colors.transparent.withAlpha(100),
                    builder: (context) => const SleepTimerBottomSheet(),
                  );
                },
              ),
            ListTile(
              contentPadding: const EdgeInsets.only(left: 15),
              visualDensity: const VisualDensity(vertical: -1),
              leading: const Icon(Icons.share),
              title: Text("shareSong".tr),
              onTap: () async {
                await AppPlatformService.shareText(
                  "https://youtube.com/watch?v=${song.id}",
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> artistWidgetList(
    MediaItem song,
    BuildContext context,
    PlayerController playerController,
  ) {
    final artistList = [];
    final artists = song.extras!['artists'];
    if (artists != null) {
      for (dynamic each in artists) {
        if (each.containsKey("id") && each['id'] != null) artistList.add(each);
      }
    }
    return artistList.isNotEmpty
        ? artistList
            .map(
              (e) => ListTile(
                onTap: () async {
                  Navigator.of(context).pop();
                  if (calledFromPlayer) {
                    await playerController.playerPanelController.close();
                  }
                  if (calledFromQueue) {
                    await playerController.playerPanelController.close();
                  }
                  await ScreenNavigationSetup.navigatorKey.currentState
                      ?.pushNamed(
                        ScreenNavigationSetup.artistScreen,
                        arguments: [true, e['id']],
                      );
                },
                tileColor: Colors.transparent,
                leading: const Icon(Icons.person),
                title: Text("${"viewArtist".tr} (${e['name']})"),
              ),
            )
            .toList()
        : [const SizedBox.shrink()];
  }
}

class SongInfoController extends ChangeNotifier
    with RemoveSongFromPlaylistMixin {
  bool isCurrentSongFav = false;
  final MediaItem song;
  final bool calledFromPlayer;
  List artistList = [];
  bool isDownloaded = false;
  SongInfoController(
    this.song,
    this.calledFromPlayer, {
    required LibraryRepository libraryRepository,
    required DownloadRepository downloadRepository,
    required PlaylistRepository playlistRepository,
    required SongCacheRepository songCacheRepository,
    required PlayerController playerController,
    required SettingsScreenController settingsScreenController,
    required Downloader downloader,
  }) : _libraryRepository = libraryRepository,
       _downloadRepository = downloadRepository,
       _playlistRepository = playlistRepository,
       _songCacheRepository = songCacheRepository,
       _playerController = playerController,
       _settingsScreenController = settingsScreenController,
       _downloader = downloader;

  final LibraryRepository _libraryRepository;
  final DownloadRepository _downloadRepository;
  final PlaylistRepository _playlistRepository;
  final SongCacheRepository _songCacheRepository;
  final PlayerController _playerController;
  final SettingsScreenController _settingsScreenController;
  final Downloader _downloader;
  LibraryRepository get libraryRepository => _libraryRepository;
  DownloadRepository get downloadRepository => _downloadRepository;
  PlaylistRepository get playlistRepository => _playlistRepository;
  SongCacheRepository get songCacheRepository => _songCacheRepository;

  Future<void> _setInitStatus(MediaItem song) async {
    isDownloaded = await _downloadRepository.containsDownload(song.id);
    isCurrentSongFav = await _libraryRepository.isFavorite(song.id);
    final artists = song.extras!['artists'];
    if (artists != null) {
      for (dynamic each in artists) {
        if (each.containsKey("id") && each['id'] != null) artistList.add(each);
      }
    }
    notifyListeners();
  }

  Future<void> init() async {
    await _setInitStatus(song);
  }

  void setDownloadStatus(bool isDownloaded_) {
    if (isDownloaded_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        isDownloaded = isDownloaded_;
        notifyListeners();
      });
    }
  }

  Future<void> toggleFav() async {
    if (calledFromPlayer) {
      if (_playerController.currentSong.value == song) {
        await _playerController.toggleFavourite();
        isCurrentSongFav = !isCurrentSongFav;
        notifyListeners();
        return;
      }
    }
    await _libraryRepository.setFavorite(song, !isCurrentSongFav);
    // The playlist-screen registry lookups below only refresh lists that
    // happen to be on screen; they must never gate the toggle itself —
    // the heart state, its listeners and the auto-download run regardless.
    try {
      final favoritesController = PlaylistScreenControllerRegistry.maybeOf(
        const Key(BoxNames.libFav).hashCode.toString(),
      );
      if (favoritesController != null) {
        if (!isCurrentSongFav) {
          await favoritesController.addNRemoveItemsInList(
            song,
            action: 'add',
            index: 0,
          );
        } else {
          await favoritesController.addNRemoveItemsInList(
            song,
            action: 'remove',
          );
        }
      }
    } catch (e) {
      printERROR(e, tag: LogTags.library);
    }
    try {
      final likedNotDownloadedController =
          PlaylistScreenControllerRegistry.maybeOf(
            const Key(BoxNames.libFavNotDownloaded).hashCode.toString(),
          );
      if (likedNotDownloadedController != null) {
        if (!isCurrentSongFav &&
            !await _downloadRepository.containsDownload(song.id)) {
          await likedNotDownloadedController.addNRemoveItemsInList(
            song,
            action: 'add',
            index: 0,
          );
        } else {
          await likedNotDownloadedController.addNRemoveItemsInList(
            song,
            action: 'remove',
          );
        }
      }
    } catch (e) {
      printERROR(e, tag: LogTags.library);
    }
    isCurrentSongFav = !isCurrentSongFav;
    notifyListeners();
    if (_settingsScreenController.autoDownloadFavoriteSongEnabled.value &&
        isCurrentSongFav) {
      await _downloader.download(song);
    }
  }
}

class SongInfoControllerRegistry {
  static var _openCount = 0;

  static bool get isOpen => _openCount > 0;

  static void open() {
    _openCount++;
  }

  static void close() {
    if (_openCount > 0) _openCount--;
  }
}

mixin RemoveSongFromPlaylistMixin {
  LibraryRepository get libraryRepository => ProviderScope.containerOf(
    AppNavigator.context!,
    listen: false,
  ).read(libraryRepositoryProvider);
  DownloadRepository get downloadRepository => ProviderScope.containerOf(
    AppNavigator.context!,
    listen: false,
  ).read(downloadRepositoryProvider);
  PlaylistRepository get playlistRepository => ProviderScope.containerOf(
    AppNavigator.context!,
    listen: false,
  ).read(playlistRepositoryProvider);
  SongCacheRepository get songCacheRepository => ProviderScope.containerOf(
    AppNavigator.context!,
    listen: false,
  ).read(songCacheRepositoryProvider);
  PipedServices get pipedServices => ProviderScope.containerOf(
    AppNavigator.context!,
    listen: false,
  ).read(pipedServicesProvider);

  Future<void> removeSongFromPlaylist(MediaItem item, Playlist playlist) async {
    if (playlist.playlistId == BoxNames.libFavNotDownloaded) {
      await libraryRepository.setFavorite(item, false);
      try {
        await PlaylistScreenControllerRegistry.maybeOf(
          Key(playlist.playlistId).hashCode.toString(),
        )?.addNRemoveItemsInList(item, action: 'remove');
      } catch (e) {
        printERROR(e, tag: LogTags.library);
      }
      return;
    }
    if (playlist.playlistId == BoxNames.libImportDuplicates ||
        playlist.playlistId == BoxNames.libImportReview) {
      if (playlist.playlistId == BoxNames.libImportDuplicates) {
        await libraryRepository.deleteImportDuplicate(item.id);
      } else {
        await libraryRepository.deleteImportReview(item.id);
      }
      try {
        await PlaylistScreenControllerRegistry.maybeOf(
          Key(playlist.playlistId).hashCode.toString(),
        )?.addNRemoveItemsInList(item, action: 'remove');
      } catch (e) {
        printERROR(e, tag: LogTags.library);
      }
      return;
    }

    if (playlist.isPipedPlaylist) {
      try {
        final playlistController = PlaylistScreenControllerRegistry.maybeOf(
          Key(playlist.playlistId).hashCode.toString(),
        );
        if (playlistController == null) return;
        final songs = await pipedServices.getPlaylistSongs(playlist.playlistId);
        final songIndex = songs.indexWhere((element) => element.id == item.id);
        if (songIndex != -1) {
          final res = await pipedServices.removeFromPlaylist(
            playlist.playlistId,
            songIndex,
          );
          if (res.code == 1) {
            await playlistController.addNRemoveItemsInList(
              item,
              action: 'remove',
            );
          }
        }
      } catch (e) {
        printERROR(
          "Some Error in removeSongFromPlaylist (might irrelevant): $e",
        );
      }
      return;
    }

    //Library songs case
    if (playlist.playlistId == BoxNames.songsCache) {
      if (!await songCacheRepository.containsCachedSong(item.id)) {
        await downloadRepository.deleteDownloadedSong(item.id);
        await LibrarySongsControllerRegistry.current?.removeSong(item, true);
      } else {
        await LibrarySongsControllerRegistry.current?.removeSong(item, false);
        await songCacheRepository.deleteCachedSong(item.id);
      }
    } else if (playlist.playlistId == BoxNames.songDownloads) {
      await downloadRepository.deleteDownloadedSong(item.id);
      await LibrarySongsControllerRegistry.current?.removeSong(item, true);
    } else if (!playlist.isPipedPlaylist) {
      final existed = await playlistRepository.playlistContainsSong(
        playlist.playlistId,
        item.id,
      );
      if (existed) {
        await playlistRepository.removeSongsFromPlaylist(playlist.playlistId, [
          item,
        ]);
      } else {
        printWarning(
          "Tried to remove missing song ${item.id} from playlist ${playlist.playlistId}",
          tag: LogTags.library,
        );
      }
    }

    // this try catch block is to handle the case when song is removed from lib-songs sections
    try {
      final playlistController = PlaylistScreenControllerRegistry.maybeOf(
        Key(playlist.playlistId).hashCode.toString(),
      );
      if (playlistController == null) return;
      try {
        await playlistController.addNRemoveItemsInList(item, action: 'remove');
      } catch (e) {
        printERROR(e, tag: LogTags.library);
      }
    } catch (e) {
      printERROR("Some Error in removeSongFromPlaylist (might irrelevant): $e");
    }
  }
}
