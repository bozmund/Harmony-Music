import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/app/providers/controller_providers.dart';
import 'package:harmonymusic/app/providers/service_providers.dart';
import 'package:harmonymusic/domain/repositories/settings_repository.dart';
import 'package:harmonymusic/services/cloud/cloud_playback_gateway.dart';
import 'package:harmonymusic/services/cloud/cloud_playback_receiver.dart';
import 'package:harmonymusic/services/cloud/harmony_cloud_client.dart';
import 'package:harmonymusic/services/cloud/playback_socket_client.dart';
import 'package:harmonymusic/services/metadata/playback_metadata_resolver.dart';
import 'package:harmonymusic/services/playback_command_service.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late _PlaybackBridge bridge;
  late _MemorySettings androidSettings;
  late _MemorySettings windowsSettings;
  late _RemoteAudioHandler androidAudio;
  late _RemoteAudioHandler windowsAudio;
  late PlaybackCommandService androidCommands;
  late PlaybackCommandService windowsCommands;
  late CloudPlaybackReceiver windowsReceiver;
  late _FixtureMetadata windowsMetadata;

  setUp(() async {
    bridge = _PlaybackBridge();
    androidSettings = _MemorySettings();
    windowsSettings = _MemorySettings(
      shuffle: true,
      repeat: true,
      queueLoop: true,
    );
    androidAudio = _RemoteAudioHandler();
    windowsAudio = _RemoteAudioHandler(
      shuffle: true,
      repeat: true,
      queueLoop: true,
    );
    androidCommands = PlaybackCommandService(
      audioHandler: androidAudio,
      settingsRepository: androidSettings,
      cloudSync: bridge.gateway('android'),
    );
    windowsCommands = PlaybackCommandService(
      audioHandler: windowsAudio,
      settingsRepository: windowsSettings,
      cloudSync: bridge.gateway('windows'),
    );
    windowsMetadata = _FixtureMetadata();
    windowsReceiver = CloudPlaybackReceiver(
      bridge.gateway('windows'),
      windowsMetadata,
      windowsCommands,
      bridge.socket('windows'),
    );
    await windowsReceiver.start();
  });

  tearDown(() {
    windowsReceiver.dispose();
  });

  Future<void> startAndroidSession() async {
    final sessionId = await androidCommands.startSharedSession(
      targetDeviceId: 'windows',
      queue: _songs,
      index: 0,
      positionMs: 0,
      playing: true,
    );
    expect(sessionId, isNotNull);
    await _waitUntil(
      () =>
          windowsAudio.mediaItem.value?.id == _songs.first.id &&
          windowsAudio.playbackState.value.processingState ==
              AudioProcessingState.ready,
      reason: 'the Windows target should finish the initial handoff',
    );
  }

  testWidgets(
    'handoff replaces target modes and reconnect does not restart playback',
    (_) async {
      await startAndroidSession();

      expect(windowsSettings.shuffle, isFalse);
      expect(windowsSettings.repeat, isFalse);
      expect(windowsSettings.queueLoop, isFalse);
      expect(
        windowsAudio.playbackState.value.shuffleMode,
        AudioServiceShuffleMode.none,
      );
      expect(
        windowsAudio.playbackState.value.repeatMode,
        AudioServiceRepeatMode.none,
      );
      expect(windowsAudio.queueLoop, isFalse);

      final startsBeforeReconnect = windowsAudio.playedSongIds.length;
      await windowsReceiver.refreshSession();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(windowsAudio.playedSongIds.length, startsBeforeReconnect);
    },
  );

  testWidgets(
    'remote next selects the exact cloud song and leaves loading by itself',
    (_) async {
      await startAndroidSession();
      windowsAudio.completeLoadsAutomatically = false;

      await androidCommands.next(desiredVideoId: _songs[1].id);
      await _waitUntil(
        () =>
            windowsAudio.mediaItem.value?.id == _songs[1].id &&
            windowsAudio.playbackState.value.processingState ==
                AudioProcessingState.loading,
        reason: 'Windows should enter loading for the requested second song',
      );

      windowsAudio.reportBuffering(const Duration(milliseconds: 500));
      await Future<void>.delayed(
        CloudPlaybackReceiver.progressInterval +
            const Duration(milliseconds: 100),
      );
      final loading = bridge.lastProgressFrom('windows');
      expect(loading?['currentSongId'], _songs[1].id);
      expect(loading?['loading'], isTrue);
      expect(loading?['positionMs'], 0);

      windowsAudio.completePendingLoad();
      await _waitUntil(
        () {
          final frame = bridge.lastProgressFrom('windows');
          return windowsAudio.playbackState.value.processingState ==
                  AudioProcessingState.ready &&
              frame?['currentSongId'] == _songs[1].id &&
              frame?['loading'] == false;
        },
        reason: 'the target should leave loading without a pause/play command',
      );
      expect(windowsAudio.pauseCallCount, 0);
      expect(windowsAudio.playCallCount, greaterThan(0));
      expect(
        windowsReceiver.diagnostics()['lastRequestedNextSongId'],
        _songs[1].id,
      );
    },
  );

  testWidgets('legacy next uses the authoritative cloud queue', (_) async {
    await startAndroidSession();

    await androidCommands.next();
    await _waitUntil(
      () => windowsAudio.mediaItem.value?.id == _songs[1].id,
      reason: 'a next command without a song id should still advance',
    );

    expect(windowsAudio.skipToNextCallCount, 0);
    expect(windowsAudio.playedSongIds.last, _songs[1].id);
  });

  testWidgets(
    'play next inserts after the remote current song and next plays it',
    (_) async {
      final initialQueue = [..._songs, _playNextQueueTail];
      windowsMetadata.items = [...initialQueue, _playNextSong];

      final sessionId = await androidCommands.startSharedSession(
        targetDeviceId: 'windows',
        queue: initialQueue,
        index: 1,
        positionMs: 0,
        playing: true,
      );
      expect(sessionId, isNotNull);
      await _waitUntil(
        () =>
            windowsAudio.mediaItem.value?.id == _songs[1].id &&
            windowsAudio.queue.value.map((song) => song.id).join('|') ==
                initialQueue.map((song) => song.id).join('|'),
        reason: 'Windows should start from the middle of the shared queue',
      );

      await androidCommands.addPlayNextItem(_playNextSong);
      final expectedQueue = [
        _songs[0],
        _songs[1],
        _playNextSong,
        _playNextQueueTail,
      ];
      await _waitUntil(
        () =>
            windowsAudio.queue.value.map((song) => song.id).join('|') ==
            expectedQueue.map((song) => song.id).join('|'),
        reason:
            'Play next should insert directly after the remote current song',
      );

      await androidCommands.next(desiredVideoId: _playNextSong.id);
      await _waitUntil(
        () => windowsAudio.mediaItem.value?.id == _playNextSong.id,
        reason: 'Next should use the queue just installed by Play next',
      );
    },
  );

  testWidgets('playlist second-song tap stays selected during remote shuffle', (
    _,
  ) async {
    final playlist = _replacementScenarios[1].queue;
    windowsMetadata.items = [..._songs, ...playlist];
    androidSettings.shuffle = true;

    await androidCommands.startSharedSession(
      targetDeviceId: 'windows',
      queue: _songs,
      index: 0,
      positionMs: 0,
      playing: true,
    );
    await _waitUntil(
      () => windowsAudio.mediaItem.value?.id == _songs.first.id,
      reason: 'Windows should accept the initial handoff',
    );

    // This is the exact command sequence used by playPlayListSong when
    // shuffle is enabled: install the tapped playlist, shuffle around the
    // tapped index, then play the selected song now at queue index zero.
    await androidCommands.updateQueue(playlist);
    await androidCommands.shuffleFromIndex(1);
    await androidCommands.playByIndex(0);
    await _waitUntil(
      () => windowsAudio.mediaItem.value?.id == playlist[1].id,
      reason: 'tapping playlist item two must play item two when shuffle is on',
    );

    final handoff = bridge.commands.lastWhere(
      (command) =>
          command['sourceDeviceId'] == 'android' &&
          command['commandType'] == 'handoff',
    );
    final payload = handoff['payload'] as Map<String, Object?>;
    expect(payload['currentSongId'], playlist[1].id);
    expect((payload['queueIds'] as List).first, playlist[1].id);
  });

  testWidgets('older handoffs without mode fields keep the target modes', (
    _,
  ) async {
    await bridge
        .gateway('android')
        .sendSessionCommand(
          targetDeviceId: 'windows',
          type: 'handoff',
          payload: {
            'queueIds': _songs.map((song) => song.id).toList(),
            'index': 0,
            'currentSongId': _songs.first.id,
            'positionMs': 0,
            'playing': true,
          },
        );
    await _waitUntil(
      () => windowsAudio.mediaItem.value?.id == _songs.first.id,
      reason: 'the legacy handoff should still start playback',
    );

    expect(windowsSettings.shuffle, isTrue);
    expect(windowsSettings.repeat, isTrue);
    expect(windowsSettings.queueLoop, isTrue);
  });

  testWidgets('legacy next stops at the end unless queue-loop wraps it', (
    _,
  ) async {
    await startAndroidSession();
    await androidCommands.next(desiredVideoId: _songs[1].id);
    await _waitUntil(
      () => windowsAudio.mediaItem.value?.id == _songs[1].id,
      reason: 'the target should reach the final queue item',
    );

    final startsAtEnd = windowsAudio.playedSongIds.length;
    await androidCommands.next();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(windowsAudio.mediaItem.value?.id, _songs[1].id);
    expect(windowsAudio.playedSongIds.length, startsAtEnd);

    await androidCommands.setQueueLoopMode(true);
    await _waitUntil(
      () => windowsSettings.queueLoop,
      reason: 'queue-loop should reach the target',
    );
    await androidCommands.next();
    await _waitUntil(
      () => windowsAudio.mediaItem.value?.id == _songs.first.id,
      reason: 'queue-loop should wrap legacy next to the first item',
    );
  });

  testWidgets(
    'target auto-advance publishes the new song and remote previous returns',
    (_) async {
      await startAndroidSession();
      await _waitUntil(
        () => windowsAudio.queue.value.length == _songs.length,
        reason: 'the target should finish widening the shared queue',
      );

      await windowsAudio.advanceAutomatically();
      await _waitUntil(
        () =>
            bridge.lastProgressFrom('windows')?['currentSongId'] ==
            _songs[1].id,
        timeout:
            CloudPlaybackReceiver.progressInterval + const Duration(seconds: 1),
        reason: 'automatic target advancement should reach controllers',
      );

      await bridge
          .gateway('android')
          .sendSessionCommand(
            targetDeviceId: 'windows',
            type: 'previous',
            payload: {
              'intent': 'selectPrevious',
              'desiredVideoId': _songs.first.id,
            },
          );
      await _waitUntil(
        () => windowsAudio.mediaItem.value?.id == _songs.first.id,
        reason: 'remote previous should return to the exact preceding song',
      );
    },
  );

  testWidgets(
    'mode commands persist on both devices and publish durable session state',
    (_) async {
      await startAndroidSession();

      await androidCommands.toggleShuffle(enabled: false);
      await androidCommands.toggleLoop(enabled: false);
      await androidCommands.setQueueLoopMode(true);
      await _waitUntil(
        () =>
            windowsSettings.shuffle &&
            windowsSettings.repeat &&
            windowsSettings.queueLoop,
        reason: 'the Windows target should apply all controller mode commands',
      );
      await _waitUntil(
        () {
          final state = bridge.sessionState;
          return state?['shuffle'] == true &&
              state?['repeat'] == true &&
              state?['queueLoop'] == true;
        },
        timeout: const Duration(seconds: 2),
        reason: 'the target should persist the modes in the shared session',
      );

      expect(androidSettings.shuffle, isTrue);
      expect(androidSettings.repeat, isTrue);
      expect(androidSettings.queueLoop, isTrue);
      expect(bridge.lastProgressFrom('windows'), containsPair('shuffle', true));
      expect(bridge.lastProgressFrom('windows'), containsPair('repeat', true));
      expect(
        bridge.lastProgressFrom('windows'),
        containsPair('queueLoop', true),
      );
    },
  );

  for (final scenario in _replacementScenarios) {
    testWidgets(
      'phone Home selection replaces Windows with ${scenario.name} queue',
      (tester) async {
        windowsMetadata.items = [..._songs, ...scenario.queue];
        final source = await bootTestApp(
          tester,
          musicService: _HomeSelectionMusicService({
            scenario.queue.first.id: scenario.queue,
          }),
          playbackGateway: bridge.gateway('android'),
        );
        final sourceController = source.container.read(
          playerControllerProvider,
        );
        final sourceCommands = source.container.read(
          playbackCommandServiceProvider,
        );

        final sessionId = await sourceCommands.startSharedSession(
          targetDeviceId: 'windows',
          queue: _songs,
          index: 0,
          positionMs: 0,
          playing: true,
        );
        expect(sessionId, isNotNull);
        await _waitUntil(
          () =>
              windowsAudio.mediaItem.value?.id == _songs.first.id &&
              windowsAudio.playbackState.value.processingState ==
                  AudioProcessingState.ready,
          reason: 'Windows should finish the initial phone handoff',
        );

        // This is the same controller path used after a Home-screen song tap:
        // it resolves the selected song's watch queue, sends the remote queue
        // update, and then hands the selected source to Windows.
        windowsAudio.completeLoadsAutomatically = false;
        await sourceController.pushSongToQueue(scenario.queue.first);
        await _waitUntil(
          () =>
              windowsAudio.mediaItem.value?.id == scenario.queue.first.id &&
              windowsAudio.playbackState.value.processingState ==
                  AudioProcessingState.loading,
          reason: 'Windows should immediately select the new Home song',
        );
        expect(windowsAudio.playbackState.value.updatePosition, Duration.zero);
        expect(windowsAudio.queue.value.map((song) => song.id), [
          scenario.queue.first.id,
        ]);

        windowsAudio.completePendingLoad();
        await _waitUntil(
          () =>
              windowsAudio.playbackState.value.processingState ==
                  AudioProcessingState.ready &&
              windowsAudio.queue.value.map((song) => song.id).join('|') ==
                  scenario.queue.map((song) => song.id).join('|'),
          reason: 'Windows should widen to the selected Home song queue',
        );
        expect(
          windowsAudio.queue.value.map((song) => song.id),
          scenario.queue.map((song) => song.id),
        );
        expect(
          windowsAudio.playedItems.last.extras?['url'],
          scenario.queue.first.extras?['url'],
          reason: 'Windows should receive the selected song source type',
        );
        expect(
          windowsAudio.queue.value.map((song) => song.id),
          isNot(contains(_songs.first.id)),
        );

        await _waitUntil(
          () {
            final state = bridge.sessionState;
            return state?['currentSongId'] == scenario.queue.first.id &&
                state?['queueIds'] is List &&
                List<String>.from(state?['queueIds'] as List).join('|') ==
                    scenario.queue.map((song) => song.id).join('|');
          },
          timeout: const Duration(seconds: 4),
          reason: 'the durable session should replace the old queue too',
        );

        windowsAudio.completeLoadsAutomatically = true;
        await sourceCommands.next(desiredVideoId: scenario.queue[1].id);
        await _waitUntil(
          () =>
              windowsAudio.mediaItem.value?.id == scenario.queue[1].id &&
              windowsAudio.playbackState.value.processingState ==
                  AudioProcessingState.ready,
          reason: 'Windows should advance through the replacement queue',
        );
        expect(
          windowsAudio.playedItems.last.extras?['url'],
          scenario.queue[1].extras?['url'],
          reason: 'Windows should use the expected next-song source type',
        );
      },
    );
  }

  testWidgets(
    'phone local-only selections resolve to Windows network sources',
    (tester) async {
      windowsMetadata.items = [
        ..._songs,
        ..._windowsOnlineFirstSelection,
        ..._windowsOnlineSecondSelection,
      ];
      final source = await bootTestApp(
        tester,
        musicService: _HomeSelectionMusicService({
          _phoneLocalFirstSelection.first.id: _phoneLocalFirstSelection,
          _phoneLocalSecondSelection.first.id: _phoneLocalSecondSelection,
        }),
        playbackGateway: bridge.gateway('android'),
      );
      final sourceController = source.container.read(playerControllerProvider);
      final sourceCommands = source.container.read(
        playbackCommandServiceProvider,
      );

      await sourceCommands.startSharedSession(
        targetDeviceId: 'windows',
        queue: _songs,
        index: 0,
        positionMs: 0,
        playing: true,
      );
      await _waitUntil(
        () =>
            windowsAudio.mediaItem.value?.id == _songs.first.id &&
            windowsAudio.playbackState.value.processingState ==
                AudioProcessingState.ready,
        reason: 'Windows should be ready for Android remote selections',
      );

      // Both source items are local files on Android. The handoff messages
      // contain their shared ids only, so Windows must resolve its own sources.
      await sourceController.pushSongToQueue(_phoneLocalFirstSelection.first);
      await _waitUntil(
        () =>
            windowsAudio.mediaItem.value?.id ==
                _windowsOnlineFirstSelection.first.id &&
            windowsAudio.playbackState.value.processingState ==
                AudioProcessingState.ready,
        reason: 'Windows should play the first phone-selected song',
      );
      expect(
        windowsAudio.playedItems.last.extras?['url'],
        _windowsOnlineFirstSelection.first.extras?['url'],
      );
      expect(
        windowsAudio.playedItems.last.extras?['url'],
        isNot(startsWith('file://')),
      );
      expect(
        windowsAudio.queue.value.map((item) => item.id),
        _windowsOnlineFirstSelection.map((item) => item.id),
      );

      final firstSelectionMessage = bridge.commands.lastWhere(
        (message) =>
            message['sourceDeviceId'] == 'android' &&
            message['commandType'] == 'handoff',
      );
      final firstSelectionPayload =
          firstSelectionMessage['payload'] as Map<String, Object?>;
      expect(
        firstSelectionPayload['queueIds'],
        _phoneLocalFirstSelection.map((item) => item.id),
        reason: 'Android should send shared queue ids, not its file paths',
      );

      await sourceController.pushSongToQueue(_phoneLocalSecondSelection.first);
      await _waitUntil(
        () =>
            windowsAudio.mediaItem.value?.id ==
                _windowsOnlineSecondSelection.first.id &&
            windowsAudio.playbackState.value.processingState ==
                AudioProcessingState.ready,
        reason: 'Windows should replace playback after the second phone tap',
      );
      expect(
        windowsAudio.playedItems.last.extras?['url'],
        _windowsOnlineSecondSelection.first.extras?['url'],
      );
      expect(
        windowsAudio.playedItems.last.extras?['url'],
        isNot(startsWith('file://')),
      );
      expect(
        windowsAudio.queue.value.map((item) => item.id),
        _windowsOnlineSecondSelection.map((item) => item.id),
      );
      await _waitUntil(
        () =>
            bridge.sessionState?['queueIds'] is List &&
            List<String>.from(
                  bridge.sessionState?['queueIds'] as List,
                ).join('|') ==
                _windowsOnlineSecondSelection.map((item) => item.id).join('|'),
        timeout: const Duration(seconds: 4),
        reason: 'the second phone tap should persist the Windows queue',
      );
    },
  );

  testWidgets(
    'Windows starts after a delayed online source for a phone-local selection',
    (tester) async {
      windowsMetadata.items = [..._songs, ..._windowsOnlineFirstSelection];
      final source = await bootTestApp(
        tester,
        musicService: _HomeSelectionMusicService({
          _phoneLocalFirstSelection.first.id: _phoneLocalFirstSelection,
        }),
        playbackGateway: bridge.gateway('android'),
      );
      final controller = source.container.read(playerControllerProvider);
      final commands = source.container.read(playbackCommandServiceProvider);
      await commands.startSharedSession(
        targetDeviceId: 'windows',
        queue: _songs,
        index: 0,
        positionMs: 0,
        playing: true,
      );
      await _waitUntil(
        () =>
            windowsAudio.playbackState.value.processingState ==
            AudioProcessingState.ready,
        reason: 'Windows should accept the initial handoff',
      );

      windowsAudio.completeLoadsAutomatically = false;
      await controller.pushSongToQueue(_phoneLocalFirstSelection.first);
      await _waitUntil(
        () =>
            windowsAudio.mediaItem.value?.id ==
                _windowsOnlineFirstSelection.first.id &&
            windowsAudio.playbackState.value.processingState ==
                AudioProcessingState.loading,
        reason: 'Windows should show the phone-selected online song as loading',
      );
      expect(windowsAudio.playbackState.value.updatePosition, Duration.zero);
      expect(
        windowsAudio.playedItems.last.extras?['url'],
        _windowsOnlineFirstSelection.first.extras?['url'],
        reason: 'Windows must use its own network source while loading',
      );

      windowsAudio.completePendingLoad();
      await _waitUntil(
        () =>
            windowsAudio.mediaItem.value?.id ==
                _windowsOnlineFirstSelection.first.id &&
            windowsAudio.playbackState.value.processingState ==
                AudioProcessingState.ready,
        reason: 'the delayed Windows source should start without another tap',
      );
    },
  );

  testWidgets('duplicate in-flight handoffs join one Windows start', (_) async {
    windowsAudio.completeLoadsAutomatically = false;
    final payload = {
      'queueIds': _songs.map((song) => song.id).toList(),
      'index': 0,
      'currentSongId': _songs.first.id,
      'positionMs': 0,
      'playing': true,
    };

    await bridge
        .gateway('android')
        .sendSessionCommand(
          targetDeviceId: 'windows',
          type: 'handoff',
          payload: payload,
        );
    await _waitUntil(
      () =>
          windowsAudio.mediaItem.value?.id == _songs.first.id &&
          windowsAudio.playbackState.value.processingState ==
              AudioProcessingState.loading,
      reason: 'the first handoff should start loading',
    );

    await bridge
        .gateway('android')
        .sendSessionCommand(
          targetDeviceId: 'windows',
          type: 'handoff',
          payload: payload,
        );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(
      windowsAudio.playedSongIds,
      [_songs.first.id],
      reason: 'a duplicate handoff must join the first load, not restart it',
    );

    windowsAudio.completePendingLoad();
    await _waitUntil(
      () =>
          windowsAudio.playbackState.value.processingState ==
          AudioProcessingState.ready,
      reason: 'the original start should complete normally',
    );
  });

  testWidgets(
    'a newer Android tap supersedes a stalled Windows online source',
    (tester) async {
      addTearDown(windowsAudio.completePendingLoad);
      windowsMetadata.items = [
        ..._songs,
        ..._windowsOnlineFirstSelection,
        ..._windowsOnlineSecondSelection,
      ];
      final source = await bootTestApp(
        tester,
        musicService: _HomeSelectionMusicService({
          _phoneLocalFirstSelection.first.id: _phoneLocalFirstSelection,
          _phoneLocalSecondSelection.first.id: _phoneLocalSecondSelection,
        }),
        playbackGateway: bridge.gateway('android'),
      );
      final controller = source.container.read(playerControllerProvider);
      final commands = source.container.read(playbackCommandServiceProvider);
      await commands.startSharedSession(
        targetDeviceId: 'windows',
        queue: _songs,
        index: 0,
        positionMs: 0,
        playing: true,
      );
      await _waitUntil(
        () =>
            windowsAudio.playbackState.value.processingState ==
            AudioProcessingState.ready,
        reason: 'Windows should accept the initial handoff',
      );

      windowsAudio.completeLoadsAutomatically = false;
      await controller.pushSongToQueue(_phoneLocalFirstSelection.first);
      await _waitUntil(
        () =>
            windowsAudio.mediaItem.value?.id ==
                _windowsOnlineFirstSelection.first.id &&
            windowsAudio.playbackState.value.processingState ==
                AudioProcessingState.loading,
        reason: 'the first online source should be visibly stalled',
      );

      // This is a second real Android controller action. Its queue-update and
      // handoff messages must supersede the unresolved first Windows load.
      await controller.pushSongToQueue(_phoneLocalSecondSelection.first);
      await _waitUntil(
        () =>
            windowsAudio.mediaItem.value?.id ==
                _windowsOnlineSecondSelection.first.id &&
            windowsAudio.playbackState.value.processingState ==
                AudioProcessingState.loading,
        reason: 'Windows should replace the stalled source with the newer tap',
      );
      expect(
        windowsAudio.playedItems.last.extras?['url'],
        _windowsOnlineSecondSelection.first.extras?['url'],
      );

      windowsAudio.completePendingLoad();
      await _waitUntil(
        () =>
            windowsAudio.mediaItem.value?.id ==
                _windowsOnlineSecondSelection.first.id &&
            windowsAudio.playbackState.value.processingState ==
                AudioProcessingState.ready,
        reason: 'the latest selection should start after its source settles',
      );
    },
  );

  testWidgets(
    'late search queue lookup cannot replace a newer Recently Played tap',
    (tester) async {
      windowsMetadata.items = [
        ..._songs,
        ..._windowsOnlineFirstSelection,
        ..._windowsOnlineSecondSelection,
      ];
      final musicService = _DelayedHomeSelectionMusicService({
        _phoneLocalFirstSelection.first.id: _phoneLocalFirstSelection,
        _phoneLocalSecondSelection.first.id: _phoneLocalSecondSelection,
      })..hold(_phoneLocalFirstSelection.first.id);
      final source = await bootTestApp(
        tester,
        musicService: musicService,
        playbackGateway: bridge.gateway('android'),
      );
      final controller = source.container.read(playerControllerProvider);
      final commands = source.container.read(playbackCommandServiceProvider);
      await commands.startSharedSession(
        targetDeviceId: 'windows',
        queue: _songs,
        index: 0,
        positionMs: 0,
        playing: true,
      );
      await _waitUntil(
        () =>
            windowsAudio.mediaItem.value?.id == _songs.first.id &&
            windowsAudio.playbackState.value.processingState ==
                AudioProcessingState.ready,
        reason: 'Windows should accept the initial handoff',
      );

      // Reproduce the real ordering: the searched song starts expanding its
      // watch queue, then the user opens Recently Played and taps another
      // online song before that first request returns.
      final olderSelection = controller.pushSongToQueue(
        _phoneLocalFirstSelection.first,
      );
      await musicService.waitUntilRequested(_phoneLocalFirstSelection.first.id);
      await controller.pushSongToQueue(_phoneLocalSecondSelection.first);
      await _waitUntil(
        () =>
            windowsAudio.mediaItem.value?.id ==
                _windowsOnlineSecondSelection.first.id &&
            windowsAudio.playbackState.value.processingState ==
                AudioProcessingState.ready,
        reason: 'the Recently Played tap should reach Windows first',
      );

      musicService.release(_phoneLocalFirstSelection.first.id);
      await olderSelection;
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        windowsAudio.mediaItem.value?.id,
        _windowsOnlineSecondSelection.first.id,
        reason:
            'the late search lookup belongs to an older tap and must be ignored',
      );
      expect(
        windowsAudio.queue.value.map((item) => item.id),
        _windowsOnlineSecondSelection.map((item) => item.id),
      );
      expect(
        bridge.commands
            .where(
              (message) =>
                  message['sourceDeviceId'] == 'android' &&
                  message['commandType'] == 'handoff',
            )
            .map(
              (message) =>
                  (message['payload'] as Map<String, Object?>)['currentSongId'],
            )
            .where((id) => id == _phoneLocalFirstSelection.first.id),
        isEmpty,
        reason: 'the obsolete searched-song intent must never be sent',
      );
    },
  );

  testWidgets('late older queue update cannot replace a newer Windows handoff', (
    _,
  ) async {
    final olderQueue = _replacementScenarios[0].queue;
    final newerQueue = _replacementScenarios[1].queue;
    windowsMetadata.items = [..._songs, ...olderQueue, ...newerQueue];
    final gateway = bridge.gateway('android');

    Map<String, Object?> stateFor(List<MediaItem> queue) => {
      'queueIds': queue.map((song) => song.id).toList(),
      'index': 0,
      'currentSongId': queue.first.id,
      'positionMs': 0,
      'playing': true,
    };

    // The real failure happened after Windows was already the active target.
    // A queueUpdate delivered to a disengaged device is intentionally ignored.
    await gateway.sendSessionCommand(
      targetDeviceId: 'windows',
      type: 'handoff',
      payload: stateFor(_songs),
    );
    await _waitUntil(
      () =>
          windowsAudio.mediaItem.value?.id == _songs.first.id &&
          windowsAudio.playbackState.value.processingState ==
              AudioProcessingState.ready,
      reason: 'Windows should first become the active audio target',
    );

    windowsMetadata.holdBatchContaining(olderQueue.first.id);
    // This reproduces the live ordering: queueUpdate and handoff are delivered
    // independently, and resolving the older/larger queue takes longer.
    await gateway.sendSessionCommand(
      targetDeviceId: 'windows',
      type: 'queueUpdate',
      payload: stateFor(olderQueue),
    );
    await gateway.sendSessionCommand(
      targetDeviceId: 'windows',
      type: 'handoff',
      payload: stateFor(olderQueue),
    );
    await _waitUntil(
      () => windowsAudio.mediaItem.value?.id == olderQueue.first.id,
      reason: 'the older handoff should begin before its queue resolves',
    );

    await gateway.sendSessionCommand(
      targetDeviceId: 'windows',
      type: 'queueUpdate',
      payload: stateFor(newerQueue),
    );
    await gateway.sendSessionCommand(
      targetDeviceId: 'windows',
      type: 'handoff',
      payload: stateFor(newerQueue),
    );
    await _waitUntil(
      () =>
          windowsAudio.mediaItem.value?.id == newerQueue.first.id &&
          windowsAudio.queue.value.map((song) => song.id).join('|') ==
              newerQueue.map((song) => song.id).join('|'),
      reason: 'the newer handoff should install its complete queue',
    );

    windowsMetadata.releaseBatchContaining(olderQueue.first.id);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(
      windowsAudio.mediaItem.value?.id,
      newerQueue.first.id,
      reason: 'late work from the older command must not change the song',
    );
    expect(
      windowsAudio.queue.value.map((song) => song.id),
      newerQueue.map((song) => song.id),
      reason: 'late work from the older command must not replace the queue',
    );
  });

  testWidgets('a device playing on its own advertises itself as the target', (
    _,
  ) async {
    // Without this there is nothing to join: publishing is gated on being the
    // audio target, and the only way to become one used to be accepting a
    // handoff, so a device playing alone was invisible to the account.
    bridge.gateway('windows').shareNowPlaying = true;
    await windowsAudio.updateQueue(_songs);
    windowsAudio.mediaItem.add(_songs[1]);

    await _waitUntil(
      () => bridge.targetDeviceId == 'windows',
      reason: 'playing locally should claim the session',
    );
    expect(
      (bridge.sessionState?['queueIds'] as List?)?.length,
      _songs.length,
      reason: 'the queue has to travel or a subscriber has nothing to show',
    );
    expect(bridge.sessionState?['currentSongId'], _songs[1].id);
  });

  testWidgets('a device does not advertise while sharing is off', (_) async {
    // Advertising what you are playing is a disclosure, so it is opted into.
    expect(bridge.gateway('windows').shareNowPlaying, isFalse);
    await windowsAudio.updateQueue(_songs);
    windowsAudio.mediaItem.add(_songs.first);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(bridge.targetDeviceId, isNull);
    expect(bridge.sessionState, isNull);
  });

  testWidgets('a claim never takes the session from another device', (_) async {
    // A device that merely started playing has no mandate to stop audio
    // elsewhere, which is what silently retargeting would do.
    bridge.sessionState = <String, dynamic>{'queueIds': <String>[]};
    bridge.targetDeviceId = 'android';
    bridge.gateway('windows').shareNowPlaying = true;

    await windowsAudio.updateQueue(_songs);
    windowsAudio.mediaItem.add(_songs.first);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(
      bridge.targetDeviceId,
      'android',
      reason: 'the device already producing audio keeps the session',
    );
  });
}

