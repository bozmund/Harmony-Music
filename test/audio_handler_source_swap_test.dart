import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('audio handler source swaps', () {
    late String source;

    setUp(() {
      source = File('lib/services/audio_handler.dart').readAsStringSync();
    });

    test('playByIndex uses classic one-song source flow', () {
      expect(
        _usesClassicOneSongSourceFlow(_caseBlock(source, 'playByIndex')),
        isTrue,
      );
    });

    test('setSourceNPlay uses classic one-song source flow', () {
      expect(
        _usesClassicOneSongSourceFlow(_caseBlock(source, 'setSourceNPlay')),
        isTrue,
      );
    });

    test('source play commands recover from source failures', () {
      final playByIndex = _caseBlock(source, 'playByIndex');
      final setSourceNPlay = _caseBlock(source, 'setSourceNPlay');

      for (final block in [playByIndex, setSourceNPlay]) {
        expect(block, contains('try {'));
        expect(block, contains('catch (error, stackTrace)'));
        expect(block, contains('_handleSourcePlaybackFailure('));
      }

      final failureBlock = _methodBlock(source, '_handleSourcePlaybackFailure');
      expect(failureBlock, contains('isSongLoading = false;'));
      expect(failureBlock, contains("'eventType': 'playError'"));
      expect(failureBlock, contains('AudioProcessingState.error'));
      expect(failureBlock, contains('errorMessage: message'));
    });

    test('successful source play emits a non-loading playback snapshot', () {
      final playByIndex = _caseBlock(source, 'playByIndex');
      final setSourceNPlay = _caseBlock(source, 'setSourceNPlay');
      final snapshotBlock = _methodBlock(source, '_emitSourceStartedSnapshot');

      expect(playByIndex, contains('_emitSourceStartedSnapshot();'));
      expect(setSourceNPlay, contains('_emitSourceStartedSnapshot();'));
      expect(snapshotBlock, contains('AudioProcessingState.ready'));
      expect(snapshotBlock, contains('playing: true'));
    });

    test('source play commands log stream setup milestones', () {
      final playByIndex = _caseBlock(source, 'playByIndex');
      final setSourceNPlay = _caseBlock(source, 'setSourceNPlay');

      expect(playByIndex, contains('playByIndex resolving stream info'));
      expect(playByIndex, contains('playByIndex selected audio url empty='));
      expect(playByIndex, contains('playByIndex adding audio source'));
      expect(playByIndex, contains('playByIndex seek and play'));
      expect(setSourceNPlay, contains('setSourceNPlay resolving stream info'));
      expect(
        setSourceNPlay,
        contains('setSourceNPlay selected audio url empty='),
      );
      expect(setSourceNPlay, contains('setSourceNPlay adding audio source'));
      expect(setSourceNPlay, contains('setSourceNPlay seek and play'));
    });

    test('source play commands explicitly load the new one-song source', () {
      final playByIndex = _caseBlock(source, 'playByIndex');
      final setSourceNPlay = _caseBlock(source, 'setSourceNPlay');
      final loadStartBlock = _methodBlock(
        source,
        '_loadCurrentSourceFromStartAndPlay',
      );

      expect(playByIndex, contains('_loadCurrentSourceFromStartAndPlay();'));
      expect(setSourceNPlay, contains('_loadCurrentSourceFromStartAndPlay();'));
      expect(loadStartBlock, contains('await _player.load();'));
      expect(
        loadStartBlock,
        contains('await _player.seek(Duration.zero, index: 0);'),
      );
      expect(loadStartBlock, contains('_startPlayerPlayback();'));
      expect(loadStartBlock, isNot(contains('await _player.play();')));
      expect(loadStartBlock, contains('_startCompletionWatchdog();'));
    });

    test('source start clears loading after requesting playback', () {
      final playByIndex = _caseBlock(source, 'playByIndex');
      final setSourceNPlay = _caseBlock(source, 'setSourceNPlay');
      final startPlaybackBlock = _methodBlock(source, '_startPlayerPlayback');

      expect(startPlaybackBlock, contains('unawaited('));
      expect(startPlaybackBlock, contains('_player.play().catchError'));
      expect(startPlaybackBlock, isNot(contains('await _player.play();')));
      expect(
        _loadsThenClearsLoadingThenEmitsStarted(playByIndex),
        isTrue,
        reason: 'playByIndex must clear loading after source playback starts',
      );
      expect(
        _loadsThenClearsLoadingThenEmitsStarted(setSourceNPlay),
        isTrue,
        reason:
            'setSourceNPlay must clear loading after source playback starts',
      );
    });

    test('source load errors retry once with a fresh stream url', () {
      final playByIndex = _caseBlock(source, 'playByIndex');
      final setSourceNPlay = _caseBlock(source, 'setSourceNPlay');
      final freshUrlBlock = _methodBlock(
        source,
        '_freshStreamInfoAfterSourceLoadFailure',
      );
      final replaceSourceBlock = _methodBlock(
        source,
        '_replaceCurrentSourceWithStreamInfo',
      );

      expect(playByIndex, contains('catch (error, stackTrace)'));
      expect(playByIndex, contains('if (isNewUrlReq) rethrow;'));
      expect(playByIndex, contains('_freshStreamInfoAfterSourceLoadFailure'));
      expect(playByIndex, contains('_replaceCurrentSourceWithStreamInfo'));
      expect(playByIndex, contains('requestGeneration != _playbackGeneration'));
      expect(
        setSourceNPlay,
        contains('_freshStreamInfoAfterSourceLoadFailure'),
      );
      expect(setSourceNPlay, contains('_replaceCurrentSourceWithStreamInfo'));
      expect(freshUrlBlock, contains('generateNewUrl: true'));
      expect(freshUrlBlock, contains('source-load-retry'));
      expect(replaceSourceBlock, contains('await _player.stop();'));
      expect(replaceSourceBlock, contains('await _playList.clear();'));
      expect(replaceSourceBlock, contains('await _playList.add'));
    });

    test('repeat mode uses just_audio native loop mode', () {
      final block = _methodBlock(source, 'setRepeatMode');

      expect(block, contains('await _player.setLoopMode('));
      expect(block, contains('LoopMode.one'));
      expect(block, contains('LoopMode.off'));
    });

    test('pause and stop emit immediate non-playing snapshots', () {
      final pauseBlock = _methodBlock(source, 'pause');
      final stopBlock = _methodBlock(source, 'stop');
      final snapshotBlock = _methodBlock(source, '_emitPlaybackSnapshot');

      expect(pauseBlock, contains('isSongLoading = false;'));
      expect(pauseBlock, contains('_emitPlaybackSnapshot('));
      expect(pauseBlock, contains('playing: false'));
      expect(pauseBlock, contains('_nonLoadingProcessingState()'));
      expect(stopBlock, contains('isSongLoading = false;'));
      expect(stopBlock, contains('AudioProcessingState.idle'));
      expect(stopBlock, contains('playing: false'));
      expect(snapshotBlock, contains('updatePosition: _player.position'));
      expect(
        snapshotBlock,
        contains('bufferedPosition: _player.bufferedPosition'),
      );
    });

    test(
      'shuffle mode uses visible queue order and can restore original order',
      () {
        final setShuffleBlock = _methodBlock(source, 'setShuffleMode');
        final shuffleBlock = _methodBlock(
          source,
          '_shuffleVisibleQueueFromIndex',
        );
        final restoreBlock = _methodBlock(source, '_restoreQueueBeforeShuffle');
        final nextBlock = _methodBlock(source, '_getNextSongIndex');
        final previousBlock = _methodBlock(source, '_getPrevSongIndex');

        expect(source, contains('List<MediaItem>? _queueBeforeShuffle;'));
        expect(source, isNot(contains('List<String> shuffledQueue')));
        expect(setShuffleBlock, contains('_shuffleVisibleQueueFromIndex'));
        expect(setShuffleBlock, contains('_restoreQueueBeforeShuffle'));
        expect(
          shuffleBlock,
          contains('PlaybackQueueOrder.shuffledFromCurrent'),
        );
        expect(restoreBlock, contains('PlaybackQueueOrder.indexOfSongId'));
        expect(nextBlock, isNot(contains('shuffleModeEnabled')));
        expect(previousBlock, isNot(contains('shuffleModeEnabled')));
        expect(previousBlock, contains('queueLoopModeEnabled'));
        expect(previousBlock, contains('queue.value.length - 1'));
      },
    );

    test(
      'queue rewrites rebroadcast the live media item for the same song',
      () {
        // The queue copy of the current song can still carry duration == null
        // (the resolved duration is only broadcast, never written back into
        // the queue). Rebroadcasting that stale copy on shuffle/unshuffle
        // collapses the progress bar total to zero and pins the bar at 0:00.
        final block = _methodBlock(source, '_setQueueAndCurrent');

        expect(block, contains('final current = mediaItem.value;'));
        expect(
          block,
          contains('current.id == nextItem.id ? current : nextItem'),
        );
        expect(
          block,
          isNot(contains('mediaItem.add(nextQueue[clampedIndex])')),
        );
      },
    );

    test(
      'auto advance listens for completed state and final-position fallback',
      () {
        final listenerBlock = _methodBlock(
          source,
          '_listenToPlaybackForNextSong',
        );
        final endPositionBlock = _methodBlock(
          source,
          '_listenForEndPositionFallback',
        );
        final watchdogBlock = _methodBlock(source, '_checkCompletionWatchdog');
        final eventBlock = _methodBlock(
          source,
          '_notifyAudioHandlerAboutPlaybackEvents',
        );
        final handlerBlock = _methodBlock(source, '_handlePlaybackCompleted');

        expect(listenerBlock, contains('_player.processingStateStream.listen'));
        expect(listenerBlock, contains('ProcessingState.completed'));
        expect(listenerBlock, contains('_scheduleCompletionHandling'));
        expect(eventBlock, contains('_player.playbackEventStream.listen'));
        expect(eventBlock, contains('event.processingState'));
        expect(eventBlock, contains('_scheduleCompletionHandling'));
        expect(handlerBlock, contains('loopModeEnabled'));
        expect(handlerBlock, contains('_completionInProgress'));
        expect(handlerBlock, contains('_scheduleCompletionRetry'));
        expect(endPositionBlock, contains('createPositionStream'));
        expect(endPositionBlock, contains('_prepareNextSourceWhenNearEnd'));
        expect(endPositionBlock, contains('_isAtEndPosition(position)'));
        expect(endPositionBlock, contains('allowEndPosition: true'));
        expect(watchdogBlock, contains('ProcessingState.completed'));
        expect(watchdogBlock, contains('_shouldHonorCompletedStateNow()'));
        expect(watchdogBlock, contains('allowEndPosition: true'));
        final isAtEndBlock = _methodBlock(source, '_isAtEndPosition');
        expect(isAtEndBlock, contains('_expectedEndDuration()'));
        expect(isAtEndBlock, contains('return currentPosition >= duration;'));
        expect(isAtEndBlock, isNot(contains('remaining.inMilliseconds')));
      },
    );

    test(
      'repeat completion restarts the current source from the beginning',
      () {
        final listenerBlock = _methodBlock(source, '_handlePlaybackCompleted');
        final repeatBlock = _methodBlock(source, '_repeatCurrentSongFromStart');
        final startPlaybackBlock = _methodBlock(source, '_startPlayerPlayback');

        expect(listenerBlock, contains('await _repeatCurrentSongFromStart();'));
        expect(listenerBlock, contains('return;'));
        expect(
          repeatBlock,
          contains('await _player.seek(Duration.zero, index: 0);'),
        );
        expect(repeatBlock, contains('_startPlayerPlayback();'));
        expect(startPlaybackBlock, contains('unawaited('));
        expect(startPlaybackBlock, contains('_player.play().catchError'));
      },
    );

    test('restores saved repeat mode to the underlying player on init', () {
      final block = _methodBlock(source, '_init');

      expect(block, contains('_settingsRepository.getLoopModeEnabled()'));
      expect(block, contains('await _player.setLoopMode('));
      expect(block, contains('LoopMode.one'));
      expect(block, contains('LoopMode.off'));
    });

    test('completion guard is declared on the audio handler', () {
      expect(source, contains('bool _completionInProgress = false;'));
      expect(source, contains('bool _completionHandlingScheduled = false;'));
      expect(
        source,
        contains('bool _completionHandlingAllowEndPosition = false;'),
      );
      expect(source, contains('bool _completionRetryScheduled = false;'));
      expect(source, contains('Timer? _completionWatchdogTimer;'));
      expect(source, contains('DateTime? _earlyCompletionDetectedAt;'));
      expect(source, contains('Duration? _earlyCompletionDelay;'));
      expect(source, contains('const _fallbackCompletionGrace'));
    });

    test('completion watchdog is managed with playback lifecycle', () {
      final startBlock = _methodBlock(source, '_startCompletionWatchdog');
      final stopBlock = _methodBlock(source, '_stopCompletionWatchdog');
      final watchdogBlock = _methodBlock(source, '_checkCompletionWatchdog');
      final pauseBlock = _methodBlock(source, 'pause');
      final stopMethodBlock = _methodBlock(source, 'stop');
      final disposeCase = _caseBlock(source, 'dispose');

      expect(startBlock, contains('Timer.periodic'));
      expect(startBlock, contains('const Duration(milliseconds: 250)'));
      expect(startBlock, contains('_checkCompletionWatchdog'));
      expect(stopBlock, contains('_completionWatchdogTimer?.cancel()'));
      expect(stopBlock, contains('_completionWatchdogTimer = null'));
      expect(watchdogBlock, contains('isSongLoading'));
      expect(watchdogBlock, contains('_completionInProgress'));
      expect(watchdogBlock, contains('_sourceSwitchInProgress'));
      expect(watchdogBlock, contains('_player.processingState'));
      expect(watchdogBlock, contains('ProcessingState.completed'));
      expect(watchdogBlock, contains('_shouldHonorCompletedStateNow()'));
      expect(watchdogBlock, contains('_player.playing && _isAtEndPosition()'));
      expect(pauseBlock, contains('_stopCompletionWatchdog();'));
      expect(stopMethodBlock, contains('_stopCompletionWatchdog();'));
      expect(disposeCase, contains('_stopCompletionWatchdog();'));
    });

    test('buffering stall watchdog recovers with a fresh stream url', () {
      final startBlock = _methodBlock(source, '_startCompletionWatchdog');
      final stopBlock = _methodBlock(source, '_stopCompletionWatchdog');
      final stallBlock = _methodBlock(source, '_checkBufferingStallWatchdog');
      final recoverBlock = _methodBlock(source, '_recoverFromStalledSource');
      final eventBlock = _methodBlock(
        source,
        '_notifyAudioHandlerAboutPlaybackEvents',
      );

      expect(source, contains('Duration? _stallWatchPosition;'));
      expect(source, contains('DateTime? _stallWatchSince;'));
      expect(source, contains('bool _stallRecoveryInFlight = false;'));
      expect(source, contains('const _bufferingStallThreshold'));
      expect(source, contains('const _bufferingStallPositionTolerance'));
      expect(startBlock, contains('_checkBufferingStallWatchdog();'));
      expect(stopBlock, contains('_resetBufferingStallWatch();'));
      expect(stallBlock, contains('isSongLoading'));
      expect(stallBlock, contains('_completionInProgress'));
      expect(stallBlock, contains('_sourceSwitchInProgress'));
      expect(stallBlock, contains('_stallRecoveryInFlight'));
      expect(stallBlock, contains('ProcessingState.buffering'));
      expect(stallBlock, contains('_bufferingStallThreshold'));
      expect(stallBlock, contains('_recoverFromStalledSource'));
      // Both the stall watchdog and the player error handler share the same
      // recovery: regenerate the stream URL and reseek to where we stalled.
      expect(eventBlock, contains('_recoverFromStalledSource'));
      expect(recoverBlock, contains("'newUrl': true"));
      expect(recoverBlock, contains('_player.seek(resumePosition, index: 0)'));
    });

    test('watchdog defers early completed state until expected media end', () {
      final honorBlock = _methodBlock(source, '_shouldHonorCompletedStateNow');
      final expectedDurationBlock = _methodBlock(
        source,
        '_expectedEndDuration',
      );
      final resetEarlyBlock = _methodBlock(
        source,
        '_resetEarlyCompletionDeferral',
      );
      final stopWatchdogBlock = _methodBlock(source, '_stopCompletionWatchdog');
      final resetPreparedBlock = _methodBlock(
        source,
        '_resetPreparedNextSource',
      );

      expect(honorBlock, contains('_expectedEndDuration()'));
      expect(honorBlock, contains('position >= expectedDuration'));
      expect(honorBlock, contains('_earlyCompletionDetectedAt ??='));
      expect(honorBlock, contains('_earlyCompletionDelay ??='));
      expect(honorBlock, contains('_fallbackCompletionGrace'));
      expect(
        honorBlock,
        contains('DateTime.now().difference(_earlyCompletionDetectedAt!)'),
      );
      expect(expectedDurationBlock, contains('mediaDuration'));
      expect(expectedDurationBlock, contains('playerDuration > mediaDuration'));
      expect(resetEarlyBlock, contains('_earlyCompletionDetectedAt = null'));
      expect(resetEarlyBlock, contains('_earlyCompletionDelay = null'));
      expect(stopWatchdogBlock, contains('_resetEarlyCompletionDeferral();'));
      expect(resetPreparedBlock, contains('_resetEarlyCompletionDeferral();'));
    });

    test('pre-end preparation checks next source without switching early', () {
      final prepareBlock = _methodBlock(source, '_startPreparingNextSource');
      final nearEndBlock = _methodBlock(
        source,
        '_prepareNextSourceWhenNearEnd',
      );

      expect(source, contains('HMStreamingData? _preparedNextStreamInfo;'));
      expect(nearEndBlock, contains('const Duration(seconds: 5)'));
      expect(nearEndBlock, contains('_resetPreparedNextSource();'));
      expect(prepareBlock, contains('_sourceInfoForPlayback'));
      expect(prepareBlock, contains('generation != _playbackGeneration'));
      expect(prepareBlock, isNot(contains('mediaItem.add')));
      expect(prepareBlock, isNot(contains('_player.stop')));
      expect(prepareBlock, isNot(contains('_player.play')));
    });

    test(
      'completion handling is deferred out of synchronous player streams',
      () {
        final scheduleBlock = _methodBlock(
          source,
          '_scheduleCompletionHandling',
        );
        final eventBlock = _methodBlock(
          source,
          '_notifyAudioHandlerAboutPlaybackEvents',
        );
        final listenerBlock = _methodBlock(
          source,
          '_listenToPlaybackForNextSong',
        );

        expect(scheduleBlock, contains('scheduleMicrotask'));
        expect(
          scheduleBlock,
          contains(
            '_handlePlaybackCompleted(allowEndPosition: allowEndPosition)',
          ),
        );
        expect(
          eventBlock,
          isNot(contains('unawaited(_handlePlaybackCompleted())')),
        );
        expect(
          listenerBlock,
          isNot(contains('await _handlePlaybackCompleted()')),
        );
      },
    );

    test(
      'source switching keeps the Android media session alive until new audio starts',
      () {
        final eventBlock = _methodBlock(
          source,
          '_notifyAudioHandlerAboutPlaybackEvents',
        );
        final playByIndex = _caseBlock(source, 'playByIndex');
        final setSourceNPlay = _caseBlock(source, 'setSourceNPlay');

        expect(source, contains('bool _sourceSwitchInProgress = false;'));
        expect(source, contains('bool _sourceSwitchWasPlaying = false;'));
        expect(eventBlock, contains('_sourceSwitchInProgress'));
        expect(eventBlock, contains('_sourceSwitchWasPlaying'));
        expect(eventBlock, contains('isSongLoading'));
        expect(eventBlock, contains('AudioProcessingState.loading'));
        expect(eventBlock, contains('AudioProcessingState.ready'));
        final processingStateIndex = eventBlock.indexOf(
          'processingState: preservingMediaSession',
        );
        final loadingFallbackIndex = eventBlock.indexOf(
          ': isSongLoading',
          processingStateIndex,
        );
        expect(processingStateIndex, greaterThanOrEqualTo(0));
        expect(
          loadingFallbackIndex,
          greaterThan(processingStateIndex),
          reason:
              'an existing Android session must remain playing, not connecting',
        );
        expect(eventBlock, contains('updatePosition = isSongLoading'));
        expect(eventBlock, contains('bufferedPosition = isSongLoading'));
        expect(
          eventBlock,
          contains('event.processingState == ProcessingState.ready'),
        );
        expect(eventBlock, contains('!isSongLoading'));
        expect(eventBlock, contains('_player.playing'));
        expect(
          playByIndex,
          contains('processingState: AudioProcessingState.loading'),
        );
        expect(playByIndex, contains('updatePosition: Duration.zero'));
        expect(playByIndex, contains('bufferedPosition: Duration.zero'));
        expect(
          setSourceNPlay,
          contains('processingState: AudioProcessingState.loading'),
        );
        expect(setSourceNPlay, contains('updatePosition: Duration.zero'));
        expect(setSourceNPlay, contains('bufferedPosition: Duration.zero'));
        expect(playByIndex, contains('_beginSourceSwitch();'));
        expect(playByIndex, contains('_endSourceSwitch();'));
        expect(
          playByIndex,
          contains('_finishSourceSwitchAfterPlaybackRequest();'),
        );
        expect(setSourceNPlay, contains('_beginSourceSwitch();'));
        expect(
          setSourceNPlay,
          contains('_finishSourceSwitchAfterPlaybackRequest();'),
        );
        final finishBlock = _methodBlock(
          source,
          '_finishSourceSwitchAfterPlaybackRequest',
        );
        expect(finishBlock, contains('if (!_sourceSwitchWasPlaying)'));
        expect(finishBlock, contains('_endSourceSwitch();'));
        expect(source, isNot(contains('_endSourceSwitch(defer: true)')));
      },
    );

    test('playback checks offline sources before network resolution', () {
      final sourceInfoBlock = _methodBlock(source, '_sourceInfoForPlayback');
      final offlineBlock = _methodBlock(source, '_offlineStreamInfoForSong');
      final playByIndex = _caseBlock(source, 'playByIndex');

      expect(playByIndex, contains('_sourceInfoForPlayback'));
      expect(sourceInfoBlock, contains('_offlineStreamInfoForSong'));
      expect(sourceInfoBlock, contains('_streamInfoForSong'));
      expect(
        sourceInfoBlock.indexOf('_offlineStreamInfoForSong'),
        lessThan(sourceInfoBlock.indexOf('_streamInfoForSong')),
      );
      expect(offlineBlock, contains('_downloadedStreamInfoForSong'));
      expect(offlineBlock, contains('_cachedStreamInfoForSong'));
      expect(offlineBlock, contains('_isLocalSourceUrl'));
      expect(
        offlineBlock.indexOf('_downloadedStreamInfoForSong'),
        lessThan(offlineBlock.indexOf('_cachedStreamInfoForSong')),
      );
    });

    test('stale playback requests are ignored after a newer switch', () {
      final playByIndex = _caseBlock(source, 'playByIndex');
      final setSourceNPlay = _caseBlock(source, 'setSourceNPlay');

      expect(source, contains('int _playbackGeneration = 0;'));
      expect(
        playByIndex,
        contains('final requestGeneration = ++_playbackGeneration;'),
      );
      expect(playByIndex, contains('requestGeneration != _playbackGeneration'));
      expect(
        setSourceNPlay,
        contains('final requestGeneration = ++_playbackGeneration;'),
      );
      expect(
        setSourceNPlay,
        contains('requestGeneration != _playbackGeneration'),
      );
    });

    test('android playback buffering is bounded to avoid heap spikes', () {
      expect(source, contains('static const _androidTargetBufferBytes'));
      expect(source, contains('maxBufferDuration: Duration(seconds: 45)'));
      expect(
        source,
        contains('bufferForPlaybackDuration: Duration(milliseconds: 200)'),
      );
      expect(
        source,
        contains(
          'bufferForPlaybackAfterRebufferDuration: Duration(seconds: 2)',
        ),
      );
      expect(source, contains('targetBufferBytes: _androidTargetBufferBytes'));
      expect(
        source,
        isNot(contains('maxBufferDuration: Duration(seconds: 120)')),
      );
      expect(
        source,
        isNot(
          contains('bufferForPlaybackDuration: Duration(milliseconds: 500)'),
        ),
      );
    });

    test('Resolver pool is warmed and disposed with the audio service', () {
      final initBlock = _methodBlock(source, '_init');
      final scheduleBlock = _methodBlock(source, '_schedulePreloadWindow');
      final disposeCase = _caseBlock(source, 'dispose');

      expect(initBlock, contains('_resolverPlaybackClient.warmUp()'));
      expect(scheduleBlock, contains('_resolverPlaybackClient.warmUp()'));
      expect(disposeCase, contains('_resolverPlaybackClient.dispose()'));
    });

    test('android notification artwork is downscaled before decoding', () {
      expect(source, contains('const _androidNotificationArtSize = 256;'));
      expect(
        source,
        contains('artDownscaleWidth: _androidNotificationArtSize'),
      );
      expect(
        source,
        contains('artDownscaleHeight: _androidNotificationArtSize'),
      );
    });

    test('completion delegates queue advancement to skipToNext', () {
      final block = _methodBlock(source, '_handlePlaybackCompleted');

      expect(block, contains('await skipToNext();'));
      expect(block, isNot(contains('await _player.seek(Duration.zero);')));
      expect(block, isNot(contains('await _player.play();')));
    });

    test('queue end without loop pauses at the start instead of replaying', () {
      final block = _methodBlock(source, 'skipToNext');
      final queueLoopBranch = block.indexOf(
        '} else if (queueLoopModeEnabled) {',
      );
      final queueEndBranch = block.indexOf('} else {', queueLoopBranch);
      final queueEndBlock = block.substring(queueEndBranch);

      expect(queueEndBlock, contains('await _player.seek(Duration.zero);'));
      expect(queueEndBlock, contains('await pause();'));
      expect(queueEndBlock, isNot(contains('await _player.play();')));
      expect(block, contains('Completion reached queue end'));
    });

    test('downloaded stream lookup falls back when metadata is incomplete', () {
      final block = _methodBlock(source, 'checkNGetUrl');

      expect(block, contains('song == null'));
      expect(block, contains('path is! String || path.isEmpty'));
      expect(block, contains('streamInfoJson is List'));
      expect(block, contains('Map<String, dynamic>.from'));
      expect(block, contains('offlineReplacementUrl: true'));
    });
  });
}

