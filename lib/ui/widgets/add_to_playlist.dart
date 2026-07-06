import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/utils/get_localization.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '../../app/providers/repository_providers.dart';
import '../../app/providers/service_providers.dart';
import '../../domain/repositories/playlist_repository.dart';
import '../../services/piped_service.dart';
import '../../utils/helper.dart';
import '/ui/widgets/create_playlist_dialog.dart';
import '../../models/playlist.dart';
import 'common_dialog_widget.dart';
import 'snackbar.dart';

enum PlaylistAddStatus { added, skipped, failed }

class AddToPlaylist extends ConsumerStatefulWidget {
  const AddToPlaylist(this.songItems, {super.key});
  final List<MediaItem> songItems;

  @override
  ConsumerState<AddToPlaylist> createState() => _AddToPlaylistState();
}

class _AddToPlaylistState extends ConsumerState<AddToPlaylist> {
  late final AddToPlaylistController addToPlaylistController;
  late final bool isPipedLinked;

  @override
  void initState() {
    super.initState();
    final pipedServices = ref.read(pipedServicesProvider);
    isPipedLinked = pipedServices.isLoggedIn;
    addToPlaylistController = AddToPlaylistController(
      playlistRepository: ref.read(playlistRepositoryProvider),
      pipedServices: pipedServices,
    );
    unawaited(addToPlaylistController.loadPlaylists());
  }