const _songs = [
  MediaItem(
    id: 'aaaaaaaaaaa',
    title: 'Remote Song One',
    artist: 'Fixture Artist',
    duration: Duration(minutes: 3),
  ),
  MediaItem(
    id: 'bbbbbbbbbbb',
    title: 'Remote Song Two',
    artist: 'Fixture Artist',
    duration: Duration(minutes: 4),
  ),
];

const _playNextQueueTail = MediaItem(
  id: 'ccccccccccc',
  title: 'Remote Queue Tail',
  artist: 'Fixture Artist',
  duration: Duration(minutes: 5),
);

const _playNextSong = MediaItem(
  id: 'ddddddddddd',
  title: 'Requested Play Next Song',
  artist: 'Fixture Artist',
  duration: Duration(minutes: 6),
);

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
  required String reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue, reason: reason);
}

class _FixtureMetadata implements PlaybackMetadataResolver {
  _FixtureMetadata([List<MediaItem>? items]) : items = items ?? _songs;

  List<MediaItem> items;
  final Map<String, Completer<void>> _batchHolds = {};

  void holdBatchContaining(String videoId) {
    _batchHolds[videoId] = Completer<void>();
  }

  void releaseBatchContaining(String videoId) {
    final hold = _batchHolds.remove(videoId);
    if (hold != null && !hold.isCompleted) hold.complete();
  }

