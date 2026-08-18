import 'package:audio_service/audio_service.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:harmonymusic/app/providers/controller_providers.dart';
import 'package:harmonymusic/app/providers/repository_providers.dart';
import 'package:harmonymusic/app/providers/service_providers.dart';
import 'package:harmonymusic/l10n/l10n.dart';
import 'package:harmonymusic/services/cloud/playback_modes.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:harmonymusic/ui/player/components/album_art_lyrics.dart';
import 'package:harmonymusic/ui/player/components/lyrics_switch.dart';
import 'package:harmonymusic/ui/player/components/lyrics_widget.dart';
import 'package:harmonymusic/ui/player/components/mini_player.dart';
import 'package:harmonymusic/ui/player/components/player_control.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Search/search_result_screen.dart';
import 'package:harmonymusic/ui/widgets/loader.dart';
import 'package:harmonymusic/ui/widgets/image_widget.dart';
import 'package:hive/hive.dart';
import 'package:integration_test/integration_test.dart';
import 'package:toggle_switch/toggle_switch.dart';

import 'support/harness.dart';
import 'support/fakes.dart';

/// Drives the real home, mini-player, full-player, and queue UI against the
/// shared fake audio boundary. These scenarios cover user-visible player
/// behavior without relying on YouTube, Resolver, or a physical audio device.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    String? reason,
    // The default covers anything that only awaits the fakes. Queue expansion
    // now backs off between retries (1s, 2s, 4s, …), so those waits are
    // deliberately measured in seconds and need to say so.
    int attempts = 30,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (condition()) return;
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(condition(), isTrue, reason: reason);
  }

  Future<TestAppHandle> startFixturePlayback(
    WidgetTester tester, {
    bool completeSourceLoad = true,
    FakeLyricsRepository? lyricsRepository,
  }) async {
    final handle = await bootTestApp(
      tester,
      lyricsRepository: lyricsRepository,
    );
    handle.audioHandler.completeSourceLoadsAutomatically = completeSourceLoad;
    final song = find.text('Fixture Song').hitTestable();
    expect(song, findsWidgets);

    await tester.tap(song.first);
    await pumpUntil(
      tester,
      () =>
          handle.audioHandler.queue.value.length == 2 &&
          handle.audioHandler.mediaItem.value?.id == 'song-1',
      reason: 'the selected song and its watch queue should reach the handler',
    );
    await tester.pump(const Duration(milliseconds: 300));
    return handle;
  }

  Future<void> openFullPlayer(WidgetTester tester) async {
    final miniTitle = find
        .descendant(
          of: find.byType(MiniPlayer),
          matching: find.text('Fixture Song'),
        )
        .hitTestable();
    expect(miniTitle, findsOneWidget);
    await tester.tap(miniTitle);
    // Wait for the entrance animation rather than guessing at it: a fixed pump
    // can land while the panel is still sliding, so the artwork is present but
    // the controls below it are not yet hit-testable — which then fails in
    // whichever helper runs next instead of here.
    await pumpUntil(
      tester,
      () => find.byType(AlbumArtNLyrics).hitTestable().evaluate().isNotEmpty,
      reason: 'the full player should open when the mini player is tapped',
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }

  Future<void> openQueue(WidgetTester tester) async {
    await pumpUntil(
      tester,
      () =>
          find.byIcon(Icons.keyboard_arrow_up).hitTestable().evaluate().isNotEmpty,
      reason: 'the queue handle should be reachable once the player settles',
    );
    final queueHandle = find.byIcon(Icons.keyboard_arrow_up).hitTestable();
    expect(queueHandle, findsOneWidget);
    await tester.tap(queueHandle);
    await pumpUntil(
      tester,
      () => find
          .byKey(const Key('queue-row-song-1-0'))
          .hitTestable()
          .evaluate()
          .isNotEmpty,
      reason: 'the queue panel should list its rows once open',
    );
    expect(
      find.byKey(const Key('queue-row-song-1-0')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('queue-row-song-2-1')).hitTestable(),
      findsOneWidget,
    );
  }

  Finder fullPlayerIcon(IconData icon) => find
      .descendant(
        of: find.byType(PlayerControlWidget),
        matching: find.byIcon(icon),
      )
      .hitTestable();

  Finder loadingIndicatorWithin(Finder parent) =>
      find.descendant(of: parent, matching: find.byType(LoadingIndicator));

  Finder fullPlayerArtwork() => find
      .descendant(
        of: find.byType(AlbumArtNLyrics),
        matching: find.byType(ImageWidget),
      )
      .hitTestable();

  Future<void> selectPlainLyrics(WidgetTester tester) async {
    await pumpUntil(
      tester,
      () => find.byType(ToggleSwitch).hitTestable().evaluate().isNotEmpty,
      reason: 'the lyrics mode toggle should appear once the panel settles',
    );
    final toggle = find.byType(ToggleSwitch).hitTestable();
    expect(toggle, findsOneWidget);
    final bounds = tester.getRect(toggle);
    await tester.tapAt(
      Offset(bounds.left + bounds.width * 0.75, bounds.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'selecting a song starts playback and opens and closes the full player',
    (tester) async {
      final handle = await startFixturePlayback(tester);
      final controller = handle.container.read(playerControllerProvider);

      expect(handle.audioHandler.customActionNames, contains('setSourceNPlay'));
      expect(handle.audioHandler.playbackState.value.playing, isTrue);
      expect(controller.currentSong.value?.id, 'song-1');
      expect(controller.currentQueue.map((song) => song.id), [
        'song-1',
        'song-2',
      ]);
      expect(
        find
            .descendant(
              of: find.byType(MiniPlayer),
              matching: find.text('Fixture Song'),
            )
            .hitTestable(),
        findsOneWidget,
      );

      await openFullPlayer(tester);
      expect(fullPlayerIcon(Icons.skip_previous), findsOneWidget);
      expect(fullPlayerIcon(Icons.skip_next), findsOneWidget);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down).hitTestable());
      await tester.pump(const Duration(milliseconds: 700));
      expect(controller.playerPanelController.isPanelClosed, isTrue);
    },
  );

  testWidgets('play and pause controls update the active audio session', (
    tester,
  ) async {
    final handle = await startFixturePlayback(tester);
    await openFullPlayer(tester);

    final playButton = find.byKey(const Key('playButton')).hitTestable();
    await tester.tap(playButton);
    await tester.pump(const Duration(milliseconds: 400));
    expect(handle.audioHandler.pauseCallCount, 1);
    expect(handle.audioHandler.playbackState.value.playing, isFalse);

    await tester.tap(playButton);
    await tester.pump(const Duration(milliseconds: 400));
    expect(handle.audioHandler.playCallCount, 1);
    expect(handle.audioHandler.playbackState.value.playing, isTrue);
  });

  testWidgets('next and previous move through the queue in both directions', (
    tester,
  ) async {
    final handle = await startFixturePlayback(tester);
    final controller = handle.container.read(playerControllerProvider);
    await openFullPlayer(tester);

    await tester.tap(fullPlayerIcon(Icons.skip_next));
    await pumpUntil(
      tester,
      () => controller.currentSong.value?.id == 'song-2',
      reason: 'next should select the second queue item',
    );
    expect(handle.audioHandler.nextCallCount, 1);
    expect(find.text('Fixture Song Two'), findsWidgets);

    await tester.tap(fullPlayerIcon(Icons.skip_previous));
    await pumpUntil(
      tester,
      () => controller.currentSong.value?.id == 'song-1',
      reason: 'previous should return to the first queue item',
    );
    expect(handle.audioHandler.previousCallCount, 1);
  });

  testWidgets('remote mode snapshots update the mirrored UI and preferences', (
    tester,
  ) async {
    final handle = await startFixturePlayback(tester);
    final controller = handle.container.read(playerControllerProvider);
    final settings = handle.container.read(settingsRepositoryProvider);

    controller.applyRemotePlaybackModes(
      const CloudPlaybackModes(shuffle: true, repeat: true, queueLoop: true),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.isShuffleModeEnabled.value, isTrue);
    expect(controller.isLoopModeEnabled.value, isTrue);
    expect(controller.isQueueLoopModeEnabled.value, isTrue);
    expect(settings.getShuffleModeEnabled(), isTrue);
    expect(settings.getLoopModeEnabled(), isTrue);
    expect(settings.getQueueLoopModeEnabled(), isTrue);

    controller.applyRemotePlaybackModes(
      const CloudPlaybackModes(shuffle: false, repeat: false, queueLoop: false),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.isShuffleModeEnabled.value, isFalse);
    expect(controller.isLoopModeEnabled.value, isFalse);
    expect(controller.isQueueLoopModeEnabled.value, isFalse);
    expect(settings.getShuffleModeEnabled(), isFalse);
    expect(settings.getLoopModeEnabled(), isFalse);
    expect(settings.getQueueLoopModeEnabled(), isFalse);
  });

  testWidgets(
    'remote next immediately shows the exact incoming song at zero and loading',
    (tester) async {
      final handle = await startFixturePlayback(tester);
      final controller = handle.container.read(playerControllerProvider);
      final commands = handle.container.read(playbackCommandServiceProvider);

      commands.startRemoteControl('windows-target');
      controller.applyRemoteQueue(
        List<MediaItem>.from(controller.currentQueue),
        index: 0,
        positionMs: 42000,
        durationMs: const Duration(minutes: 3).inMilliseconds,
        playing: true,
      );
      await tester.pump(const Duration(milliseconds: 100));

      // This is the controller-side half of a user pressing Next. The command
      // transport itself is covered by remote_playback_test; here we exercise
      // the optimistic surface that must stay coherent until target frames
      // arrive over the socket.
      final transition = controller.beginRemoteSongTransition(
        List<MediaItem>.from(controller.currentQueue),
        1,
      );
      expect(transition, isNotNull);
      await tester.pump();

      expect(controller.currentSong.value?.id, 'song-2');
      expect(controller.progressBarStatus.value.current, Duration.zero);
      expect(controller.buttonState.value, PlayButtonState.loading);

      // The target can still have an in-flight progress frame for the old
      // song. It must not undo the controller's optimistic next transition.
      controller.applyRemoteProgress({
        'currentSongId': 'song-1',
        'positionMs': 45000,
        'durationMs': const Duration(minutes: 3).inMilliseconds,
        'playing': true,
        'loading': false,
        'publishedAtMs': DateTime.now().millisecondsSinceEpoch,
      });
      await tester.pump();
      expect(controller.currentSong.value?.id, 'song-2');
      expect(controller.progressBarStatus.value.current, Duration.zero);
      expect(controller.buttonState.value, PlayButtonState.loading);

      // The matching target frame confirms the transition. A loading frame
      // remains frozen; a ready frame alone clears the controller's spinner.
      controller.applyRemoteProgress({
        'currentSongId': 'song-2',
        'positionMs': 0,
        'durationMs': const Duration(minutes: 3).inMilliseconds,
        'playing': true,
        'loading': true,
        'publishedAtMs': DateTime.now().millisecondsSinceEpoch,
      });
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.progressBarStatus.value.current, Duration.zero);
      expect(controller.buttonState.value, PlayButtonState.loading);

      controller.applyRemoteProgress({
        'currentSongId': 'song-2',
        'positionMs': 0,
        'durationMs': const Duration(minutes: 3).inMilliseconds,
        'playing': true,
        'loading': false,
        'publishedAtMs': DateTime.now().millisecondsSinceEpoch,
      });
      await tester.pump();
      expect(controller.buttonState.value, PlayButtonState.playing);

      // Stop the controller ticker before the widget test disposes the tree.
      controller.applyRemoteProgress({
        'currentSongId': 'song-2',
        'positionMs': 0,
        'durationMs': const Duration(minutes: 3).inMilliseconds,
        'playing': false,
        'loading': false,
        'publishedAtMs': DateTime.now().millisecondsSinceEpoch,
      });
      await tester.pump();
    },
  );

  testWidgets(
    'controller follows, corrects, pauses, and freezes remote progress frames',
    (tester) async {
      final handle = await startFixturePlayback(tester);
      final controller = handle.container.read(playerControllerProvider);

      // The target clock is one second behind the controller. Its wall-clock
      // timestamp must not be treated as transport latency: doing so is what
      // made a phone visibly ahead of Windows in a real remote session.
      controller.applyRemoteProgress({
        'currentSongId': 'song-1',
        'positionMs': 10000,
        'durationMs': const Duration(minutes: 3).inMilliseconds,
        'playing': true,
        'loading': false,
        'speed': 1.0,
        'publishedAtMs': DateTime.now()
            .subtract(const Duration(seconds: 1))
            .millisecondsSinceEpoch,
      });
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await tester.pump();
      final projectedMs =
          controller.progressBarStatus.value.current.inMilliseconds;
      expect(
        projectedMs,
        inInclusiveRange(10000, 10450),
        reason:
            'the controller should follow from frame receipt, not peer clock skew',
      );

      // A newer sample is authoritative and must re-anchor the visible timer
      // rather than accumulating drift from the controller's own clock.
      controller.applyRemoteProgress({
        'currentSongId': 'song-1',
        'positionMs': 18000,
        'durationMs': const Duration(minutes: 3).inMilliseconds,
        'playing': true,
        'loading': false,
        'speed': 1.0,
        // A target clock ahead by two seconds must be equally harmless.
        'publishedAtMs': DateTime.now()
            .add(const Duration(seconds: 2))
            .millisecondsSinceEpoch,
      });
      await tester.pump();
      expect(
        controller.progressBarStatus.value.current.inMilliseconds,
        inInclusiveRange(18000, 18250),
        reason: 'a fresh target frame should correct the controller position',
      );

      // Pause and loading frames own the timer: neither is allowed to continue
      // extrapolating locally while the remote audio device is stopped/loading.
      controller.applyRemoteProgress({
        'currentSongId': 'song-1',
        'positionMs': 18300,
        'durationMs': const Duration(minutes: 3).inMilliseconds,
        'playing': false,
        'loading': false,
        'publishedAtMs': DateTime.now().millisecondsSinceEpoch,
      });
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await tester.pump();
      expect(controller.progressBarStatus.value.current.inMilliseconds, 18300);
      expect(controller.buttonState.value, PlayButtonState.paused);

      controller.applyRemoteProgress({
        'currentSongId': 'song-2',
        'positionMs': 0,
        'durationMs': const Duration(minutes: 4).inMilliseconds,
        'playing': true,
        'loading': true,
        'publishedAtMs': DateTime.now().millisecondsSinceEpoch,
      });
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await tester.pump();
      expect(controller.currentSong.value?.id, 'song-2');
      expect(controller.progressBarStatus.value.current, Duration.zero);
      expect(controller.buttonState.value, PlayButtonState.loading);
    },
  );

  Future<void> expectIncomingTrackWaitsAtZero(
    WidgetTester tester,
    TestAppHandle handle,
  ) async {
    final controller = handle.container.read(playerControllerProvider);
    await pumpUntil(
      tester,
      () => controller.currentSong.value?.id == 'song-2',
      reason: 'the incoming queue item should become the visible song',
    );

    // Android can briefly report ready at zero before the incoming network
    // source falls back to buffering. That transient ready event is not proof
    // that audible playback started and must not release the timer/loading UI.
    handle.audioHandler.reportCurrentLoadBuffering(
      reportedPosition: Duration.zero,
    );
    await tester.pump(const Duration(milliseconds: 100));
    handle.audioHandler.completeCurrentLoad();
    await tester.pump(const Duration(milliseconds: 100));
    handle.audioHandler.reportCurrentLoadBuffering();
    await tester.pump(const Duration(milliseconds: 100));

    final progressFinder = find.descendant(
      of: find.byType(PlayerControlWidget),
      matching: find.byType(ProgressBar),
    );
    expect(
      (
        controllerPosition: controller.progressBarStatus.value.current,
        visiblePosition: tester.widget<ProgressBar>(progressFinder).progress,
        buttonState: controller.buttonState.value,
        visibleLoadingIndicators: loadingIndicatorWithin(
          find.byType(PlayerControlWidget),
        ).evaluate().length,
      ),
      (
        controllerPosition: Duration.zero,
        visiblePosition: Duration.zero,
        buttonState: PlayButtonState.loading,
        visibleLoadingIndicators: 1,
      ),
      reason:
          'the incoming timer must stay at 0:00 and its play/pause control '
          'must show loading immediately, without the later-rebuffer grace',
    );

    await tester.pump(const Duration(seconds: 2));
    expect(
      controller.progressBarStatus.value.current,
      Duration.zero,
      reason: 'buffering time must not be counted as elapsed playback',
    );
    expect(tester.widget<ProgressBar>(progressFinder).progress, Duration.zero);
    expect(controller.buttonState.value, PlayButtonState.loading);
  }

  testWidgets(
    'manually skipped online song stays at zero and loading until ready',
    (tester) async {
      final handle = await startFixturePlayback(tester);
      final controller = handle.container.read(playerControllerProvider);
      await openFullPlayer(tester);

      handle.audioHandler.completeSourceLoadsAutomatically = false;
      await tester.tap(fullPlayerIcon(Icons.skip_next));
      await expectIncomingTrackWaitsAtZero(tester, handle);

      handle.audioHandler.completeCurrentLoad();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.buttonState.value, PlayButtonState.playing);
      expect(
        loadingIndicatorWithin(find.byType(PlayerControlWidget)),
        findsNothing,
      );
    },
  );

  testWidgets(
    'automatically advanced online song stays at zero and loading until ready',
    (tester) async {
      final handle = await startFixturePlayback(tester);
      final controller = handle.container.read(playerControllerProvider);
      await openFullPlayer(tester);

      handle.audioHandler.completeSourceLoadsAutomatically = false;
      await handle.audioHandler.finishCurrentTrackAndAdvance();
      await expectIncomingTrackWaitsAtZero(tester, handle);

      handle.audioHandler.completeCurrentLoad();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.buttonState.value, PlayButtonState.playing);
      expect(
        loadingIndicatorWithin(find.byType(PlayerControlWidget)),
        findsNothing,
      );
    },
  );

  testWidgets('the progress control sends the requested seek position', (
    tester,
  ) async {
    final handle = await startFixturePlayback(tester);
    await openFullPlayer(tester);

    final progressFinder = find.descendant(
      of: find.byType(PlayerControlWidget),
      matching: find.byType(ProgressBar),
    );
    expect(progressFinder, findsOneWidget);
    final progressBar = tester.widget<ProgressBar>(progressFinder);
    progressBar.onSeek!(const Duration(minutes: 1, seconds: 17));
    await tester.pump(const Duration(milliseconds: 300));

    expect(handle.audioHandler.seekPositions, [
      const Duration(minutes: 1, seconds: 17),
    ]);
    expect(
      handle.audioHandler.playbackState.value.updatePosition,
      const Duration(minutes: 1, seconds: 17),
    );
  });

  testWidgets(
    'seeking beyond loaded online audio freezes time and shows loading',
    (tester) async {
      final handle = await startFixturePlayback(tester);
      final controller = handle.container.read(playerControllerProvider);
      await openFullPlayer(tester);
      handle.audioHandler.bufferSeeks = true;

      final progressFinder = find.descendant(
        of: find.byType(PlayerControlWidget),
        matching: find.byType(ProgressBar),
      );
      final progressBar = tester.widget<ProgressBar>(progressFinder);
      const requestedPosition = Duration(minutes: 2, seconds: 5);
      progressBar.onSeek!(requestedPosition);
      await pumpUntil(
        tester,
        () => controller.progressBarStatus.value.current == requestedPosition,
        reason: 'the seek position should reach the visible progress bar',
      );
      // Buffering has a deliberate 350 ms grace period to avoid flashing the
      // spinner for tiny decoder stalls.
      await tester.pump(const Duration(milliseconds: 500));

      expect(controller.buttonState.value, PlayButtonState.loading);
      expect(
        loadingIndicatorWithin(find.byType(PlayerControlWidget)),
        findsOneWidget,
      );
      expect(
        loadingIndicatorWithin(find.byType(AlbumArtNLyrics)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(AlbumArtNLyrics),
          matching: find.byKey(const Key('online-song-artwork-shimmer')),
        ),
        findsNothing,
      );

      await tester.pump(const Duration(seconds: 2));
      expect(
        controller.progressBarStatus.value.current,
        requestedPosition,
        reason: 'elapsed time must not advance while online audio is buffering',
      );
      expect(
        tester.widget<ProgressBar>(progressFinder).progress,
        requestedPosition,
        reason: 'the visible timer bar must remain frozen while buffering',
      );

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down).hitTestable());
      await tester.pump(const Duration(milliseconds: 700));
      expect(loadingIndicatorWithin(find.byType(MiniPlayer)), findsOneWidget);

      handle.audioHandler.completeCurrentLoad();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.buttonState.value, PlayButtonState.playing);
      expect(loadingIndicatorWithin(find.byType(MiniPlayer)), findsNothing);
    },
  );

  testWidgets(
    'a newly selected online song stays at zero with loading buttons until ready',
    (tester) async {
      final handle = await startFixturePlayback(
        tester,
        completeSourceLoad: false,
      );
      final controller = handle.container.read(playerControllerProvider);

      expect(controller.progressBarStatus.value.current, Duration.zero);
      expect(controller.progressBarStatus.value.buffered, Duration.zero);
      expect(controller.buttonState.value, PlayButtonState.loading);
      expect(loadingIndicatorWithin(find.byType(MiniPlayer)), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MiniPlayer),
          matching: find.byKey(const Key('online-song-artwork-shimmer')),
        ),
        findsOneWidget,
      );

      await openFullPlayer(tester);
      expect(
        loadingIndicatorWithin(find.byType(PlayerControlWidget)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlbumArtNLyrics),
          matching: find.byKey(const Key('online-song-artwork-shimmer')),
        ),
        findsOneWidget,
      );
      expect(
        loadingIndicatorWithin(find.byType(AlbumArtNLyrics)),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(
        controller.progressBarStatus.value.current,
        Duration.zero,
        reason: 'a source that has not started must remain at 0:00',
      );
      final progressFinder = find.descendant(
        of: find.byType(PlayerControlWidget),
        matching: find.byType(ProgressBar),
      );
      expect(
        tester.widget<ProgressBar>(progressFinder).progress,
        Duration.zero,
        reason: 'the visible timer bar must remain at 0:00 before source start',
      );
      expect(controller.buttonState.value, PlayButtonState.loading);

      handle.audioHandler.completeCurrentLoad();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.buttonState.value, PlayButtonState.playing);
      expect(
        find.byKey(const Key('online-song-artwork-shimmer')),
        findsNothing,
      );
      expect(
        loadingIndicatorWithin(find.byType(PlayerControlWidget)),
        findsNothing,
      );
    },
  );

  testWidgets(
    'lyrics show loading then synced and plain content and can be closed',
    (tester) async {
      const syncedLyrics = '[00:00.00]Fixture synced line';
      const plainLyrics = 'Fixture plain line one\nFixture plain line two';
      final lyricsRepository = FakeLyricsRepository(
        lyrics: const {'synced': syncedLyrics, 'plainLyrics': plainLyrics},
        completeReadsAutomatically: false,
      );
      final handle = await startFixturePlayback(
        tester,
        lyricsRepository: lyricsRepository,
      );
      final controller = handle.container.read(playerControllerProvider);
      await openFullPlayer(tester);

      await tester.tap(fullPlayerArtwork());
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.showLyricsFlag.value, isTrue);
      expect(controller.isLyricsLoading.value, isTrue);
      expect(loadingIndicatorWithin(find.byType(LyricsWidget)), findsOneWidget);

      lyricsRepository.completePendingRead();
      await pumpUntil(
        tester,
        () => !controller.isLyricsLoading.value,
        reason: 'cached lyrics should replace the loading indicator',
      );
      expect(controller.lyrics['synced'], syncedLyrics);
      expect(find.byType(LyricView), findsOneWidget);
      final lyricsContext = tester.element(find.byType(LyricsSwitch));
      expect(find.text(lyricsContext.l10n.synced), findsOneWidget);
      expect(find.text(lyricsContext.l10n.plain), findsOneWidget);

      await selectPlainLyrics(tester);
      expect(controller.lyricsMode.value, 1);
      expect(find.text(plainLyrics), findsOneWidget);

      final artworkBounds = tester.getRect(
        find.byType(AlbumArtNLyrics).hitTestable(),
      );
      await tester.tapAt(artworkBounds.topLeft + const Offset(20, 20));
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.showLyricsFlag.value, isFalse);
      expect(fullPlayerArtwork(), findsOneWidget);
      expect(lyricsRepository.getCallCount, 1);
    },
  );

  testWidgets('unavailable lyrics show clear messages in both modes', (
    tester,
  ) async {
    final lyricsRepository = FakeLyricsRepository(
      lyrics: const {'synced': 'NA', 'plainLyrics': 'NA'},
    );
    final handle = await startFixturePlayback(
      tester,
      lyricsRepository: lyricsRepository,
    );
    final controller = handle.container.read(playerControllerProvider);
    await openFullPlayer(tester);

    await tester.tap(fullPlayerArtwork());
    await tester.pump(const Duration(milliseconds: 300));
    await pumpUntil(
      tester,
      () => !controller.isLyricsLoading.value,
      reason: 'the unavailable cached result should finish loading',
    );
    final lyricsContext = tester.element(find.byType(LyricsSwitch));
    expect(
      find.text(lyricsContext.l10n.syncedLyricsNotAvailable),
      findsOneWidget,
    );

    await selectPlainLyrics(tester);
    expect(find.text(lyricsContext.l10n.lyricsNotAvailable), findsOneWidget);
    expect(lyricsRepository.getCallCount, 1);
  });

  testWidgets('changing songs closes lyrics and ignores a stale fetch', (
    tester,
  ) async {
    final lyricsRepository = FakeLyricsRepository(
      lyrics: const {
        'synced': '[00:00.00]Stale first-song lyric',
        'plainLyrics': 'Stale first-song lyric',
      },
      completeReadsAutomatically: false,
    );
    final handle = await startFixturePlayback(
      tester,
      lyricsRepository: lyricsRepository,
    );
    final controller = handle.container.read(playerControllerProvider);
    await openFullPlayer(tester);

    await tester.tap(fullPlayerArtwork());
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.isLyricsLoading.value, isTrue);

    await tester.tap(fullPlayerIcon(Icons.skip_next));
    await pumpUntil(
      tester,
      () => controller.currentSong.value?.id == 'song-2',
      reason: 'next should replace the song while lyrics are pending',
    );
    expect(controller.showLyricsFlag.value, isFalse);
    expect(controller.isLyricsLoading.value, isFalse);
    expect(controller.lyrics['synced'], isEmpty);
    expect(controller.lyrics['plainLyrics'], isEmpty);

    lyricsRepository.completePendingRead();
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.currentSong.value?.id, 'song-2');
    expect(controller.showLyricsFlag.value, isFalse);
    expect(controller.lyrics['synced'], isEmpty);
    expect(controller.lyrics['plainLyrics'], isEmpty);
    expect(find.text('Stale first-song lyric'), findsNothing);
  });

  testWidgets('shuffle and single-song repeat toggle on and back off', (
    tester,
  ) async {
    final handle = await startFixturePlayback(tester);
    final controller = handle.container.read(playerControllerProvider);
    await openFullPlayer(tester);

    await tester.tap(fullPlayerIcon(Icons.shuffle));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.isShuffleModeEnabled.value, isTrue);
    expect(handle.audioHandler.shuffleModes.last, AudioServiceShuffleMode.all);

    await tester.tap(fullPlayerIcon(Icons.shuffle));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.isShuffleModeEnabled.value, isFalse);
    expect(handle.audioHandler.shuffleModes.last, AudioServiceShuffleMode.none);

    await tester.tap(fullPlayerIcon(Icons.all_inclusive));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.isLoopModeEnabled.value, isTrue);
    expect(handle.audioHandler.repeatModes.last, AudioServiceRepeatMode.one);

    await tester.tap(fullPlayerIcon(Icons.all_inclusive));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.isLoopModeEnabled.value, isFalse);
    expect(handle.audioHandler.repeatModes.last, AudioServiceRepeatMode.none);
  });

  testWidgets('favorite toggles persist from the full player', (tester) async {
    await startFixturePlayback(tester);
    await openFullPlayer(tester);
    final favourites = await Hive.openBox(BoxNames.libFav);

    await tester.tap(fullPlayerIcon(Icons.favorite_border));
    await tester.pump(const Duration(milliseconds: 300));
    expect(favourites.containsKey('song-1'), isTrue);
    expect(fullPlayerIcon(Icons.favorite), findsOneWidget);

    await tester.tap(fullPlayerIcon(Icons.favorite));
    await tester.pump(const Duration(milliseconds: 300));
    expect(favourites.containsKey('song-1'), isFalse);
    expect(fullPlayerIcon(Icons.favorite_border), findsOneWidget);
  });

  testWidgets('queue rows select songs and remove only non-current songs', (
    tester,
  ) async {
    final handle = await startFixturePlayback(tester);
    final controller = handle.container.read(playerControllerProvider);
    await openFullPlayer(tester);
    await openQueue(tester);

    await tester.tap(find.byKey(const Key('queue-row-song-2-1')).hitTestable());
    await pumpUntil(
      tester,
      () => controller.currentSong.value?.id == 'song-2',
      reason: 'tapping a queue row should select that song',
    );
    expect(handle.audioHandler.playedIndices.last, 1);

    await tester.drag(
      find.byKey(const Key('queue-dismiss-song-1-0')).hitTestable(),
      const Offset(-500, 0),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(handle.audioHandler.queue.value.map((song) => song.id), ['song-2']);
    expect(controller.currentSong.value?.id, 'song-2');

    await tester.drag(
      find.byKey(const Key('queue-dismiss-song-2-0')).hitTestable(),
      const Offset(-500, 0),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      handle.audioHandler.queue.value.map((song) => song.id),
      ['song-2'],
      reason: 'the current song must not be dismissible from the queue',
    );
  });

  testWidgets('queue loop and clear controls reach the audio session', (
    tester,
  ) async {
    final handle = await startFixturePlayback(tester);
    final controller = handle.container.read(playerControllerProvider);
    await openFullPlayer(tester);
    await openQueue(tester);

    final initialQueueLoopMode = controller.isQueueLoopModeEnabled.value;
    await tester.tap(find.text('Queue loop').hitTestable());
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      controller.isQueueLoopModeEnabled.value,
      isNot(initialQueueLoopMode),
    );
    expect(
      handle.audioHandler.customActionNames,
      contains('toggleQueueLoopMode'),
    );

    await tester.tap(find.byIcon(Icons.playlist_remove).hitTestable());
    await pumpUntil(
      tester,
      () => handle.audioHandler.queue.value.isEmpty,
      reason: 'clear queue should empty the audio session queue',
    );
    expect(handle.audioHandler.customActionNames, contains('clearQueue'));
    expect(controller.currentQueue, isEmpty);
  });

  // ---------------------------------------------------------------------------
  // Queue expansion
  //
  // Tapping a single song is supposed to give you a queue, not one song. The
  // tapped song starts immediately against a placeholder queue of just itself
  // (`setSourceNPlay` does `queue.add([currMed])`) and the watch-playlist lookup
  // overwrites that a moment later. That lookup used to be issued exactly once
  // with no error handling at all, and on the local path its result was consumed
  // by an `unawaited(...then(...))` with no `onError` — so any throw left the
  // placeholder in place, played the song perfectly, and said nothing. It was
  // intermittent and online-only, because offline library playback goes through
  // `playPlayListSong`, which never makes the call.
  // ---------------------------------------------------------------------------

  /// Lets a song change's side effects finish before the test ends.
  ///
  /// Selecting a song kicks off Hive writes that nothing in the test awaits —
  /// `_addToRP`, `_backfillLibraryDuration`. A test that stops at its last
  /// assertion leaves them running into `bootTestApp`'s teardown, which closes
  /// the boxes and deletes the temp directory underneath them; the resulting
  /// `PathNotFoundException` is reported against whichever test happens to be
  /// on screen. The established tests avoid it by doing more UI work after
  /// playback starts, which these do not.
  Future<void> settleSongSideEffects(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 900));
  }

  Future<void> submitSearch(WidgetTester tester, String query) async {
    await tester.tap(find.byIcon(Icons.search).hitTestable());
    await tester.pump(const Duration(milliseconds: 600));
    final field = find.byType(TextField).hitTestable();
    expect(field, findsWidgets, reason: 'the search screen should be open');

    await tester.enterText(field.first, query);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await pumpUntil(
      tester,
      () => find.byType(SearchResultScreen).evaluate().isNotEmpty,
      reason: 'submitting the query should navigate to the results',
    );
    // The results screen fetches on arrival; give the list a chance to build.
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('a home tap fills the queue with similar songs', (tester) async {
    final handle = await bootTestApp(tester);
    handle.audioHandler.completeSourceLoadsAutomatically = true;

    await tester.tap(find.text('Fixture Song').hitTestable().first);
    await pumpUntil(
      tester,
      () => handle.audioHandler.queue.value.length == 2,
      reason: 'the tap should be expanded into its watch queue, not left as '
          'the single song that was tapped',
    );

    expect(handle.audioHandler.mediaItem.value?.id, 'song-1');
    expect(
      handle.audioHandler.queue.value.map((song) => song.id),
      ['song-1', 'song-2'],
    );
    await settleSongSideEffects(tester);
  });

  testWidgets('a search-result tap fills the queue with similar songs', (
    tester,
  ) async {
    // The other half of the reported symptom, and the half with no coverage at
    // all until now. It reaches the same `pushSongToQueue` as a home tap, but
    // through an entirely different widget tree.
    final handle = await bootTestApp(tester);
    handle.audioHandler.completeSourceLoadsAutomatically = true;

    await submitSearch(tester, 'fixture');
    final result = find.text('Fixture Song').hitTestable();
    expect(result, findsWidgets, reason: 'the search should list the fixture song');

    await tester.tap(result.first);
    await pumpUntil(
      tester,
      () => handle.audioHandler.queue.value.length == 2,
      reason: 'a searched song must expand into a queue exactly like a home tap',
    );
    expect(handle.audioHandler.mediaItem.value?.id, 'song-1');
    await settleSongSideEffects(tester);
  });

  testWidgets('a failed watch-playlist lookup is retried, not surrendered to', (
    tester,
  ) async {
    final music = _FlakyWatchQueueService(failuresBeforeSuccess: 1);
    final handle = await bootTestApp(tester, musicService: music);
    handle.audioHandler.completeSourceLoadsAutomatically = true;

    await tester.tap(find.text('Fixture Song').hitTestable().first);

    // The song itself never depended on the lookup and must not start waiting
    // on it now.
    await pumpUntil(
      tester,
      () => handle.audioHandler.mediaItem.value?.id == 'song-1',
      reason: 'playback starts against the placeholder queue regardless',
    );

    await pumpUntil(
      tester,
      () => handle.audioHandler.queue.value.length == 2,
      reason: 'the retry should recover the queue a single failure used to '
          'strand at one song',
      attempts: 60,
    );
    expect(music.watchQueueCalls, greaterThan(1));
    await settleSongSideEffects(tester);
  });

  testWidgets('the queue shows it is still filling while a retry is in flight', (
    tester,
  ) async {
    // Three failures put the success at ~7s of backoff (1s + 2s + 4s), which is
    // comfortably longer than the second or so it takes to open the player and
    // the queue panel below. One failure would land the queue at ~1s and race
    // the navigation.
    final music = _FlakyWatchQueueService(failuresBeforeSuccess: 3);
    final handle = await bootTestApp(tester, musicService: music);
    handle.audioHandler.completeSourceLoadsAutomatically = true;
    final controller = handle.container.read(playerControllerProvider);

    await tester.tap(find.text('Fixture Song').hitTestable().first);
    await pumpUntil(
      tester,
      () => controller.isQueueExpanding.value,
      reason: 'the wait has to be visible, or a slow queue is '
          'indistinguishable from one that never filled',
    );

    // Let the player surface before navigating. Reach the queue panel by
    // whichever route this device offers: with `autoOpenPlayer` on (the
    // default) and a phone-width screen the full player takes over by itself,
    // so the mini-player route exists only when it does not.
    await pumpUntil(
      tester,
      () => find.byIcon(Icons.keyboard_arrow_up).hitTestable().evaluate().isNotEmpty ||
          find
              .descendant(
                of: find.byType(MiniPlayer),
                matching: find.text('Fixture Song'),
              )
              .hitTestable()
              .evaluate()
              .isNotEmpty,
      reason: 'the player should appear once the song starts',
    );
    if (find.byIcon(Icons.keyboard_arrow_up).hitTestable().evaluate().isEmpty) {
      await openFullPlayer(tester);
    }
    await tester.tap(find.byIcon(Icons.keyboard_arrow_up).hitTestable().first);
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      controller.isQueueExpanding.value,
      isTrue,
      reason: 'the queue must still be filling, or this asserts nothing',
    );
    expect(find.byKey(const Key('queue-expanding-indicator')), findsOneWidget);

    // Three failures means the queue lands after 1s + 2s + 4s of backoff. Wait
    // past that: leaving the loop running into teardown also leaves Hive work
    // in flight against a directory the harness has already deleted.
    await pumpUntil(
      tester,
      () => !controller.isQueueExpanding.value,
      reason: 'the indicator must resolve once the queue lands',
      attempts: 200,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('queue-expanding-indicator')), findsNothing);
    expect(handle.audioHandler.queue.value.length, 2);
    await settleSongSideEffects(tester);
  });

  testWidgets('a newer tap cancels an in-flight retry loop', (tester) async {
    // A retry loop that outlives its own selection would eventually overwrite a
    // queue the user has since chosen — the exact failure the generation guard
    // exists to prevent, now that the lookup can live for seconds.
    final music = _FlakyWatchQueueService(failuresBeforeSuccess: 1);
    final handle = await bootTestApp(tester, musicService: music);
    handle.audioHandler.completeSourceLoadsAutomatically = true;
    final controller = handle.container.read(playerControllerProvider);

    await tester.tap(find.text('Fixture Song').hitTestable().first);
    await pumpUntil(tester, () => controller.isQueueExpanding.value);

    // Supersede it while the first lookup is still failing and backing off.
    // Through the controller rather than a second Home tile: by now the player
    // panel has auto-opened over Home, so the tile is not reachable — and what
    // is under test is the generation guard's effect on the retry loop, not the
    // widget route that bumps it. `remote_playback_test.dart` drives its
    // ordering races the same way.
    music.failuresBeforeSuccess = 0;
    await controller.pushSongToQueue(music.songTwo);
    await pumpUntil(
      tester,
      () =>
          handle.audioHandler.mediaItem.value?.id == 'song-2' &&
          handle.audioHandler.queue.value.length == 2,
      reason: 'the newer tap owns the queue',
      attempts: 60,
    );

    await pumpUntil(
      tester,
      () => !controller.isQueueExpanding.value,
      reason: 'the superseded loop must not leave the indicator running',
      attempts: 60,
    );
    await settleSongSideEffects(tester);
  });

  testWidgets('a permanently failing lookup degrades instead of hanging', (
    tester,
  ) async {
    // Every attempt throws. The song still plays, nothing escapes as an
    // unhandled async error, and the indicator gives up rather than spinning
    // forever — a degraded state that is decided rather than accidental.
    final music = _FlakyWatchQueueService(failuresBeforeSuccess: 1000);
    final handle = await bootTestApp(tester, musicService: music);
    handle.audioHandler.completeSourceLoadsAutomatically = true;
    final controller = handle.container.read(playerControllerProvider);

    await tester.tap(find.text('Fixture Song').hitTestable().first);
    await pumpUntil(
      tester,
      () => handle.audioHandler.mediaItem.value?.id == 'song-1',
      reason: 'a dead lookup must never stop the tapped song from playing',
    );

    // Confirm it actually started expanding first: without this the wait below
    // is satisfied by a flag that was never raised, and the test passes while
    // proving nothing.
    await pumpUntil(
      tester,
      () => controller.isQueueExpanding.value,
      reason: 'the expansion should be under way',
    );

    // Five attempts with 1s + 2s + 4s + 8s of backoff, so ~15s to exhaustion.
    // Waiting it out is also what leaves nothing in flight at teardown.
    await pumpUntil(
      tester,
      () => !controller.isQueueExpanding.value,
      reason: 'the retries are bounded, so the indicator must resolve',
      attempts: 300,
    );
    expect(handle.audioHandler.queue.value.map((song) => song.id), ['song-1']);
    expect(
      music.watchQueueCalls,
      5,
      reason: 'every attempt should have been made before giving up',
    );
    await settleSongSideEffects(tester);
  });

  testWidgets('an unparseable response is given up on immediately', (
    tester,
  ) async {
    // The failure actually seen on Windows: `getTabBrowseId` indexed through a
    // watch-panel tab that carried no `endpoint`, so the response arrived and
    // the parse threw. Retrying that cannot help — the same document parses the
    // same way every time — and doing it anyway kept the "finding similar
    // songs" row up for ~15s before admitting nothing was coming.
    final music = _FlakyWatchQueueService(
      failuresBeforeSuccess: 1000,
      failure: _LookupFailure.unparseable,
    );
    final handle = await bootTestApp(tester, musicService: music);
    handle.audioHandler.completeSourceLoadsAutomatically = true;
    final controller = handle.container.read(playerControllerProvider);

    await tester.tap(find.text('Fixture Song').hitTestable().first);

    // Anchor on the lookup itself, not on the handler's song: the audio handler
    // is shared across the whole suite and still holds `song-1` from an earlier
    // test, so waiting on that would pass before this tap did anything at all.
    await pumpUntil(
      tester,
      () => music.watchQueueCalls >= 1,
      reason: 'the tap should attempt a queue expansion',
    );

    // Long enough that a retry would have happened: the first backoff is 1s.
    await tester.pump(const Duration(seconds: 2));

    expect(
      music.watchQueueCalls,
      1,
      reason: 'a response that failed to parse must be attempted exactly once — '
          'the same document parses the same way every time',
    );
    expect(
      controller.isQueueExpanding.value,
      isFalse,
      reason: 'the indicator must clear at once, not after fifteen seconds of '
          'pointless backoff',
    );
    expect(handle.audioHandler.mediaItem.value?.id, 'song-1');
    expect(handle.audioHandler.queue.value.map((song) => song.id), ['song-1']);
    await settleSongSideEffects(tester);
  });

  // ---------------------------------------------------------------------------
  // Cross-device favorite freshness
  //
  // `isCurrentSongFav` used to only ever update on a song change or a local
  // toggle. Liking a song on the phone reached this device's Hive box fine —
  // cloud sync's own tests already covered that — but the heart icon on an
  // already-open Windows session kept showing unliked regardless, because
  // nothing re-checked it once the pull landed. These are the sync-facing half
  // of that fix: `PlayerControllerRegistry` making the running controller
  // reachable from a background service, and `refreshFavoriteStatus` actually
  // updating `isCurrentSongFav` when asked to.
  // ---------------------------------------------------------------------------

  testWidgets(
    'PlayerControllerRegistry exposes the same instance the app is running',
    (tester) async {
      final handle = await bootTestApp(tester);

      expect(
        PlayerControllerRegistry.current,
        same(handle.container.read(playerControllerProvider)),
      );
    },
  );

  testWidgets(
    'refreshFavoriteStatus updates the heart icon for a favorite that arrived '
    'from outside the player — the shape a sync pull takes',
    (tester) async {
      final handle = await startFixturePlayback(tester);
      final controller = handle.container.read(playerControllerProvider);
      expect(controller.currentSong.value?.id, 'song-1');
      expect(
        controller.isCurrentSongFav.value,
        isFalse,
        reason: 'the fixture song starts unliked',
      );

      // Not `toggleFavourite()` — that is the LOCAL toggle path and already
      // updates the icon on its own. This writes to Hive the way
      // `CloudSyncRepository.applyRemote` does when a pull lands a favorite
      // from another device: straight to the box, with nothing in between
      // that would notify the player.
      await handle.container
          .read(libraryRepositoryProvider)
          .setFavorite(controller.currentSong.value!, true);
      expect(
        controller.isCurrentSongFav.value,
        isFalse,
        reason: 'confirms the write alone does not reach the icon — that is '
            'the bug this method exists to close',
      );

      await PlayerControllerRegistry.current!.refreshFavoriteStatus();

      expect(controller.isCurrentSongFav.value, isTrue);
    },
  );

  testWidgets(
    'refreshFavoriteStatus is a no-op with nothing playing',
    (tester) async {
      final handle = await bootTestApp(tester);
      final controller = handle.container.read(playerControllerProvider);
      expect(controller.currentSong.value, isNull);

      // Must not throw reaching for a current song that does not exist — a
      // sync can land before the user has ever tapped a song.
      await controller.refreshFavoriteStatus();

      expect(controller.isCurrentSongFav.value, isFalse);
    },
  );

  testWidgets('with autoOpenPlayer on, the full player takes over by itself', (
    tester,
  ) async {
    // The harness pins the preference off so MiniPlayer assertions do not
    // depend on the device's screen width. Production defaults it *on*, so
    // that path needs covering somewhere or the flip would quietly delete the
    // only test of it.
    final handle = await bootTestApp(tester, autoOpenPlayer: true);
    handle.audioHandler.completeSourceLoadsAutomatically = true;

    await tester.tap(find.text('Fixture Song').hitTestable().first);
    await pumpUntil(
      tester,
      () => find.byType(AlbumArtNLyrics).hitTestable().evaluate().isNotEmpty,
      reason: 'the full player should open without the user tapping again',
    );
  });
}

