import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';

void main() {
  group('player controller queue ordering', () {
    late String source;

    setUp(() {
      source = File('lib/ui/player/player_controller.dart').readAsStringSync();
    });

    test(
      'normal song taps start playback before background queue update completes',
      () {
        final block = _methodBlock(source, 'pushSongToQueue');

        final queueUpdateIndex = block.indexOf(
          'final queueUpdate = Future.delayed',
        );
        final backgroundUpdateIndex = block.indexOf('queueUpdate.then');
        final panelCheckIndex = block.indexOf(
          'unawaited(_playerPanelCheck());',
        );
        final setSourceIndex = block.indexOf(
          '_playbackCommands.setSourceAndPlay',
        );

        expect(queueUpdateIndex, isNot(-1));
        expect(backgroundUpdateIndex, isNot(-1));
        expect(panelCheckIndex, isNot(-1));
        expect(setSourceIndex, isNot(-1));
        expect(queueUpdateIndex, lessThan(backgroundUpdateIndex));
        expect(backgroundUpdateIndex, lessThan(setSourceIndex));
        expect(panelCheckIndex, lessThan(setSourceIndex));
      },
    );

    test('playlist-id playback waits for queue update before playByIndex', () {
      final block = _methodBlock(source, 'pushSongToQueue');
      final playlistBranchIndex = block.indexOf('if (playlistId != null)');
      final awaitQueueUpdateIndex = block.indexOf(
        'await queueUpdate;',
        playlistBranchIndex,
      );
      final playByIndexIndex = block.indexOf(
        '_playbackCommands.playByIndex',
        awaitQueueUpdateIndex,
      );

      expect(playlistBranchIndex, isNot(-1));
      expect(awaitQueueUpdateIndex, isNot(-1));
      expect(playByIndexIndex, isNot(-1));
      expect(awaitQueueUpdateIndex, lessThan(playByIndexIndex));
    });

    test('playlist playback updates queue before playByIndex', () {
      final block = _methodBlock(source, 'playPlayListSong');
      final panelIndex = block.indexOf('await _playerPanelCheck();');
      final updateQueueIndex = block.indexOf(
        'await _playbackCommands.updateQueue',
      );
      final shuffleIndex = block.indexOf(
        'await _playbackCommands.shuffleFromIndex',
      );
      final playByIndexIndex = block.indexOf('_playbackCommands.playByIndex');

      expect(panelIndex, isNot(-1));
      expect(updateQueueIndex, isNot(-1));
      expect(shuffleIndex, isNot(-1));
      expect(playByIndexIndex, isNot(-1));
      expect(panelIndex, lessThan(updateQueueIndex));
      expect(updateQueueIndex, lessThan(playByIndexIndex));
      expect(shuffleIndex, lessThan(playByIndexIndex));
    });

    test('enqueue into an empty queue starts playback', () {
      final block = _methodBlock(source, 'enqueueSong');

      expect(block, contains('if (currentQueue.isEmpty)'));
      expect(block, contains('await playPlayListSong([mediaItem], 0);'));
    });

    test('transport request methods are fire-and-forget wrappers', () {
      expect(
        _methodBlock(source, 'requestPlay'),
        contains('_runPlaybackCommand'),
      );
      expect(
        _methodBlock(source, 'requestPause'),
        contains('_runPlaybackCommand'),
      );
      expect(
        _methodBlock(source, 'requestPlayPause'),
        contains('_runPlaybackCommand'),
      );
      expect(
        _methodBlock(source, 'requestPrev'),
        contains('_runPlaybackCommand'),
      );
      expect(
        _methodBlock(source, 'requestNext'),
        contains('_runPlaybackCommand'),
      );
      expect(
        _methodBlock(source, 'requestSeek'),
        contains('_runPlaybackCommand'),
      );
    });

    test('playback commands are delegated through command service', () {
      expect(
        source,
        contains('required PlaybackCommandService playbackCommands'),
      );
      expect(
        source,
        contains('final PlaybackCommandService _playbackCommands;'),
      );
      expect(source, contains('_playbackCommands.play()'));
      expect(source, contains('_playbackCommands.pause()'));
      expect(source, contains('_playbackCommands.toggleShuffle('));
      expect(source, contains('_playbackCommands.playByIndex'));
    });

    test('playback command runner intentionally discards command futures', () {
      final block = _methodBlock(source, '_runPlaybackCommand');

      expect(block, contains('unawaited('));
      expect(block, contains('_playbackCommand'));
    });

    test('display queue keeps first song first when current index is zero', () {
      final queue = [_song('a'), _song('b'), _song('c')];

      expect(PlayerController.displayQueueFor(queue, 0), queue);
    });

    test('display queue rotates current song to the first row', () {
      final queue = [_song('a'), _song('b'), _song('c'), _song('d')];

      final displayQueue = PlayerController.displayQueueFor(queue, 2);

      expect(displayQueue.map((song) => song.id), ['c', 'd', 'a', 'b']);
    });

    test('display queue falls back to real order for invalid index', () {
      final queue = [_song('a'), _song('b'), _song('c')];

      final displayQueue = PlayerController.displayQueueFor(queue, 99);

      expect(displayQueue.map((song) => song.id), ['a', 'b', 'c']);
    });

    test('display reorder maps back while preserving current real index', () {
      final queue = [_song('a'), _song('b'), _song('c'), _song('d')];

      final reordered = PlayerController.realQueueAfterDisplayReorder(
        queue: queue,
        currentIndex: 2,
        oldDisplayIndex: 2,
        newDisplayIndex: 1,
      );

      expect(reordered.map((song) => song.id), ['d', 'b', 'c', 'a']);
      expect(reordered[2].id, 'c');
      expect(PlayerController.displayQueueFor(reordered, 2).first.id, 'c');
    });

    test('playback wake lock is tied to player state transitions', () {
      final listenerBlock = _methodBlock(
        source,
        '_listenForChangesInPlayerState',
      );
      final disposeBlock = _methodBlock(source, 'dispose');

      expect(listenerBlock, contains('_setPlaybackWakeLock'));
      expect(listenerBlock, contains('AudioProcessingState.completed'));
      expect(listenerBlock, contains('AudioProcessingState.error'));
      expect(disposeBlock, contains('_setPlaybackWakeLock(false)'));
    });

    test('completion state does not race audio handler queue advancement', () {
      final listenerBlock = _methodBlock(
        source,
        '_listenForChangesInPlayerState',
      );

      expect(listenerBlock, contains('AudioProcessingState.completed'));
      expect(listenerBlock, isNot(contains('_playbackCommands.seek')));
      expect(listenerBlock, isNot(contains('_playbackCommands.pause')));
    });

    test('source handoff shows loading button until new source starts', () {
      final playerStateBlock = _methodBlock(
        source,
        '_listenForChangesInPlayerState',
      );
      final durationBlock = _methodBlock(source, '_listenForChangesInDuration');
      final bufferedBlock = _methodBlock(
        source,
        '_listenForChangesInBufferedPosition',
      );
      final readyStartBlock = _methodBlock(source, '_isReadySourceStart');

      expect(playerStateBlock, contains('_isWaitingForCurrentSourceStart'));
      expect(playerStateBlock, contains('_isReadySourceStart(playerState)'));
      expect(
        readyStartBlock,
        contains('_isSourceStartPosition(playbackState.updatePosition)'),
      );
      expect(
        playerStateBlock,
        contains('_setButtonState(PlayButtonState.loading)'),
      );
      expect(durationBlock, contains('_beginPendingSourceStart(mediaItem.id)'));
      expect(
        bufferedBlock,
        contains('_setButtonState(PlayButtonState.playing)'),
      );
    });

    test('media item listener only clears lyrics when song changes', () {
      final block = _methodBlock(source, '_listenForChangesInDuration');

      expect(block, contains('final previousSongId = currentSong.value?.id;'));
      expect(
        block,
        contains('final isSameSong = previousSongId == mediaItem.id;'),
      );
      expect(block, contains('if (!isSameSong)'));
      expect(block, contains('_clearLyricsForSongChange();'));
    });

    test(
      'song changes reset progress without mixing old position and new total',
      () {
        final block = _methodBlock(source, '_listenForChangesInDuration');

        expect(source, contains('String? _pendingPlaybackStartSongId;'));
        expect(block, contains('_beginPendingSourceStart(mediaItem.id);'));
        expect(block, contains('val.current = isSameSong'));
        expect(block, contains(': Duration.zero;'));
        expect(
          block,
          contains('_clampProgressPosition(val.current, val.total)'),
        );
        expect(block, isNot(contains('val.current = oldState.current;')));
      },
    );

    test('stale position ticks are ignored until new source starts', () {
      final positionBlock = _methodBlock(source, '_listenForChangesInPosition');
      final bufferedBlock = _methodBlock(
        source,
        '_listenForChangesInBufferedPosition',
      );
      final readyStartBlock = _methodBlock(source, '_isReadySourceStart');
      final clampBlock = _methodBlock(source, '_clampProgressPosition');

      expect(positionBlock, contains('if (_isWaitingForCurrentSourceStart)'));
      expect(positionBlock, contains('_isReadySourceStart(playbackState)'));
      expect(positionBlock, contains('_isSourceStartPosition(position)'));
      expect(positionBlock, contains('_clampProgressPosition(position'));
      expect(readyStartBlock, contains('AudioProcessingState.ready'));
      expect(readyStartBlock, contains('playbackState.playing'));
      expect(
        readyStartBlock,
        contains('_isSourceStartPosition(playbackState.updatePosition)'),
      );
      expect(bufferedBlock, contains('_isReadySourceStart(playbackState)'));
      expect(
        bufferedBlock,
        contains(
          'if (_isWaitingForCurrentSourceStart && !startedPendingSource) return;',
        ),
      );
      expect(bufferedBlock, isNot(contains('val.current = oldState.current;')));
      expect(clampBlock, contains('position > total'));
      expect(clampBlock, contains('return total;'));
    });

    test('same-song replay preserves visible lyrics state', () {
      final block = _methodBlock(source, '_listenForChangesInDuration');
      final clearIndex = block.indexOf('_clearLyricsForSongChange();');
      final currentSongUpdateIndex = block.indexOf(
        'currentSong.value = mediaItem;',
      );

      expect(clearIndex, isNot(-1));
      expect(currentSongUpdateIndex, isNot(-1));
      expect(block, isNot(contains('showLyricsFlag.value = false;')));
      expect(currentSongUpdateIndex, lessThan(clearIndex));
    });

    test('showLyrics guards against stale async results', () {
      final block = _methodBlock(source, 'showLyrics');

      expect(block, contains('final songId = song.id;'));
      expect(block, contains('final generation = ++_lyricsLoadGeneration;'));
      expect(block, contains('_isCurrentLyricsRequest(songId, generation)'));
      expect(block, contains('finally'));
    });

    test('synced lyric controller ignores empty and NA lyrics', () {
      final block = _methodBlock(source, 'updateSyncedLyricsController');

      expect(
        block,
        contains('if (syncedLyrics.isEmpty || syncedLyrics == "NA") return;'),
      );
      expect(block, contains('lyricController.loadLyric(syncedLyrics);'));
    });

    test('song changes reset loaded lyrics and pending requests', () {
      final block = _methodBlock(source, '_clearLyricsForSongChange');

      expect(block, contains('_lyricsLoadGeneration++;'));
      expect(block, contains('_loadedSyncedLyrics = null;'));
      expect(block, contains('showLyricsFlag.value = false;'));
      expect(block, contains('isLyricsLoading.value = false;'));
    });

    test('observable player state bubbles to parent listeners', () {
      final block = _methodBlock(source, '_bindObservableState');

      expect(block, contains('watchList(currentQueue);'));
      expect(block, contains('watchValue(currentSong);'));
      expect(block, contains('watchValue(playerPanelMinHeight);'));
      expect(block, contains('watchValue(buttonState);'));
      expect(block, contains('watchMap(lyrics);'));
      expect(block, contains('_notifyPlayerChanged()'));
    });

    test('high-frequency progress updates do not repaint whole player', () {
      final bindingBlock = _methodBlock(source, '_bindObservableState');
      final positionBlock = _methodBlock(source, '_listenForChangesInPosition');
      final bufferedBlock = _methodBlock(
        source,
        '_listenForChangesInBufferedPosition',
      );

      expect(bindingBlock, isNot(contains('watchValue(progressBarStatus);')));
      expect(positionBlock, isNot(contains('notifyListeners();')));
      expect(bufferedBlock, isNot(contains('notifyListeners();')));
      expect(positionBlock, contains('progressBarStatus.update'));
      expect(bufferedBlock, contains('progressBarStatus.update'));
    });

    test('mini player progress bar clamps progress fraction', () {
      final miniProgressSource = File(
        'lib/ui/widgets/mini_player_progress_bar.dart',
      ).readAsStringSync();

      expect(miniProgressSource, contains('progressFraction'));
      expect(miniProgressSource, contains('total.inMilliseconds'));
      expect(miniProgressSource, contains('clamp(0.0, 1.0)'));
      expect(
        miniProgressSource,
        isNot(contains('current.inSeconds / total.inSeconds')),
      );
    });

    test('miniplayer height is repaired and announced on first play', () {
      final block = _methodBlock(source, '_playerPanelCheck');

      expect(
        block,
        contains('initFlagForPlayer || playerPanelMinHeight.value == 0'),
      );
      expect(block, contains('playerPanelMinHeight.value ='));
      expect(block, contains('initFlagForPlayer = false;'));
      expect(block, contains('_notifyPlayerChanged();'));
    });

    test('miniplayer height is set before auto-opening player panel', () {
      final block = _methodBlock(source, '_playerPanelCheck');
      final minHeightIndex = block.indexOf('playerPanelMinHeight.value =');
      final openIndex = block.indexOf('await playerPanelController.open();');

      expect(minHeightIndex, isNot(-1));
      expect(openIndex, isNot(-1));
      expect(minHeightIndex, lessThan(openIndex));
    });

    test('observable subscriptions are cleaned up with the controller', () {
      final block = _methodBlock(source, 'dispose');

      expect(block, contains('_disposed = true;'));
      expect(block, contains('_observableSubscriptions'));
      expect(block, contains('subscription.cancel()'));
      expect(block, contains('_observableSubscriptions.clear();'));
    });
  });
}