  @override
  Future<MediaItem?> resolve(String videoId) async {
    for (final song in items) {
      if (song.id == videoId) return song;
    }
    return null;
  }

  @override
  Future<Map<String, MediaItem>> resolveBatch(List<String> videoIds) async {
    for (final entry in _batchHolds.entries.toList()) {
      if (videoIds.contains(entry.key)) await entry.value.future;
    }
    return {
      for (final song in items)
        if (videoIds.contains(song.id)) song.id: song,
    };
  }
}

class _PlaybackBridge {
  final Map<String, _BridgeSocket> _sockets = {};
  final List<Map<String, dynamic>> progressFrames = [];
  final List<Map<String, Object?>> commands = [];
  Map<String, dynamic>? sessionState;
  String? targetDeviceId;
  var _commandSequence = 0;

  final Map<String, _BridgeGateway> _gateways = {};

  /// One gateway per device, memoized. A fresh instance per call would mean
  /// per-device state — `shareNowPlaying` — set in a test never reaching the
  /// receiver holding its own copy.
  _BridgeGateway gateway(String deviceId) =>
      _gateways.putIfAbsent(deviceId, () => _BridgeGateway(this, deviceId));

  PlaybackSocketTransport socket(String deviceId) {
    return _sockets.putIfAbsent(deviceId, () => _BridgeSocket(this, deviceId));
  }