/// A music service whose watch-playlist lookup throws the first
/// [failuresBeforeSuccess] times it is called.
///
/// Modelled on `_HomeSelectionMusicService` in `remote_playback_test.dart`:
/// subclass the shared fake and override the one call the scenario is about.
enum _LookupFailure { transient, unparseable }

class _FlakyWatchQueueService extends FakeMusicService {
  _FlakyWatchQueueService({
    required this.failuresBeforeSuccess,
    this.failure = _LookupFailure.transient,
  });

  int failuresBeforeSuccess;

  /// Which kind of failure to raise. The controller retries only failures that
  /// never reached a usable response; a parse error is given up on at once.
  final _LookupFailure failure;

  int watchQueueCalls = 0;

  @override
  Future<Map<String, dynamic>> getWatchPlaylist({
    String videoId = "",
    String? playlistId,
    int limit = 25,
    bool radio = false,
    bool shuffle = false,
    String? additionalParamsNext,
    bool onlyRelated = false,
  }) async {
    watchQueueCalls++;
    if (watchQueueCalls <= failuresBeforeSuccess) {
      throw switch (failure) {
        // A request that never completed — the case retrying exists for.
        _LookupFailure.transient => DioException.connectionError(
          requestOptions: RequestOptions(path: '/youtubei/v1/next'),
          reason: 'watch playlist unreachable',
        ),
        // The shape that actually bit on Windows: the response arrived and the
        // parser choked on it. `getTabBrowseId` raised exactly this by indexing
        // through a tab that carried no `endpoint`.
        _LookupFailure.unparseable => NoSuchMethodError.withInvocation(
          null,
          Invocation.method(#[], const ['browseEndpoint']),
        ),
      };
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