String _caseBlock(String source, String caseName) {
  final caseStart = source.indexOf("case '$caseName':");
  expect(caseStart, isNot(-1), reason: "Missing $caseName case");

  final nextCase = source.indexOf('\n      case ', caseStart + 1);
  final switchEnd = source.indexOf('\n    }\n', caseStart + 1);
  final caseEnd = nextCase == -1 ? switchEnd : nextCase;
  expect(caseEnd, isNot(-1), reason: "Could not find end of $caseName case");

  return source.substring(caseStart, caseEnd);
}

String _methodBlock(String source, String methodName) {
  var methodStart = source.indexOf('void $methodName(');
  if (methodStart == -1) {
    methodStart = source.indexOf('Future<void> $methodName(');
  }
  if (methodStart == -1) {
    methodStart = source.indexOf('Future<HMStreamingData> $methodName(');
  }
  if (methodStart == -1) {
    methodStart = source.indexOf('Future<HMStreamingData?> $methodName(');
  }
  if (methodStart == -1) {
    methodStart = source.indexOf('int $methodName(');
  }
  if (methodStart == -1) {
    methodStart = source.indexOf('bool $methodName(');
  }
  if (methodStart == -1) {
    methodStart = source.indexOf('Duration? $methodName(');
  }
  expect(methodStart, isNot(-1), reason: 'Missing $methodName');
  final bodyStart = _methodBodyStart(source, methodStart);
  expect(bodyStart, isNot(-1), reason: 'Missing body for $methodName');

  var depth = 0;
  for (var index = bodyStart; index < source.length; index++) {
    final char = source[index];
    if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
      if (depth == 0) {
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

bool _usesClassicOneSongSourceFlow(String block) {
  final stopIndex = block.indexOf('await _player.stop();');
  final clearIndex = block.indexOf('await _playList.clear();');
  if (stopIndex == -1 || clearIndex == -1 || stopIndex > clearIndex)
    return false;

  final addIndex = block.indexOf('await _playList.add', clearIndex);
  if (addIndex == -1) return false;

  final loadStartIndex = block.indexOf(
    'await _loadCurrentSourceFromStartAndPlay();',
    addIndex,
  );

  return loadStartIndex != -1 && addIndex < loadStartIndex;
}

bool _loadsThenClearsLoadingThenEmitsStarted(String block) {
  final loadStartIndex = block.indexOf(
    'await _loadCurrentSourceFromStartAndPlay();',
  );
  if (loadStartIndex == -1) return false;

  final clearLoadingIndex = block.indexOf(
    'isSongLoading = false;',
    loadStartIndex,
  );
  if (clearLoadingIndex == -1) return false;

  final emitStartedIndex = block.indexOf(
    '_emitSourceStartedSnapshot();',
    clearLoadingIndex,
  );

  return emitStartedIndex != -1;
}