  Map<String, dynamic>? lastProgressFrom(String deviceId) {
    for (final frame in progressFrames.reversed) {
      if (frame['_sourceDeviceId'] == deviceId) return frame;
    }
    return null;
  }

  /// What the server does after a claim or a state write: tell every *other*
  /// device a session exists and who owns the audio. This is the frame a
  /// device subscribes to when it joins playback already in progress.
  void broadcastSessionSnapshot({required String exceptDeviceId}) {
    final state = sessionState;
    final target = targetDeviceId;
    if (state == null || target == null) return;
    for (final entry in _sockets.entries) {
      if (entry.key == exceptDeviceId) continue;
      entry.value.addFrame({
        'type': 'sessionSnapshot',
        'sessionId': 'session-$target',
        'targetDeviceId': target,
        'sequence': 1,
        'state': Map<String, Object?>.from(state),
        'positionMs': state['positionMs'] ?? 0,
        'playing': state['playing'] ?? false,
        'currentSongId': state['currentSongId'],
      });
    }
  }

  void _sendCommand(
    String sourceDeviceId,
    String targetDeviceId,
    String type,
    Map<String, Object?> payload,
  ) {
    commands.add({
      'sourceDeviceId': sourceDeviceId,
      'targetDeviceId': targetDeviceId,
      'commandType': type,
      'payload': Map<String, Object?>.from(payload),
    });
    _sockets[targetDeviceId]?.addFrame({
      'type': 'command',
      'commandId': 'command-${++_commandSequence}',
      'sourceDeviceId': sourceDeviceId,
      'targetDeviceId': targetDeviceId,
      'commandType': type,
      'payload': Map<String, Object?>.from(payload),
    });
  }

