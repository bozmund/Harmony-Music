import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level, matching the convention in this directory: the real widget
/// needs a Navigator, a ScaffoldMessenger, Hive-backed repositories and a
/// downloader, none of which exist under `flutter test`.
void main() {
  final source = File('lib/ui/widgets/song_download_btn.dart').readAsStringSync();

  test('the already-cached pop cannot empty the navigation stack', () {
    // The pop is there to dismiss the song-info sheet this button normally
    // lives in. From the player there is no sheet, so it popped the last page
    // instead: go_router asserts `currentConfiguration.isNotEmpty` and the
    // window renders black. Reported on Windows, where the player's download
    // button is a click away.
    final at = source.indexOf('containsCachedSong');
    expect(at, greaterThan(-1));
    final branch = source.substring(at, source.indexOf('} else {', at));

    expect(
      branch,
      contains('!calledFromPlayer'),
      reason: 'the player has no sheet of its own to close',
    );
    expect(
      branch,
      contains('canPop()'),
      reason: 'never pop a stack that has nothing left on it',
    );
    // The messenger has to be captured before the pop, or the lookup runs
    // against a context that may no longer sit under one.
    expect(
      branch.indexOf('ScaffoldMessenger.of(context)'),
      lessThan(branch.indexOf('navigator.pop()')),
    );
  });

  test('the player call site still declares itself as such', () {
    // The guard above is only correct while this stays true. Matched without
    // depending on indentation, which says nothing about behaviour.
    final player = File(
      'lib/ui/player/components/mini_player.dart',
    ).readAsStringSync();
    final at = player.indexOf('SongDownloadButton(');
    expect(at, greaterThan(-1), reason: 'the player still hosts the button');
    expect(
      player.substring(at, at + 200),
      contains('calledFromPlayer: true'),
      reason: 'mini_player must keep declaring it has no sheet to close',
    );
  });
}
