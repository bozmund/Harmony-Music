import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/previous_track_policy.dart';

void main() {
  late String player;
  late String receiver;
  late String audioHandler;
  late String playbackCommands;
  late String miniPlayer;
  late String fullPlayer;

  setUpAll(() {
    player = File(
      'lib/ui/player/player_controller.dart',
    ).readAsStringSync().withUnixNewlines;
    receiver = File(
      'lib/services/cloud/cloud_playback_receiver.dart',
    ).readAsStringSync().withUnixNewlines;
    audioHandler = File(
      'lib/services/audio_handler.dart',
    ).readAsStringSync().withUnixNewlines;
    playbackCommands = File(
      'lib/services/playback_command_service.dart',
    ).readAsStringSync().withUnixNewlines;
    miniPlayer = File(
      'lib/ui/player/components/mini_player.dart',
    ).readAsStringSync().withUnixNewlines;
    fullPlayer = File(
      'lib/ui/player/components/player_control.dart',
    ).readAsStringSync().withUnixNewlines;
  });

  test('remote selections enter loading before their network command', () {
    final standalone = _methodBlock(player, 'pushSongToQueue');
    final playlist = _methodBlock(player, 'playPlayListSong');

    expect(
      standalone.indexOf('beginRemoteSongTransition'),
      lessThan(standalone.indexOf('_playbackCommands.setSourceAndPlay')),
    );
    expect(
      playlist.indexOf('beginRemoteSongTransition'),
      lessThan(playlist.indexOf('_playbackCommands.updateQueue')),
    );
    expect(standalone, contains('failRemoteSongTransition(remoteTransition)'));
    expect(playlist, contains('failRemoteSongTransition(remoteTransition)'));
  });

  test('pending song id rejects stale remote frames and snapshots', () {
    final queue = _methodBlock(player, 'applyRemoteQueue');
    final index = _methodBlock(player, 'applyRemoteIndex');
    final progress = _methodBlock(player, 'applyRemoteProgress');

    expect(queue, contains('_pendingRemoteSongId'));
    expect(queue, contains('queue[safeIndex].id != pendingSongId'));
    expect(index, contains('currentQueue[safeIndex].id != pendingSongId'));
    expect(progress, contains('songId != pendingSongId'));
    expect(progress, contains('_confirmRemoteSongTransition()'));
  });

  test(
    'remote transition snapshots an aliased current queue before clearing',
    () {
      final transition = _methodBlock(player, 'beginRemoteSongTransition');
      final snapshotIndex = transition.indexOf(
        'final nextQueue = List<MediaItem>.from(queue)',
      );
      final clearIndex = transition.indexOf('..clear()');

      expect(snapshotIndex, isNot(-1));
      expect(clearIndex, isNot(-1));
      expect(snapshotIndex, lessThan(clearIndex));
      expect(
        transition,
        contains('_pendingRemoteSongId = nextQueue[index].id'),
      );
      expect(transition, contains('..addAll(nextQueue)'));
      expect(
        transition,
        contains('_setCurrentSongAndRefreshFavorite(nextQueue[index])'),
      );
    },
  );

  test('remote song changes refresh favorite state by song id', () {
    final assign = _methodBlock(player, '_setCurrentSongAndRefreshFavorite');
    final queue = _methodBlock(player, 'applyRemoteQueue');
    final index = _methodBlock(player, 'applyRemoteIndex');

    expect(assign, contains('isCurrentSongFav.value = false'));
    expect(assign, contains('unawaited(_checkFavFor(song))'));
    expect(queue, contains('_setCurrentSongAndRefreshFavorite('));
    expect(index, contains('_setCurrentSongAndRefreshFavorite('));
    expect(player, contains('isFavorite: isCurrentSongFav.value'));
    expect(player, contains('isCurrentSongFav.value = rollback.isFavorite'));
  });

  test('remote loading holds the target position and stops extrapolation', () {
    final progress = _methodBlock(player, 'applyRemoteProgress');

    expect(progress, contains('MediaItemBuilder.isResolving'));
    expect(progress, contains('final positionMs = reportedPositionMs'));
    expect(progress, contains('if (playing && !loading)'));
    expect(
      progress.indexOf('final positionMs = reportedPositionMs'),
      lessThan(progress.indexOf('RemoteProgressAnchor.fromSample')),
    );
  });

  test('target ignores Android position ticks while cloud song resolves', () {
    final resolving = _methodBlock(player, 'setCurrentSongResolving');
    final position = _methodBlock(player, '_listenForChangesInPosition');
    final buffered = _methodBlock(
      player,
      '_listenForChangesInBufferedPosition',
    );

    expect(resolving, contains('if (pendingSong != null)'));
    expect(resolving, contains('value.current = heldPosition'));
    expect(resolving, contains('value.buffered = heldPosition'));
    expect(resolving, contains('pendingPosition > Duration.zero'));
    expect(position, contains('if (_currentSongResolving) return'));
    expect(buffered, contains('if (_currentSongResolving) return'));
  });

  test('matching target metadata replaces the mirrored presentation', () {
    final progress = _methodBlock(player, 'applyRemoteProgress');
    final metadata = _methodBlock(player, '_applyRemoteSongMetadata');

    expect(progress, contains("_applyRemoteSongMetadata("));
    expect(metadata, contains("metadata['id']?.toString() != songId"));
    expect(metadata, contains("metadata['title']"));
    expect(metadata, contains("metadata['artist']"));
    expect(metadata, contains("metadata['album']"));
    expect(metadata, contains("metadata['durationMs']"));
    expect(metadata, contains("metadata['artworkUri']"));
    expect(metadata, contains('currentQueue[queueIndex] = settled'));
    expect(metadata, contains('_setCurrentSongAndRefreshFavorite(settled)'));
  });

  test('direct target taps supersede stale cloud loading placeholders', () {
    final watcher = _methodBlock(receiver, '_watchLocalPlaybackForPublication');
    final localSelection = _methodBlock(receiver, '_onLocalSongSelected');
    final localSongChanged = _methodBlock(receiver, '_onLocalSongChanged');
    final publishState = _methodBlock(receiver, '_publishSessionState');
    final metadata = _methodBlock(player, '_applyRemoteSongMetadata');

    expect(watcher, contains('_onLocalSongChanged'));
    expect(watcher, contains('_commands.localSongSelections.listen'));
    expect(localSelection, contains('_targetPlaybackGeneration++'));
    expect(localSelection, contains('_targetSongIdOverride = null'));
    expect(localSelection, contains('_targetLoadingPositionMs = null'));
    expect(localSelection, contains('_targetLoadingDurationMs = null'));
    expect(localSongChanged, contains('_applyingSessionQueue == 0'));
    expect(localSongChanged, contains('pendingSongId != item.id'));
    expect(localSongChanged, contains('_targetSongIdOverride = null'));
    expect(localSongChanged, contains('_targetLoadingPositionMs = null'));
    expect(localSongChanged, contains('_publishProgressFrame()'));
    expect(
      publishState,
      contains('final orderedIds = queue.map((item) => item.id).toList()'),
    );
    expect(
      publishState,
      isNot(contains('_appliedQueueIds!.length > queue.length')),
    );
    expect(
      publishState,
      contains('_appliedQueueIds = List<String>.unmodifiable(orderedIds)'),
    );
    expect(metadata, contains('MediaItemBuilder.placeholder(songId)'));
    expect(metadata, contains('queueIndex < 0'));
    expect(metadata, contains('currentSongIndex.value = queueIndex'));
  });

  test('Android media notification mirrors and controls the remote target', () {
    final progress = _methodBlock(player, 'applyRemoteProgress');
    final syncNotification = _methodBlock(
      player,
      '_syncRemoteMediaNotification',
    );
    final clearNotification = _methodBlock(
      player,
      'clearRemoteMediaNotification',
    );
    final customEvents = _methodBlock(player, '_listenForCustomEvents');
    final handlerPlay = _methodBlock(audioHandler, 'play');
    final handlerPause = _methodBlock(audioHandler, 'pause');
    final handlerSeek = _methodBlock(audioHandler, 'seek');
    final handlerNext = _methodBlock(audioHandler, 'skipToNext');
    final handlerPrevious = _methodBlock(audioHandler, 'skipToPrevious');
    final handlerActions = _methodBlock(audioHandler, 'customAction');
    final pauseForSyncEnd = _methodBlock(receiver, '_pauseLocalForSyncEnd');

    expect(progress, contains('_syncRemoteMediaNotification('));
    expect(syncNotification, contains('RuntimePlatform.isAndroid'));
    expect(syncNotification, contains("'setRemoteNotificationMirror'"));
    expect(clearNotification, contains("'clearRemoteNotificationMirror'"));
    expect(customEvents, contains("'remoteNotificationCommand'"));
    expect(customEvents, contains('await next()'));
    expect(customEvents, contains('await prev()'));
    expect(handlerPlay, contains("_forwardRemoteNotificationCommand('play')"));
    expect(
      handlerPause,
      contains("_forwardRemoteNotificationCommand('pause')"),
    );
    expect(handlerSeek, contains("_forwardRemoteNotificationCommand('seek'"));
    expect(handlerNext, contains("_forwardRemoteNotificationCommand('next')"));
    expect(
      handlerPrevious,
      contains("_forwardRemoteNotificationCommand('previous')"),
    );
    expect(handlerActions, contains("case 'setRemoteNotificationMirror':"));
    expect(handlerActions, contains("case 'clearRemoteNotificationMirror':"));
    expect(
      pauseForSyncEnd.indexOf('clearRemoteMediaNotification'),
      lessThan(pauseForSyncEnd.indexOf('await _local.pause()')),
    );
  });

  test('remote previous uses controller intent and rejects stale progress', () {
    final previous = _methodBlock(player, 'prev');
    final forwarding = _methodBlock(playbackCommands, 'previous');
    final updateQueue = _methodBlock(audioHandler, 'updateQueue');
    final previousCommand = receiver.substring(
      receiver.indexOf("case 'previous':"),
      receiver.indexOf("case 'queueUpdate':"),
    );
    final directPrevious = _methodBlock(
      receiver,
      '_playPreviousCloudQueueItem',
    );

    expect(previous, contains('_applyOptimisticRemoteSeek(Duration.zero)'));
    expect(previous, contains('beginRemoteSongTransition('));
    expect(previous, contains('remoteIntent: remoteIntent'));
    expect(previous, contains('desiredVideoId: desiredVideoId'));
    expect(forwarding, contains("'intent': remoteIntent.name"));
    expect(forwarding, contains("'desiredVideoId': desiredVideoId"));
    expect(previousCommand, contains("payload['intent']"));
    expect(previousCommand, contains('PreviousTrackIntent.restartCurrent'));
    expect(previousCommand, isNot(contains("payload['positionMs']")));
    expect(previousCommand, contains('await _local.seek(Duration.zero)'));
    expect(previousCommand, contains("payload['desiredVideoId']"));
    expect(previousCommand, contains('await _startPlayback('));
    expect(previousCommand, contains('await _playPreviousCloudQueueItem()'));
    expect(directPrevious, contains('_targetSongIdOverride'));
    expect(directPrevious, contains('_local.currentSong?.id'));
    expect(directPrevious, contains('final previousIndex = currentIndex - 1'));
    expect(directPrevious, contains('await _startPlayback('));
    expect(audioHandler, contains('DateTime? _previousRestartedAt'));
    expect(audioHandler, contains('final restartedAt = _previousRestartedAt'));
    expect(audioHandler, contains('_previousRestartedAt = DateTime.now()'));
    expect(updateQueue, contains('item.id == currentSongId'));
    expect(updateQueue, contains('currentIndex = nextIndex'));
  });

  test('previous threshold matches the established local behavior', () {
    expect(shouldRestartCurrentTrack(previousTrackRestartThreshold), isFalse);
    expect(
      shouldRestartCurrentTrack(
        previousTrackRestartThreshold + const Duration(milliseconds: 1),
      ),
      isTrue,
    );
    expect(
      previousTrackIntentFor(previousTrackRestartThreshold),
      PreviousTrackIntent.selectPrevious,
    );
    expect(
      previousTrackIntentFor(
        previousTrackRestartThreshold + const Duration(milliseconds: 1),
      ),
      PreviousTrackIntent.restartCurrent,
    );
    expect(
      previousTrackIntentFromWire('selectPrevious'),
      PreviousTrackIntent.selectPrevious,
    );
    expect(previousTrackIntentFromWire('invalid'), isNull);
  });

  test('target exposes the incoming song while it resolves', () {
    final start = _methodBlock(receiver, '_startPlayback');
    final publish = _methodBlock(receiver, '_publishProgressFrame');

    expect(start, contains('MediaItemBuilder.placeholder(queueIds[index])'));
    expect(start, contains('prepareIncomingCloudSong('));
    expect(publish, contains("frame['loading'] = true"));
    expect(publish, contains("frame['currentSongId'] = pendingSongId"));
    expect(publish, contains("frame['positionMs'] = targetLoadingPositionMs"));
    expect(publish, contains("frame['songMetadata']"));
  });

  test('a stale session read cannot demote the device that just became the '
      'audio target', () {
    final refresh = _methodBlock(receiver, '_refreshSession');
    final become = _methodBlock(receiver, '_becomeAudioTarget');
    final adopt = _methodBlock(receiver, 'adoptInitiatedHandoff');
    final ended = _methodBlock(receiver, '_onSessionEnded');
    final leave = _methodBlock(receiver, 'leaveSync');

    // Reading the session is a round trip that races the pending-command drain
    // applying a handoff. Applying its stale answer flips a device that is
    // already producing audio into mirror mode, where its own player events are
    // discarded and the title shimmers under a song that is plainly playing.
    expect(refresh, contains('final generation = _roleGeneration'));
    expect(
      refresh.indexOf('final generation = _roleGeneration'),
      lessThan(refresh.indexOf('await _cloud.playbackSession()')),
    );
    expect(
      refresh.indexOf('generation != _roleGeneration'),
      greaterThan(refresh.indexOf('await _cloud.playbackSession()')),
    );
    expect(
      refresh.indexOf('generation != _roleGeneration'),
      lessThan(refresh.indexOf('await _applySession(')),
    );
    for (final roleChange in [become, adopt, ended, leave]) {
      expect(roleChange, contains('_roleGeneration++'));
    }
  });

  test('the audio target drops any mirror gate before revealing its song', () {
    final start = _methodBlock(receiver, '_startPlayback');
    final clearIndex = start.indexOf(
      'await _player?.clearRemoteSessionState()',
    );
    final resolvingIndex = start.indexOf(
      '_player?.setCurrentSongResolving(false)',
    );

    // clearRemoteSessionState resyncs the visible song from this device's own
    // handler, which is authoritative for whoever is producing the audio.
    expect(clearIndex, isNot(-1));
    expect(resolvingIndex, isNot(-1));
    expect(clearIndex, lessThan(resolvingIndex));
    expect(
      _methodBlock(player, 'clearRemoteSessionState'),
      contains('if (!_cloudRemoteStateActive) return'),
    );
  });

  test('nothing the target waits on can outlive the spinner it shows', () {
    final start = _methodBlock(receiver, '_startPlayback');
    final metadata = File(
      'lib/services/metadata/song_metadata_service.dart',
    ).readAsStringSync().withUnixNewlines;
    final music = File(
      'lib/services/music_service.dart',
    ).readAsStringSync().withUnixNewlines;

    // Everything the user can see on the audio target clears in _startPlayback's
    // `finally`, so every await inside it has to be bounded or the device sits
    // on a spinner and a placeholder title forever.
    expect(start, contains('.timeout(_metadataResolveTimeout'));
    expect(start, contains('.timeout(\n            _playbackStartTimeout,'));
    expect(
      metadata,
      contains(
        'completer.future.timeout(_resolveBudget, onTimeout: () => null)',
      ),
    );
    // Dio applies no timeouts unless it is given them.
    expect(music, contains('connectTimeout:'));
    expect(music, contains('receiveTimeout:'));
    expect(music, contains('sendTimeout:'));
  });

  test('a handoff resumed mid-track counts as a started source', () {
    final startPosition = _methodBlock(player, '_isSourceStartPosition');
    final playbackProgress = _methodBlock(player, '_hasSourcePlaybackProgress');
    final begin = _methodBlock(player, '_beginPendingSourceStart');
    final clear = _methodBlock(player, '_clearPendingSourceStart');
    final resolving = _methodBlock(player, 'setCurrentSongResolving');

    // Hand a song over 59s in and the target seeks to 0:59. Measuring "did the
    // source start" against zero called that a stalled start forever, which
    // pinned the play button on loading and shimmered the title of a song that
    // was resolved and playing.
    expect(startPosition, contains('_pendingPlaybackStartPosition'));
    expect(
      startPosition,
      isNot(contains('position <= _sourceStartProgressWindow')),
    );
    expect(
      playbackProgress,
      contains('position > _pendingPlaybackStartPosition'),
    );
    // Still measured from the handoff position, but only when the
    // expectation belongs to this song - see the resume-position test in
    // player_controller_queue_order_test.dart.
    expect(begin, contains('_expectedSourceStartSongId == songId'));
    expect(begin, contains('expectedStart ?? Duration.zero'));
    expect(clear, contains('_pendingPlaybackStartPosition = Duration.zero'));
    expect(clear, contains('_expectedSourceStartPosition = null'));
    expect(
      resolving,
      contains('_expectedSourceStartPosition = pendingPosition'),
    );
  });

  test('resolved metadata replaces a placeholder for the same song id', () {
    final observable = File(
      'lib/utils/observable_state.dart',
    ).readAsStringSync().withUnixNewlines;
    final assign = _methodBlock(player, '_setCurrentSongAndRefreshFavorite');
    final duration = _methodBlock(player, '_listenForChangesInDuration');

    // MediaItem.operator== compares id alone, so a resolved song and the
    // placeholder it replaces are "equal". ObservableValue's setter drops equal
    // writes, which left the placeholder — and its shimmer — on screen forever
    // while the audio handler happily played the real track.
    expect(observable, contains('void overwrite(T next)'));
    expect(observable, contains('if (identical(_value, next)) return'));
    expect(assign, contains('currentSong.overwrite(song)'));
    expect(assign, isNot(contains('currentSong.value = song')));
    expect(duration, contains('currentSong.overwrite(mediaItem)'));
    expect(duration, isNot(contains('currentSong.value = mediaItem')));
  });

  test('remote standalone selections preserve their expanded queue', () {
    final standalone = _methodBlock(player, 'pushSongToQueue');
    final setSource = _methodBlock(playbackCommands, 'setSourceAndPlay');

    expect(standalone, contains('_playbackCommands.isRemoteControlActive'));
    expect(standalone, contains('final remoteQueue = await queueUpdate'));
    expect(standalone, contains('transitionQueue = remoteQueue'));
    expect(setSource, contains('_remoteQueue.indexWhere'));
    expect(setSource, contains('remoteIndex < 0 ? [mediaItem] : _remoteQueue'));
  });

  test('stale queue resolution cannot overwrite a newer handoff', () {
    final start = _methodBlock(receiver, '_startPlayback');
    final widen = _methodBlock(receiver, '_widenLocalQueue');

    expect(start, contains('final generation = ++_targetPlaybackGeneration'));
    expect(start, contains('generation != _targetPlaybackGeneration'));
    expect(start, contains('_widenLocalQueue(queueIds, generation)'));
    expect(widen, contains('generation != _targetPlaybackGeneration'));
    expect(
      widen.indexOf('generation != _targetPlaybackGeneration'),
      lessThan(widen.indexOf('await _local.updateQueue(resolved)')),
    );
    expect(widen, contains('generation == _targetPlaybackGeneration'));
  });

  test('stale queue-update resolution cannot overwrite a newer handoff', () {
    final update = _methodBlock(receiver, '_applyQueueUpdate');

    // Socket commands are dispatched concurrently. A large, older queueUpdate
    // can therefore finish resolving after a newer handoff has already
    // installed its queue. The queue update must participate in the same
    // supersession generation as handoff widening before it mutates the player.
    expect(update, contains('final generation = _targetPlaybackGeneration'));
    expect(update, contains('final queueUpdateGeneration ='));
    expect(update, contains('queueUpdateGeneration != _queueUpdateGeneration'));
    expect(update, contains('generation != _targetPlaybackGeneration'));
    expect(
      update.lastIndexOf('generation != _targetPlaybackGeneration'),
      greaterThan(update.indexOf('await _metadata.resolveBatch(queueIds)')),
    );
    expect(
      update.lastIndexOf('generation != _targetPlaybackGeneration'),
      lessThan(update.indexOf('await _local.updateQueue(items)')),
    );
  });

  test('a rejected optimistic snapshot is not marked as applied', () {
    final queue = _methodBlock(player, 'applyRemoteQueue');
    final mirror = _methodBlock(receiver, '_mirrorQueue');

    // applyRemoteQueue can reject a snapshot while an optimistic next/previous
    // transition is pending. Recording its ids anyway makes every later
    // snapshot look unchanged even though the visible queue was never replaced.
    expect(queue, contains('bool applyRemoteQueue('));
    expect(queue, contains('return false;'));
    expect(queue, contains('return true;'));
    expect(mirror, contains('final queueApplied = player.applyRemoteQueue('));
    expect(mirror, contains('if (!queueApplied) return;'));
    expect(
      mirror.indexOf('_appliedQueueIds = List<String>.unmodifiable(queueIds)'),
      greaterThan(mirror.indexOf('if (!queueApplied) return;')),
    );
  });

  test('handoff resumes from the controller position before playing', () {
    final start = _methodBlock(receiver, '_startPlayback');
    final load = _methodBlock(
      audioHandler,
      '_loadCurrentSourceFromStartAndPlay',
    );
    final playByIndexCase = audioHandler.substring(
      audioHandler.indexOf("case 'playByIndex':"),
      audioHandler.indexOf("case 'setSourceNPlay':"),
    );

    expect(start, contains('position: startPosition'));
    expect(playByIndexCase, contains("(extras['position'] as num?)"));
    expect(playByIndexCase, contains('startPosition: requestedPosition'));
    expect(load, contains('_player.seek(startPosition, index: 0)'));
    expect(
      load.indexOf('_player.seek(startPosition, index: 0)'),
      lessThan(load.indexOf('_startPlayerPlayback()')),
    );
  });

  test('leaving sync pauses both sides and clears either device role', () {
    final leave = _methodBlock(receiver, 'leaveSync');
    final ended = _methodBlock(receiver, '_onSessionEnded');

    expect(leave, contains('await _cloud.endPlaybackSession()'));
    expect(leave, isNot(contains('if (wasTarget)')));
    expect(leave, contains('await _commands.pause()'));
    expect(leave, contains('await _pauseLocalForSyncEnd('));
    expect(leave, contains('preserveMirroredPosition: wasRemoteController'));
    expect(
      leave.indexOf('await _commands.pause()'),
      lessThan(leave.indexOf('_commands.stopRemoteControl()')),
    );
    expect(ended, contains('await _pauseLocalForSyncEnd('));
    expect(
      ended.indexOf('await _pauseLocalForSyncEnd('),
      lessThan(ended.indexOf('_commands.stopRemoteControl()')),
    );
  });

  test('leaving sync keeps the session song, not the pre-sync one', () {
    final pause = _methodBlock(receiver, '_pauseLocalForSyncEnd');
    final adopt = _methodBlock(receiver, '_adoptMirroredSongLocally');

    // A controller's own handler never moves during a session, so rebuilding
    // the UI from it on leave teleported the user back to whatever was playing
    // before the handoff.
    expect(
      pause.indexOf('_adoptMirroredSongLocally()'),
      lessThan(pause.indexOf('await _local.pause()')),
    );
    expect(adopt, contains('MediaItemBuilder.isResolving(mirroredSong)'));
    // Same song already loaded: keep its timer rather than reloading it.
    expect(adopt, contains('_local.currentSong?.id == mirroredSong.id'));
    expect(adopt, contains('await _local.seek(position)'));
    // Different song: adopt the session's queue and prepare without resuming.
    expect(adopt, contains('await _local.updateQueue(queue)'));
    expect(adopt, contains('restoreSession: true'));
    expect(adopt, contains('position: position.inMilliseconds'));
  });

  test('incoming target prepares the collapsed player without opening it', () {
    final prepare = _methodBlock(player, 'prepareIncomingCloudSong');
    final resolvingIndex = prepare.indexOf('setCurrentSongResolving(');
    final panelIndex = prepare.indexOf(
      '_playerPanelCheck(restoreSession: true)',
    );

    expect(resolvingIndex, isNot(-1));
    expect(panelIndex, isNot(-1));
    expect(resolvingIndex, lessThan(panelIndex));
    expect(prepare, contains('if (!playerPanelOpen.value)'));
    expect(prepare, contains('playerPanelTopVisible.value = true'));
    expect(prepare, contains('playerPaneOpacity.value = 1'));
    expect(prepare, isNot(contains('playerPanelController.open')));
  });

  test('a resolved song never shimmers because audio is busy', () {
    final getter = player.substring(
      player.indexOf('bool get isCurrentSongLoading'),
      player.indexOf('bool get isCurrentOnlineSongInitiallyLoading'),
    );
    expect(getter, contains('MediaItemBuilder.isResolving'));
    expect(getter, isNot(contains('buttonState')));
    expect(getter, isNot(contains('_currentSongResolving')));
  });

  test('online artwork shimmers only until the selected source starts', () {
    final getter = player.substring(
      player.indexOf('bool get isCurrentOnlineSongInitiallyLoading'),
      player.indexOf('int? beginRemoteSongTransition'),
    );

    expect(getter, contains("_isWaitingForCurrentSourceStart"));
    expect(getter, contains('_currentSongResolving'));
    expect(getter, contains("!sourceUrl.contains('file')"));
    expect(getter, isNot(contains('buttonState')));
  });

  test('a brief rebuffer does not swap the play icon for a spinner', () {
    final block = _methodBlock(player, '_listenForChangesInPlayerState');
    final arm = _methodBlock(player, '_armBufferingGrace');

    expect(player, contains('static const _bufferingSpinnerGrace'));
    expect(block, contains('_armBufferingGrace('));
    expect(block, contains('_cancelBufferingGrace();'));
    // Real loads must not wait out the grace window.
    expect(
      block.indexOf('final immediateLoading'),
      lessThan(block.indexOf('_armBufferingGrace(')),
    );
    expect(arm, contains('AudioProcessingState.buffering'));
    expect(
      _methodBlock(player, 'dispose'),
      contains('_cancelBufferingGrace()'),
    );
    // The handoff tail lands mid-rebuffer and must follow the same rule.
    expect(
      _methodBlock(player, 'setCurrentSongResolving'),
      contains('_armBufferingGrace('),
    );
  });

  test('seeking before a source starts retargets the pending start', () {
    final seek = _methodBlock(player, 'seek');
    expect(seek, contains('_retargetPendingSourceStart(position)'));

    final retarget = _methodBlock(player, '_retargetPendingSourceStart');
    expect(retarget, contains('_pendingPlaybackStartPosition = position'));
    expect(retarget, contains('_expectedSourceStartPosition = position'));
    expect(retarget, contains('_sourceStartGuardPosition = position'));

    // Restarting the current track seeks to zero for the same reason.
    expect(
      _methodBlock(player, 'prev'),
      contains('_retargetPendingSourceStart(Duration.zero)'),
    );
  });

  test('both player surfaces use the unified song loading predicate', () {
    expect(fullPlayer, contains('playerController.isCurrentSongLoading'));
    expect(miniPlayer, contains('playerController.isCurrentSongLoading'));
    expect(
      RegExp('BasicShimmerContainer').allMatches(miniPlayer).length,
      greaterThanOrEqualTo(2),
    );
  });
}