  void _fromSocket(String sourceDeviceId, Map<String, Object?> frame) {
    if (frame['type'] != 'progress') return;
    final recorded = <String, dynamic>{
      ...frame,
      '_sourceDeviceId': sourceDeviceId,
    };
    progressFrames.add(recorded);
    for (final entry in _sockets.entries) {
      if (entry.key != sourceDeviceId) entry.value.addFrame(recorded);
    }
  }
}

class _BridgeGateway implements CloudPlaybackGateway {
  _BridgeGateway(this.bridge, this.deviceId);

  final _PlaybackBridge bridge;

  @override
  final String deviceId;

  /// Whether this fake device advertises what it is playing. Off by default,
  /// matching the real preference, so existing scenarios are unaffected.
  @override
  bool shareNowPlaying = false;

  @override
  Future<String?> claimPlaybackSession({
    required Map<String, Object?> state,
  }) async {
    // Mirrors the server: a claim never takes a session owned by someone else.
    if (bridge.targetDeviceId != null && bridge.targetDeviceId != deviceId) {
      return null;
    }
    bridge.sessionState = state;
    bridge.targetDeviceId = deviceId;
    // The broadcast is the point — it is what lets another device notice a
    // session exists and subscribe to it.
    bridge.broadcastSessionSnapshot(exceptDeviceId: deviceId);
    return 'claimed-$deviceId';
  }

