import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Spotify import dialog source checks', () {
    late String source;

    setUpAll(() {
      source = File(
        'lib/ui/widgets/import_spotify_playlist_dialog.dart',
      ).readAsStringSync();
    });

    test('explains how to request Spotify account data', () {
      expect(source, contains("request your account data"));
      expect(source, contains("download the ZIP file"));
      expect(source, contains("Spotify Playlist JSON or Library"));
      expect(source, contains("JSON file if you already extracted the ZIP"));
    });

    test('keeps the dialog scrollable on small screens', () {
      expect(source, contains("SingleChildScrollView"));
      expect(source, contains("MediaQuery.sizeOf(context).height * 0.82"));
    });

    test('reads playlist controller from Riverpod instead of registry', () {
      expect(source, contains("ConsumerStatefulWidget"));
      expect(source, contains("ref.read(libraryPlaylistsControllerProvider)"));
      expect(
        source,
        isNot(contains("LibraryPlaylistsControllerRegistry.current!")),
      );
    });

    test('opens Spotify privacy page through platform service', () {
      expect(
        source,
        contains("https://www.spotify.com/account/privacy/"),
      );
      expect(source, contains("Open Spotify data page"));
      expect(source, contains("AppPlatformService.openUrl"));
    });

    test('accepts ZIP and JSON files', () {
      expect(source, contains("extensions: ['zip', 'json']"));
      expect(source, contains("ZipDecoder().decodeBytes"));
      expect(source, contains("fileName.endsWith('.json')"));
    });

    test('ZIP import ignores unsupported Spotify JSON entries', () {
      expect(source, contains("_tryParseSpotifyJson"));
      expect(source, contains("_tryDecodeSpotifyArchiveJson"));
      expect(source, contains("strict: false"));
      expect(source, contains("continue;"));
      expect(source, contains("on FormatException"));
      expect(source, contains("on SpotifyPlaylistImportException"));
    });

    test('parses liked songs and direct playlist item maps', () {
      expect(source, contains("Spotify Liked Songs"));
      expect(source, contains("decoded['tracks']"));
      expect(source, contains("item['track'] is Map"));
      expect(source, contains(": item"));
    });
  });
}