  @override
  void dispose() {
    addToPlaylistController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      child: Container(
        height: isPipedLinked ? 400 : 350,
        padding: const EdgeInsets.only(
          top: 20,
          bottom: 30,
          left: 20,
          right: 20,
        ),
        child: Stack(
          children: [
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.only(bottom: 10.0, top: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Marquee(
                            id: "createNewPlaylistx",
                            delay: const Duration(milliseconds: 300),
                            child: Text(
                              "CreateNewPlaylist".tr,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        tooltip: "CreateNewPlaylist".tr,
                        icon: const Icon(Icons.playlist_add),
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await showDialog(
                            context: context,
                            builder: (context) => CreateNRenamePlaylistPopup(
                              isCreateNAdd: true,
                              songItems: widget.songItems,
                            ),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: "close".tr,
                        icon: const Icon(Icons.done),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                if (isPipedLinked)
                  AnimatedBuilder(
                    animation: addToPlaylistController,
                    builder: (context, _) => RadioGroup<String>(
                      groupValue: addToPlaylistController.playlistType.value,
                      onChanged: (value) {
                        if (value == null ||
                            addToPlaylistController.additionInProgress.value) {
                          return;
                        }
                        unawaited(
                          addToPlaylistController.changePlaylistType(value),
                        );
                      },
                      child: IgnorePointer(
                        ignoring:
                            addToPlaylistController.additionInProgress.value,
                        child: Opacity(
                          opacity:
                              addToPlaylistController.additionInProgress.value
                              ? 0.55
                              : 1,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Radio<String>(value: 'piped'),
                                  Text('Piped'.tr),
                                ],
                              ),
                              const SizedBox(width: 15),
                              Row(
                                children: [
                                  const Radio<String>(value: 'local'),
                                  Text('local'.tr),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColorLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    //color: Colors.green,
                    child: AnimatedBuilder(
                      animation: addToPlaylistController,
                      builder: (context, _) =>
                          addToPlaylistController.playlists.isNotEmpty
                          ? ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount:
                                  addToPlaylistController.playlists.length,
                              itemBuilder: (context, index) {
                                final playlist =
                                    addToPlaylistController.playlists[index];
                                final isMembershipLoaded =
                                    addToPlaylistController
                                        .isPlaylistMembershipLoaded(
                                          playlist.playlistId,
                                        );
                                final isMembershipLoading =
                                    addToPlaylistController
                                        .isPlaylistMembershipLoading(
                                          playlist.playlistId,
                                        );
                                final isDisabled =
                                    isMembershipLoaded &&
                                    addToPlaylistController.isPlaylistDisabled(
                                      playlist.playlistId,
                                      widget.songItems,
                                    );
                                final isAdding = addToPlaylistController
                                    .isPlaylistAdding(playlist.playlistId);
                                final canAdd =
                                    !isDisabled &&
                                    !isAdding &&
                                    !isMembershipLoading;
                                return Opacity(
                                  opacity: isDisabled ? 0.55 : 1,
                                  child: Material(
                                    type: MaterialType.transparency,
                                    child: ListTile(
                                      enabled: canAdd,
                                      leading: isAdding || isMembershipLoading
                                          ? const SizedBox.square(
                                              dimension: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Icon(
                                              isDisabled
                                                  ? Icons.check_circle
                                                  : Icons.add_circle_outline,
                                            ),
                                      title: Text(playlist.title),
                                      onTap: canAdd
                                          ? () async {
                                              final result =
                                                  await addToPlaylistController
                                                      .addSongsToPlaylist(
                                                        widget.songItems,
                                                        playlist.playlistId,
                                                      );
                                              if (!context.mounted) return;
                                              final message =
                                                  result ==
                                                      PlaylistAddStatus.added
                                                  ? "songAddedToPlaylistAlert"
                                                        .tr
                                                  : result ==
                                                        PlaylistAddStatus
                                                            .skipped
                                                  ? "songAlreadyExists".tr
                                                  : "errorOccurredAlert".tr;
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                snackbar(
                                                  context,
                                                  message,
                                                  size: SanckBarSize.MEDIUM,
                                                ),
                                              );
                                            }
                                          : null,
                                    ),
                                  ),
                                );
                              },
                            )
                          : Center(child: Text("noLibPlaylist".tr)),
                    ),
                  ),
                ),
              ],
            ),
            AnimatedBuilder(
              animation: addToPlaylistController,
              builder: (context, _) =>
                  (addToPlaylistController.additionInProgress.value &&
                      isPipedLinked)
                  ? const Positioned(
                      top: 60,
                      right: 8,
                      child: SizedBox(
                        height: 15,
                        width: 15,
                        child: CircularProgressIndicator(
                          backgroundColor: Colors.transparent,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class AddToPlaylistController extends ChangeNotifier {
  AddToPlaylistController({
    required PlaylistRepository playlistRepository,
    required PipedServices pipedServices,
  }) : _playlistRepository = playlistRepository,
       _pipedServices = pipedServices;

  final PlaylistRepository _playlistRepository;
  final PipedServices _pipedServices;
  final playlists = <Playlist>[];
  final playlistType = ValueNotifier("local");
  final additionInProgress = ValueNotifier(false);
  final playlistSongIds = <String, Set<String>>{};
  final addingPlaylistIds = <String>{};
  final loadingMembershipPlaylistIds = <String>{};
  List<Playlist> localPlaylists = [];
  List<Playlist> pipedPlaylists = [];

  Future<void> loadPlaylists() async {
    playlists
      ..clear()
      ..addAll(
        (await _playlistRepository.getPlaylists()).where(
          (playlist) => !playlist.isCloudPlaylist,
        ),
      );
    localPlaylists = playlists.toList();
    notifyListeners();
    final res = await _pipedServices.getAllPlaylists();
    if (res.code == 1) {
      pipedPlaylists = res.response
          .map(
            (item) => Playlist(
              title: item['name'],
              playlistId: item['id'],
              description: "Piped Playlist",
              thumbnailUrl: item['thumbnail'],
              isPipedPlaylist: true,
            ),
          )
          .whereType<Playlist>()
          .toList();
    }
    notifyListeners();
  }

  Future<void> changePlaylistType(String val) async {
    playlistType.value = val;
    playlists
      ..clear()
      ..addAll(val == "piped" ? pipedPlaylists : localPlaylists);
    notifyListeners();
  }

  bool isPlaylistAdding(String playlistId) {
    return addingPlaylistIds.contains(playlistId);
  }

  bool isPlaylistMembershipLoading(String playlistId) {
    return loadingMembershipPlaylistIds.contains(playlistId);
  }

  bool isPlaylistMembershipLoaded(String playlistId) {
    return playlistSongIds.containsKey(playlistId);
  }

  bool isPlaylistDisabled(String playlistId, List<MediaItem> songs) {
    return missingSongsForPlaylist(songs, playlistId).isEmpty;
  }

  List<MediaItem> missingSongsForPlaylist(
    List<MediaItem> songs,
    String playlistId,
  ) {
    final existingIds = playlistSongIds[playlistId] ?? <String>{};
    return songs.where((song) => !existingIds.contains(song.id)).toList();
  }

  void updatePlaylistMembership(String playlistId, Iterable<String> songIds) {
    playlistSongIds[playlistId] = songIds.toSet();
    notifyListeners();
  }

  void markSongsAddedToPlaylist(String playlistId, Iterable<MediaItem> songs) {
    final ids = {...playlistSongIds[playlistId] ?? <String>{}};
    ids.addAll(songs.map((song) => song.id));
    playlistSongIds[playlistId] = ids;
    notifyListeners();
  }

  void markSongsRemovedFromPlaylist(
    String playlistId,
    Iterable<MediaItem> songs,
  ) {
    final ids = playlistSongIds[playlistId];
    if (ids == null) return;
    final updatedIds = {...ids};
    updatedIds.removeAll(songs.map((song) => song.id));
    playlistSongIds[playlistId] = updatedIds;
    notifyListeners();
  }

  Future<PlaylistAddStatus> addSongsToPlaylist(
    List<MediaItem> songs,
    String playlistId,
  ) async {
    final selectedPlaylistType = playlistType.value;
    final membershipLoaded = await ensurePlaylistMembershipLoaded(
      playlistId,
      playlistTypeOverride: selectedPlaylistType,
    );
    if (!membershipLoaded) {
      return PlaylistAddStatus.failed;
    }
    final missingSongs = missingSongsForPlaylist(songs, playlistId);
    if (missingSongs.isEmpty) {
      return PlaylistAddStatus.skipped;
    }

    additionInProgress.value = true;
    addingPlaylistIds.add(playlistId);
    notifyListeners();
    try {
      if (selectedPlaylistType == "local") {
        final actuallyAddedSongs = await _addLocalMissingSongs(
          playlistId,
          missingSongs,
        );
        if (actuallyAddedSongs.isEmpty) return PlaylistAddStatus.skipped;
        markSongsAddedToPlaylist(playlistId, actuallyAddedSongs);
        return PlaylistAddStatus.added;
      } else {
        final videosId = missingSongs.map((e) => e.id).toList();
        final res = await _pipedServices.addToPlaylist(playlistId, videosId);
        if (res.code != 1) {
          return PlaylistAddStatus.failed;
        }
        markSongsAddedToPlaylist(playlistId, missingSongs);
        return PlaylistAddStatus.added;
      }
    } catch (e) {
      printWarning(
        "Failed to add songs to playlist $playlistId: $e",
        tag: "AddToPlaylist",
      );
      return PlaylistAddStatus.failed;
    } finally {
      addingPlaylistIds.remove(playlistId);
      additionInProgress.value = addingPlaylistIds.isNotEmpty;
      notifyListeners();
    }
  }

  Future<List<MediaItem>> _addLocalMissingSongs(
    String playlistId,
    List<MediaItem> missingSongs,
  ) async {
    final actuallyAddedSongs = <MediaItem>[];
    final existingIds = await _playlistRepository.getPlaylistSongIds(
      playlistId,
    );
    for (MediaItem element in missingSongs) {
      if (!existingIds.contains(element.id)) {
        actuallyAddedSongs.add(element);
      }
    }
    await _playlistRepository.addSongsToPlaylist(
      playlistId,
      actuallyAddedSongs,
    );
    updatePlaylistMembership(playlistId, {
      ...existingIds,
      ...actuallyAddedSongs.map((song) => song.id),
    });
    return actuallyAddedSongs;
  }

  Future<bool> ensurePlaylistMembershipLoaded(
    String playlistId, {
    String? playlistTypeOverride,
  }) async {
    if (playlistSongIds.containsKey(playlistId)) {
      return true;
    }
    if (loadingMembershipPlaylistIds.contains(playlistId)) {
      return false;
    }
    loadingMembershipPlaylistIds.add(playlistId);
    notifyListeners();
    try {
      if ((playlistTypeOverride ?? playlistType.value) == "local") {
        updatePlaylistMembership(
          playlistId,
          await _readLocalPlaylistSongIds(playlistId),
        );
      } else {
        final songs = await _pipedServices.getPlaylistSongs(playlistId);
        updatePlaylistMembership(playlistId, songs.map((song) => song.id));
      }
      return true;
    } catch (e) {
      printWarning(
        "Failed to load playlist membership for $playlistId: $e",
        tag: "AddToPlaylist",
      );
      return false;
    } finally {
      loadingMembershipPlaylistIds.remove(playlistId);
      notifyListeners();
    }
  }

  Future<Set<String>> _readLocalPlaylistSongIds(String playlistId) async {
    return _playlistRepository.getPlaylistSongIds(playlistId);
  }

  @override
  void dispose() {
    playlistType.dispose();
    additionInProgress.dispose();
    super.dispose();
  }
}
