import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/nav_parser.dart';

/// The watch panel's playlist id is what turns a tap into a queue of similar
/// songs — except it isn't: `pushSongToQueue` never reads it. It was still
/// sourced with `.first` over the entries that carry one, which throws
/// `StateError: No element` when none do. That throw escaped the whole of
/// `getWatchPlaylist`, so a response full of perfectly good tracks was
/// discarded and the tapped song was left alone in the queue, playing fine and
/// explaining nothing.
void main() {
  Map<String, dynamic> entry({String? playlistId}) => {
    'playlistPanelVideoRenderer': {
      'videoId': 'song-1',
      if (playlistId != null)
        'navigationEndpoint': {
          'watchEndpoint': {'playlistId': playlistId},
        },
    },
  };

  group('watch panel playlist id', () {
    test('entries without a playlist id yield null instead of throwing', () {
      expect(
        MusicServices.watchPanelPlaylistId([entry(), entry()]),
        isNull,
        reason: 'this is the throw that used to discard the whole queue',
      );
    });

    test('an empty panel yields null', () {
      expect(MusicServices.watchPanelPlaylistId([]), isNull);
    });

    test('the first entry carrying an id wins', () {
      expect(
        MusicServices.watchPanelPlaylistId([
          entry(),
          entry(playlistId: 'RDAMVMabc'),
          entry(playlistId: 'RDAMVMxyz'),
        ]),
        'RDAMVMabc',
      );
    });

    test('an unrecognised entry shape is skipped, not fatal', () {
      expect(
        MusicServices.watchPanelPlaylistId([
          'not a renderer',
          {'someOtherRenderer': {}},
          entry(playlistId: 'RDAMVMabc'),
        ]),
        'RDAMVMabc',
      );
    });
  });

  // The watch panel's lyrics (tab 1) and related (tab 2) browse ids. Neither is
  // read by the queue expansion, but both are resolved upstream of every track,
  // so anything that throws here discards the whole watch queue and leaves the
  // tapped song playing alone.
  group('watch panel tab browse id', () {
    Map<String, dynamic> renderer(List<Map<String, dynamic>> tabs) => {
      'tabs': tabs,
    };

    Map<String, dynamic> tab(Map<String, dynamic> tabRenderer) => {
      'tabRenderer': tabRenderer,
    };

    test('a selectable tab with no endpoint yields null instead of throwing', () {
      // The exact shape observed on Windows: the tab is not marked
      // `unselectable`, and has no `endpoint` at all. Indexing straight through
      // it raised `NoSuchMethodError: '[]' called on null` for "browseEndpoint",
      // which escaped getWatchPlaylist and threw away every parsed track.
      final watchNext = renderer([
        tab({'title': 'Up next'}),
        tab({'title': 'Lyrics'}),
      ]);

      expect(getTabBrowseId(watchNext, 1), isNull);
    });

    test('an unselectable tab yields null', () {
      final watchNext = renderer([
        tab({'title': 'Up next'}),
        tab({
          'title': 'Lyrics',
          'unselectable': true,
          'endpoint': {
            'browseEndpoint': {'browseId': 'MPLYt-should-be-ignored'},
          },
        }),
      ]);

      expect(getTabBrowseId(watchNext, 1), isNull);
    });

    test('a well-formed tab yields its browse id', () {
      final watchNext = renderer([
        tab({'title': 'Up next'}),
        tab({
          'title': 'Lyrics',
          'endpoint': {
            'browseEndpoint': {'browseId': 'MPLYt_lyrics_id'},
          },
        }),
        tab({
          'title': 'Related',
          'endpoint': {
            'browseEndpoint': {'browseId': 'MPTRt_related_id'},
          },
        }),
      ]);

      expect(getTabBrowseId(watchNext, 1), 'MPLYt_lyrics_id');
      expect(getTabBrowseId(watchNext, 2), 'MPTRt_related_id');
    });

    test('a missing tab index yields null', () {
      expect(getTabBrowseId(renderer([tab({'title': 'Up next'})]), 2), isNull);
    });

    test('a null or malformed renderer yields null', () {
      expect(getTabBrowseId(null, 1), isNull);
      expect(getTabBrowseId(<String, dynamic>{}, 1), isNull);
      expect(getTabBrowseId({'tabs': 'not a list'}, 1), isNull);
      expect(getTabBrowseId({'tabs': <dynamic>[]}, 1), isNull);
      expect(getTabBrowseId(renderer([tab({}), tab({})]), 1), isNull);
    });
  });
}
