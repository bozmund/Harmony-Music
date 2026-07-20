import 'package:flutter/material.dart';
import 'package:harmonymusic/l10n/l10n.dart';

import '/models/playlist.dart';
import '/services/constant.dart';
import '../navigator.dart';
import 'image_widget.dart';

class ContentListItem extends StatelessWidget {
  const ContentListItem({
    super.key,
    required this.content,
    this.isLibraryItem = false,
  });

  ///content will be of Type class Album or Playlist
  final dynamic content;
  final bool isLibraryItem;

  @override
  Widget build(BuildContext context) {
    final isAlbum = content.runtimeType.toString() == "Album";
    final isBuiltInLibraryPlaylist =
        !isAlbum &&
        !(content.isCloudPlaylist as bool) &&
        (content.playlistId == BoxNames.libRP ||
            content.playlistId == BoxNames.libFav ||
            content.playlistId == BoxNames.libFavNotDownloaded ||
            content.playlistId == BoxNames.libImportDuplicates ||
            content.playlistId == BoxNames.libImportReview ||
            content.playlistId == BoxNames.songsCache ||
            content.playlistId == BoxNames.songDownloads);
    // A built-in playlist shows its first song's artwork once it has songs
    // (thumbnailUrl derived in LibraryPlaylistsController); empty built-ins
    // keep the original icon look.
    final builtInHasArt =
        isBuiltInLibraryPlaylist &&
        content.thumbnailUrl != Playlist.thumbPlaceholderUrl;
    final title = isAlbum || !isLibraryItem
        ? content.title as String
        : switch (content.playlistId as String) {
            BoxNames.libRP => context.l10n.recentlyPlayed,
            BoxNames.libFav => context.l10n.favorites,
            BoxNames.libFavNotDownloaded => context.l10n.likedNotDownloaded,
            BoxNames.libImportDuplicates => context.l10n.importConflicts,
            BoxNames.libImportReview => context.l10n.importNeedsReview,
            BoxNames.songsCache => context.l10n.cachedOrOffline,
            BoxNames.songDownloads => context.l10n.downloads,
            _ => content.title as String,
          };
    return InkWell(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: () async {
        final navigator = ScreenNavigationSetup.navigatorKey.currentState;
        if (navigator == null) return;
        if (isAlbum) {
          await navigator.pushNamed(
            ScreenNavigationSetup.albumScreen,
            arguments: (content, content.browseId),
          );
          return;
        }
        await navigator.pushNamed(
          ScreenNavigationSetup.playlistScreen,
          arguments: [content, content.playlistId],
        );
      },
      child: Container(
        width: 130,
        height: 180,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            isAlbum
                ? ImageWidget(size: 120, album: content)
                : !isBuiltInLibraryPlaylist || builtInHasArt
                ? SizedBox.square(
                    dimension: 120,
                    child: Stack(
                      children: [
                        ImageWidget(size: 120, playlist: content),
                        if (content.isPipedPlaylist)
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Container(
                                height: 18,
                                width: 18,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(5),
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.secondary,
                                ),
                                child: Center(
                                  child: Text(
                                    "P",
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium!
                                        .copyWith(fontSize: 14),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (!content.isCloudPlaylist)
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Container(
                                height: 18,
                                width: 18,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(5),
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.secondary,
                                ),
                                child: Center(
                                  child: Text(
                                    "L",
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium!
                                        .copyWith(fontSize: 14),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                : Container(
                    height: 120,
                    width: 120,
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColorLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Icon(
                        content.playlistId == BoxNames.libRP
                            ? Icons.history
                            : content.playlistId == BoxNames.libFav
                            ? Icons.favorite
                            : content.playlistId == BoxNames.libFavNotDownloaded
                            ? Icons.favorite_border
                            : content.playlistId == BoxNames.libImportDuplicates
                            ? Icons.playlist_remove
                            : content.playlistId == BoxNames.libImportReview
                            ? Icons.rule
                            : content.playlistId == BoxNames.songsCache
                            ? Icons.flight
                            : Icons.download,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  ),
            const SizedBox(height: 5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    // overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    isAlbum
                        ? isLibraryItem
                              ? ""
                              : "${content.artists[0]['name'] ?? ""} | ${content.year ?? ""}"
                        : isLibraryItem
                        ? ""
                        : content.description ?? "",
                    maxLines: 1,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