  @override
  Future<void> acknowledgePlaybackCommand({
    required String commandId,
    required bool applied,
  }) async {}

  @override
  Future<void> endPlaybackSession() async {
    bridge.sessionState = null;
    bridge.targetDeviceId = null;
  }

  @override
  Future<List<CloudPlaybackCommand>> pendingPlaybackCommands() async =>
      const [];

  @override
  Future<CloudPlaybackSession?> playbackSession() async {
    final state = bridge.sessionState;
    final target = bridge.targetDeviceId;
    if (state == null || target == null) return null;
    return CloudPlaybackSession(
      sessionId: 'session-1',
      targetDeviceId: target,
      sequence: 1,
      state: Map<String, dynamic>.from(state),
      currentSongId: state['currentSongId']?.toString(),
      positionMs: (state['positionMs'] as num?)?.toInt() ?? 0,
      playing: state['playing'] == true,
    );
  }

  @override
  Future<void> sendSessionCommand({
    required String targetDeviceId,
    required String type,
    required Map<String, Object?> payload,
  }) async {
    bridge._sendCommand(deviceId, targetDeviceId, type, payload);
  }

  @override
  Future<String> startPlaybackSession({
    required String targetDeviceId,
    required Map<String, Object?> state,
  }) async {
    bridge.targetDeviceId = targetDeviceId;
    bridge.sessionState = Map<String, dynamic>.from(state);
    bridge._sendCommand(deviceId, targetDeviceId, 'handoff', state);
    return 'session-1';
  }

