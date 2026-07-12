import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/l10n/l10n.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '../../app/providers/repository_providers.dart';
import '../../app/providers/service_providers.dart';
import '../../domain/repositories/playlist_repository.dart';
import '../../services/piped_service.dart';
import '../../utils/helper.dart';
import '../screens/Library/library_controller.dart';
import '/ui/widgets/create_playlist_dialog.dart';
import '../../models/playlist.dart';
import 'awaitable_button.dart';
import 'common_dialog_widget.dart';
import 'snackbar.dart';

enum PlaylistAddStatus { added, skipped, failed }

enum PlaylistRemoveStatus { removed, skipped, failed }

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

  String _addResultMessage(PlaylistAddStatus result) {
    switch (result) {
      case PlaylistAddStatus.added:
        return context.l10n.songAddedToPlaylistAlert;
      case PlaylistAddStatus.skipped:
        return context.l10n.songAlreadyExists;
      case PlaylistAddStatus.failed:
        return context.l10n.errorOccurredAlert;
    }
  }

  String _removeResultMessage(PlaylistRemoveStatus result) {
    switch (result) {
      case PlaylistRemoveStatus.removed:
        return context.l10n.songRemovedFromPlaylistAlert;
      case PlaylistRemoveStatus.skipped:
        return context.l10n.songAlreadyExists;
      case PlaylistRemoveStatus.failed:
        return context.l10n.errorOccurredAlert;
    }
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
                              context.l10n.createNewPlaylist,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      AwaitableIconButton(
                        tooltip: context.l10n.createNewPlaylist,
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
                        tooltip: context.l10n.close,
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
                                  Text(context.l10n.piped),
                                ],
                              ),
                              const SizedBox(width: 15),
                              Row(
                                children: [
                                  const Radio<String>(value: 'local'),
                                  Text(context.l10n.local),
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
                                // Membership known and every selected song is
                                // already in this playlist: tapping now
                                // removes them instead of being a no-op.
                                final containsAll =
                                    isMembershipLoaded &&
                                    addToPlaylistController
                                        .playlistContainsAllSongs(
                                          playlist.playlistId,
                                          widget.songItems,
                                        );
                                final isBusy = addToPlaylistController
                                    .isPlaylistAdding(playlist.playlistId);
                                final canInteract =
                                    !isBusy && !isMembershipLoading;
                                return Material(
                                  type: MaterialType.transparency,
                                  child: ListTile(
                                    enabled: canInteract,
                                    leading: isBusy || isMembershipLoading
                                        ? const SizedBox.square(
                                            dimension: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Icon(
                                            containsAll
                                                ? Icons.check_circle
                                                : Icons.add_circle_outline,
                                          ),
                                    title: Text(playlist.title),
                                    subtitle: containsAll
                                        ? Text(
                                            context
                                                .l10n
                                                .tapToRemoveFromPlaylist,
                                          )
                                        : null,
                                    onTap: canInteract
                                        ? () async {
                                            final message = containsAll
                                                ? _removeResultMessage(
                                                    await addToPlaylistController
                                                        .removeSongsFromPlaylist(
                                                          widget.songItems,
                                                          playlist.playlistId,
                                                        ),
                                                  )
                                                : _addResultMessage(
                                                    await addToPlaylistController
                                                        .addSongsToPlaylist(
                                                          widget.songItems,
                                                          playlist.playlistId,
                                                        ),
                                                  );
                                            if (!context.mounted) return;
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
                                );
                              },
                            )
                          : Center(child: Text(context.l10n.noLibPlaylist)),
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
    // Resolve local membership up front so each row can immediately show
    // whether the song is already in the playlist (and offer to remove it).
    // Local reads are cheap Hive lookups; piped stays lazy so we don't fire
    // a network request per playlist just to open the dialog. Kicked off
    // here and awaited at the end so it runs alongside the piped fetch.
    final localMembershipsFuture = _preloadLocalMemberships();
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
    await localMembershipsFuture;
  }

  Future<void> _preloadLocalMemberships() async {
    await Future.wait(
      localPlaylists.map(
        (playlist) => ensurePlaylistMembershipLoaded(
          playlist.playlistId,
          playlistTypeOverride: "local",
        ),
      ),
    );
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

  /// True when every one of [songs] is already in the playlist. Such a
  /// playlist is not disabled — tapping it removes the songs (toggle).
  bool playlistContainsAllSongs(String playlistId, List<MediaItem> songs) {
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
        // Playlist tiles derive artwork from their first song; recompute
        // since this add happened outside the playlist screen.
        unawaited(
          LibraryPlaylistsControllerRegistry.current
                  ?.recomputeLocalPlaylistThumb(playlistId) ??
              Future.value(),
        );
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

  /// Removes whichever of [songs] are currently in the playlist. Reuses the
  /// same in-flight tracking (`addingPlaylistIds` / `additionInProgress`) as
  /// adding, so the row shows a spinner and stays locked during removal too.
  Future<PlaylistRemoveStatus> removeSongsFromPlaylist(
    List<MediaItem> songs,
    String playlistId,
  ) async {
    final selectedPlaylistType = playlistType.value;
    final membershipLoaded = await ensurePlaylistMembershipLoaded(
      playlistId,
      playlistTypeOverride: selectedPlaylistType,
    );
    if (!membershipLoaded) {
      return PlaylistRemoveStatus.failed;
    }
    final existingIds = playlistSongIds[playlistId] ?? <String>{};
    final songsToRemove = songs
        .where((song) => existingIds.contains(song.id))
        .toList();
    if (songsToRemove.isEmpty) {
      return PlaylistRemoveStatus.skipped;
    }

    additionInProgress.value = true;
    addingPlaylistIds.add(playlistId);
    notifyListeners();
    try {
      if (selectedPlaylistType == "local") {
        await _playlistRepository.removeSongsFromPlaylist(
          playlistId,
          songsToRemove,
        );
        markSongsRemovedFromPlaylist(playlistId, songsToRemove);
        // Keep tile artwork in sync when the first song may have changed.
        unawaited(
          LibraryPlaylistsControllerRegistry.current
                  ?.recomputeLocalPlaylistThumb(playlistId) ??
              Future.value(),
        );
        return PlaylistRemoveStatus.removed;
      } else {
        final removed = await _removePipedSongs(playlistId, songsToRemove);
        if (removed.isEmpty) return PlaylistRemoveStatus.failed;
        markSongsRemovedFromPlaylist(playlistId, removed);
        return PlaylistRemoveStatus.removed;
      }
    } catch (e) {
      printWarning(
        "Failed to remove songs from playlist $playlistId: $e",
        tag: "AddToPlaylist",
      );
      return PlaylistRemoveStatus.failed;
    } finally {
      addingPlaylistIds.remove(playlistId);
      additionInProgress.value = addingPlaylistIds.isNotEmpty;
      notifyListeners();
    }
  }

  /// Piped removal is index-based, so map the target song ids to their
  /// current positions and delete highest-index first — that keeps the
  /// lower indices valid as we go. Returns the songs actually removed.
  Future<List<MediaItem>> _removePipedSongs(
    String playlistId,
    List<MediaItem> songsToRemove,
  ) async {
    final currentSongs = await _pipedServices.getPlaylistSongs(playlistId);
    final removeIds = songsToRemove.map((song) => song.id).toSet();
    final indices = <int>[];
    for (var i = 0; i < currentSongs.length; i++) {
      if (removeIds.contains(currentSongs[i].id)) indices.add(i);
    }
    indices.sort((a, b) => b.compareTo(a));

    final removed = <MediaItem>[];
    for (final index in indices) {
      final res = await _pipedServices.removeFromPlaylist(playlistId, index);
      if (res.code == 1) {
        removed.add(currentSongs[index]);
      }
    }
    return removed;
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
