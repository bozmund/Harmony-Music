import 'package:flutter/material.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/artist.dart';

import 'package:harmonymusic/ui/screens/Artists/artist_screen.dart';
import 'package:harmonymusic/ui/screens/Home/home_screen.dart';

import 'screens/Album/album_screen.dart';
import 'screens/Playlist/playlist_screen.dart';
import 'screens/Search/search_result_screen.dart';
import 'screens/Search/search_screen.dart';

class ScreenNavigationSetup {
  ScreenNavigationSetup._();

  static const id = 1;
  static final navigatorKey = GlobalKey<NavigatorState>();
  static const homeScreen = '/homeScreen';
  static const searchScreen = '/searchScreen';
  static const searchResultScreen = '/searchResultScreen';
  static const artistScreen = '/artistScreen';
  static const albumScreen = '/albumScreen';
  static const playlistScreen = '/playlistScreen';
}

class ScreenNavigation extends StatelessWidget {
  const ScreenNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: ScreenNavigationSetup.navigatorKey,
      initialRoute: '/homeScreen',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case ScreenNavigationSetup.homeScreen:
            return MaterialPageRoute(
              builder: (context) => const HomeScreen(),
              settings: settings,
            );

          case ScreenNavigationSetup.albumScreen:
            final id = (settings.arguments as (Album?, String)).$2;
            return MaterialPageRoute(
              builder: (context) => AlbumScreen(key: Key(id)),
              settings: settings,
            );

          case ScreenNavigationSetup.playlistScreen:
            final id = (settings.arguments as List)[1] as String;
            return MaterialPageRoute(
              builder: (context) => PlaylistScreen(key: Key(id)),
              settings: settings,
            );

          case ScreenNavigationSetup.searchScreen:
            return MaterialPageRoute(
              builder: (context) => const SearchScreen(),
              settings: settings,
            );

          case ScreenNavigationSetup.searchResultScreen:
            return MaterialPageRoute(
              builder: (context) => const SearchResultScreen(),
              settings: settings,
            );

          case ScreenNavigationSetup.artistScreen:
            final args = settings.arguments as List;
            final id = args[0] ? args[1] : (args[1] as Artist).browseId;
            return MaterialPageRoute(
              builder: (context) => ArtistScreen(key: Key(id)),
              settings: settings,
            );

          default:
            return null;
        }
      },
    );
  }
}