  @override
  Future<void> switchPlaybackTarget({
    required String targetDeviceId,
    required Map<String, Object?> state,
  }) async {
    bridge.targetDeviceId = targetDeviceId;
    bridge.sessionState = Map<String, dynamic>.from(state);
    bridge._sendCommand(deviceId, targetDeviceId, 'handoff', state);
  }

  @override
  Future<void> updatePlaybackSessionState(Map<String, Object?> state) async {
    bridge.sessionState = Map<String, dynamic>.from(state);
  }
}

class _BridgeSocket implements PlaybackSocketTransport {
  _BridgeSocket(this.bridge, this.deviceId);

  final _PlaybackBridge bridge;
  final String deviceId;
  final _frames = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final _statuses = StreamController<PlaybackSocketStatus>.broadcast(
    sync: true,
  );

  @override
  PlaybackSocketStatus currentStatus = PlaybackSocketStatus.disconnected;

  @override
  Stream<Map<String, dynamic>> get frames => _frames.stream;

  @override
  Stream<PlaybackSocketStatus> get status => _statuses.stream;

  void addFrame(Map<String, dynamic> frame) => _frames.add(frame);

  @override
  Future<void> connect(String _) async {
    currentStatus = PlaybackSocketStatus.connected;
    _statuses.add(currentStatus);
  }

  @override
  void send(Map<String, Object?> frame) => bridge._fromSocket(deviceId, frame);

  @override
  Future<void> dispose() async {
    currentStatus = PlaybackSocketStatus.disconnected;
    await _frames.close();
    await _statuses.close();
  }
}

class _RemoteAudioHandler extends BaseAudioHandler {
  _RemoteAudioHandler({
    bool shuffle = false,
    bool repeat = false,
    this.queueLoop = false,
  }) {
    playbackState.add(
      PlaybackState(
        processingState: AudioProcessingState.idle,
        playing: false,
        shuffleMode: shuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        repeatMode: repeat
            ? AudioServiceRepeatMode.one
            : AudioServiceRepeatMode.none,
      ),
    );
  }

  bool completeLoadsAutomatically = true;
  bool queueLoop;
  int playCallCount = 0;
  int pauseCallCount = 0;
  int skipToNextCallCount = 0;
  final List<String> playedSongIds = [];
  final List<MediaItem> playedItems = [];
  Completer<void>? _pendingLoad;

  @override
  Future<void> updateQueue(List<MediaItem> items) async {
    final currentId = mediaItem.value?.id;
    queue.add(List<MediaItem>.from(items));
    final index = items.indexWhere((item) => item.id == currentId);
    if (index >= 0) {
      playbackState.add(playbackState.value.copyWith(queueIndex: index));
    }
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name == 'playByIndex') {
      final index = extras?['index'] as int? ?? 0;
      if (index < 0 || index >= queue.value.length) return null;
      final song = queue.value[index];
      playedSongIds.add(song.id);
      playedItems.add(song);
      mediaItem.add(song);
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.loading,
          playing: true,
          queueIndex: index,
          updatePosition: Duration.zero,
          bufferedPosition: Duration.zero,
        ),
      );
      if (!completeLoadsAutomatically) {
        _pendingLoad = Completer<void>();
        await _pendingLoad!.future;
      }
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.ready,
          playing: true,
          updatePosition: Duration.zero,
        ),
      );
    } else if (name == 'toggleQueueLoopMode') {
      queueLoop = extras?['enable'] == true;
    } else if (name == 'setShuffleModePreservingQueue') {
      final enabled = extras?['enabled'] == true;
      playbackState.add(
        playbackState.value.copyWith(
          shuffleMode: enabled
              ? AudioServiceShuffleMode.all
              : AudioServiceShuffleMode.none,
        ),
      );
    }
    return null;
  }

  @override
  Future<void> play() async {
    playCallCount++;
    playbackState.add(
      playbackState.value.copyWith(
        playing: true,
        processingState: AudioProcessingState.ready,
      ),
    );
  }

  @override
  Future<void> pause() async {
    pauseCallCount++;
    playbackState.add(playbackState.value.copyWith(playing: false));
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
  }

  @override
  Future<void> skipToNext() async {
    skipToNextCallCount++;
  }

  void reportBuffering(Duration position) {
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.buffering,
        playing: true,
        updatePosition: position,
      ),
    );
  }

  void completePendingLoad() {
    final pending = _pendingLoad;
    if (pending == null || pending.isCompleted) return;
    pending.complete();
    _pendingLoad = null;
  }

  Future<void> advanceAutomatically() async {
    final currentIndex = queue.value.indexWhere(
      (item) => item.id == mediaItem.value?.id,
    );
    if (currentIndex < 0 || currentIndex + 1 >= queue.value.length) return;
    await customAction('playByIndex', {'index': currentIndex + 1});
  }
}