String _methodBlock(String source, String methodName) {
  var methodStart = source.indexOf('Future<void> $methodName(');
  if (methodStart == -1) {
    methodStart = source.indexOf('Future<bool> $methodName(');
  }
  if (methodStart == -1) {
    methodStart = source.indexOf('Future<dynamic> $methodName(');
  }
  if (methodStart == -1) {
    methodStart = source.indexOf('int? $methodName(');
  }
  if (methodStart == -1) {
    methodStart = source.indexOf('bool $methodName(');
  }
  if (methodStart == -1) {
    methodStart = source.indexOf('void $methodName(');
  }
  expect(methodStart, isNot(-1), reason: 'Missing $methodName');
  final bodyStart = _methodBodyStart(source, methodStart);
  expect(bodyStart, isNot(-1), reason: 'Missing body for $methodName');
  var depth = 0;
  var started = false;
  for (var i = bodyStart; i < source.length; i++) {
    if (source[i] == '{') {
      depth++;
      started = true;
    } else if (source[i] == '}') {
      depth--;
      if (started && depth == 0) {
        return source.substring(methodStart, i + 1);
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
      if (parenDepth == 0) return source.indexOf('{', index);
    }
  }
  return -1;
}

/// Source assertions in this file match on LF. Git checks these files out with
/// CRLF on Windows (`core.autocrlf=true`), so a literal read makes every
/// multi-line needle miss — the assertion then fails on the developer's machine
/// and passes in CI, which is the worst way for a test to be wrong.
extension _UnixNewlines on String {
  String get withUnixNewlines => replaceAll('\r\n', '\n');
}