MediaItem _song(String id) => MediaItem(id: id, title: 'Song $id');

String _methodBlock(String source, String methodName) {
  var methodStart = source.indexOf('Future<void> $methodName(');
  if (methodStart == -1) {
    methodStart = source.indexOf('void $methodName(');
  }
  if (methodStart == -1) {
    methodStart = source.indexOf('Duration $methodName(');
  }
  if (methodStart == -1) {
    methodStart = source.indexOf('bool $methodName(');
  }
  expect(methodStart, isNot(-1), reason: 'Missing $methodName');
  final bodyStart = _methodBodyStart(source, methodStart);
  expect(bodyStart, isNot(-1), reason: 'Missing body for $methodName');

  var depth = 0;
  var started = false;
  for (var index = bodyStart; index < source.length; index++) {
    final char = source[index];
    if (char == '{') {
      depth++;
      started = true;
    } else if (char == '}') {
      depth--;
      if (started && depth == 0) {
        return source.substring(methodStart, index + 1);
      }
    }
  }

  fail('Could not find end of $methodName');
}

int _methodBodyStart(String source, int methodStart) {
  var parenDepth = 0;
  for (
    var index = source.indexOf('(', methodStart);
    index < source.length;
    index++
  ) {
    final char = source[index];
    if (char == '(') {
      parenDepth++;
    } else if (char == ')') {
      parenDepth--;
      if (parenDepth == 0) {
        return source.indexOf('{', index);
      }
    }
  }

  return -1;
}