class _HomeSelectionMusicService extends FakeMusicService {
  _HomeSelectionMusicService(this._watchQueues);

  final Map<String, List<MediaItem>> _watchQueues;

  @override
  Future<Map<String, dynamic>> getWatchPlaylist({
    String videoId = '',
    String? playlistId,
    int limit = 25,
    bool radio = false,
    bool shuffle = false,
    String? additionalParamsNext,
    bool onlyRelated = false,
  }) async {
    final queue = _watchQueues[videoId];
    if (queue != null) {
      return {'tracks': queue, 'additionalParamsForNext': null};
    }
    return super.getWatchPlaylist(
      videoId: videoId,
      playlistId: playlistId,
      limit: limit,
      radio: radio,
      shuffle: shuffle,
      additionalParamsNext: additionalParamsNext,
      onlyRelated: onlyRelated,
    );
  }
}

class _DelayedHomeSelectionMusicService extends _HomeSelectionMusicService {
  _DelayedHomeSelectionMusicService(super.watchQueues);

  final Map<String, Completer<void>> _holds = {};
  final Map<String, Completer<void>> _requests = {};

  void hold(String videoId) {
    _holds.putIfAbsent(videoId, Completer<void>.new);
  }

  Future<void> waitUntilRequested(String videoId) =>
      _requests.putIfAbsent(videoId, Completer<void>.new).future;

  void release(String videoId) {
    final hold = _holds[videoId];
    if (hold != null && !hold.isCompleted) hold.complete();
  }

  @override
  Future<Map<String, dynamic>> getWatchPlaylist({
    String videoId = '',
    String? playlistId,
    int limit = 25,
    bool radio = false,
    bool shuffle = false,
    String? additionalParamsNext,
    bool onlyRelated = false,
  }) async {
    final requested = _requests.putIfAbsent(videoId, Completer<void>.new);
    if (!requested.isCompleted) requested.complete();
    final hold = _holds[videoId];
    if (hold != null) await hold.future;
    return super.getWatchPlaylist(
      videoId: videoId,
      playlistId: playlistId,
      limit: limit,
      radio: radio,
      shuffle: shuffle,
      additionalParamsNext: additionalParamsNext,
      onlyRelated: onlyRelated,
    );
  }
}

class _ReplacementScenario {
  const _ReplacementScenario(this.name, this.queue);

  final String name;
  final List<MediaItem> queue;
}

MediaItem _replacementSong(String id, String source) => MediaItem(
  id: id,
  title: 'Replacement $id',
  artist: 'Fixture Artist',
  duration: const Duration(minutes: 3),
  extras: {'url': source, 'isLive': false},
);

final _replacementScenarios = [
  _ReplacementScenario('offline', [
    _replacementSong('offline0001', 'file:///C:/Music/offline0001.mp3'),
    _replacementSong('offline0002', 'file:///C:/Music/offline0002.mp3'),
    _replacementSong('offline0003', 'file:///C:/Music/offline0003.mp3'),
  ]),
  _ReplacementScenario('online', [
    _replacementSong('online00001', 'https://example.test/online00001.m4a'),
    _replacementSong('online00002', 'https://example.test/online00002.m4a'),
    _replacementSong('online00003', 'https://example.test/online00003.m4a'),
  ]),
  _ReplacementScenario('mixed', [
    _replacementSong('mixed000001', 'file:///C:/Music/mixed000001.mp3'),
    _replacementSong('mixed000002', 'https://example.test/mixed000002.m4a'),
    _replacementSong('mixed000003', 'file:///C:/Music/mixed000003.mp3'),
  ]),
];

final _phoneLocalFirstSelection = [
  _replacementSong('phoneLoc001', 'file:///storage/emulated/0/Music/one.mp3'),
  _replacementSong('phoneLoc002', 'file:///storage/emulated/0/Music/two.mp3'),
];

final _phoneLocalSecondSelection = [
  _replacementSong('phoneLoc003', 'file:///storage/emulated/0/Music/three.mp3'),
  _replacementSong('phoneLoc004', 'file:///storage/emulated/0/Music/four.mp3'),
];

final _windowsOnlineFirstSelection = [
  _replacementSong('phoneLoc001', 'https://example.test/windows-one.m4a'),
  _replacementSong('phoneLoc002', 'https://example.test/windows-two.m4a'),
];

final _windowsOnlineSecondSelection = [
  _replacementSong('phoneLoc003', 'https://example.test/windows-three.m4a'),
  _replacementSong('phoneLoc004', 'https://example.test/windows-four.m4a'),
];

class _MemorySettings implements SettingsRepository {
  _MemorySettings({
    this.shuffle = false,
    this.repeat = false,
    this.queueLoop = false,
  });

  bool shuffle;
  bool repeat;
  bool queueLoop;

  @override
  bool getShuffleModeEnabled() => shuffle;

  @override
  bool getLoopModeEnabled() => repeat;

  @override
  bool getQueueLoopModeEnabled() => queueLoop;

  @override
  Future<void> setShuffleModeEnabled(bool value) async => shuffle = value;

  @override
  Future<void> setLoopModeEnabled(bool value) async => repeat = value;

  @override
  Future<void> setQueueLoopModeEnabled(bool value) async => queueLoop = value;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked.');
}
