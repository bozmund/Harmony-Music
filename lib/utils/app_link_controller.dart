import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:harmonymusic/utils/get_localization.dart';

import '../app/navigation/app_navigator.dart';
import '../models/playing_from.dart';

import '/ui/widgets/song_info_bottom_sheet.dart';
import '/utils/helper.dart';
import '../ui/widgets/loader.dart';
import '/services/app_contracts.dart';
import '/ui/player/player_controller.dart';
import '../ui/navigator.dart';
import '../ui/widgets/snackbar.dart';

class AppLinksController with ProcessLink {
  AppLinksController({
    required MusicServiceContract musicService,
    required PlayerController playerController,
  }) : _musicService = musicService,
       _playerController = playerController {
    unawaited(initDeepLinks());
  }

  final MusicServiceContract _musicService;
  final PlayerController _playerController;
  @override
  MusicServiceContract get musicService => _musicService;
  @override
  PlayerController get playerController => _playerController;

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  Future<void> initDeepLinks() async {
    _appLinks = AppLinks();

    // Check initial link if app was in cold state (terminated)
    final appLink = await _appLinks.getInitialLink();
    if (appLink != null) {
      await filterLinks(appLink);
    }

    // Handle link when app is in warm state (front or background)
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) async {
      await filterLinks(uri);
    });
  }

  void dispose() {
    unawaited(_linkSubscription?.cancel());
  }
}

mixin ProcessLink {
  MusicServiceContract get musicService;
  PlayerController get playerController;

  Future<void> filterLinks(Uri uri) async {
    if (playerController.playerPanelController.isPanelOpen) {
      await playerController.playerPanelController.close();
    }

    if (SongInfoControllerRegistry.isOpen) {
      final context = AppNavigator.context;
      if (context != null) {
        Navigator.of(context).pop();
      }
    }

    if (uri.host == "youtube.com" ||
        uri.host == "music.youtube.com" ||
        uri.host == "youtu.be" ||
        uri.host == "www.youtube.com" ||
        uri.host == "m.youtube.com") {
      printINFO(
        "pathsegmet: ${uri.pathSegments} params:${uri.queryParameters}",
      );
      if (uri.pathSegments[0] == "playlist" &&
          uri.queryParameters.containsKey("list")) {
        final browseId = uri.queryParameters['list'];
        await openPlaylistOrAlbum(browseId!);
      } else if (uri.pathSegments[0] == "shorts") {
        _showSnackBar("notaSongVideo".tr);
      } else if (uri.pathSegments[0] == "watch") {
        final songId = uri.queryParameters['v'];
        await playSong(songId!);
      } else if (uri.pathSegments[0] == "channel") {
        final browseId = uri.pathSegments[1];
        await openArtist(browseId);
      } else if ((uri.queryParameters.isEmpty || uri.query.contains("si=")) &&
          uri.host == "youtu.be") {
        final songId = uri.pathSegments[0];
        await playSong(songId);
      }
    } else {
      _showSnackBar("notaValidLink".tr);
    }
  }

  Future<void> openPlaylistOrAlbum(String browseId) async {
    final navigator = ScreenNavigationSetup.navigatorKey.currentState;
    if (navigator == null) return;
    if (browseId.contains("OLAK5uy")) {
      await navigator.pushNamed(
        ScreenNavigationSetup.albumScreen,
        arguments: (null, browseId),
      );
    } else {
      await navigator.pushNamed(
        ScreenNavigationSetup.playlistScreen,
        arguments: [null, browseId],
      );
    }
  }

  Future<void> openArtist(String channelId) async {
    final navigator = ScreenNavigationSetup.navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.pushNamed(
      ScreenNavigationSetup.artistScreen,
      arguments: [true, channelId],
    );
  }

  Future<void> playSong(String songId) async {
    final context = AppNavigator.context;
    if (context == null) return;
    await showDialog(
      context: context,
      builder: (context) =>
          const Center(child: LoadingIndicator(strokeWidth: 5)),
      barrierDismissible: false,
    );
    final result = await musicService.getSongWithId(songId);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
    if (result[0]) {
      await playerController.playPlayListSong(
        List.from(result[1]),
        0,
        playFrom: PlayingFrom(type: PlayingFromType.SELECTION),
      );
    } else {
      _showSnackBar("notaSongVideo".tr);
    }
  }

  void _showSnackBar(String message) {
    final context = AppNavigator.context;
    if (context == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(snackbar(context, message, size: SanckBarSize.MEDIUM));
  }
}
