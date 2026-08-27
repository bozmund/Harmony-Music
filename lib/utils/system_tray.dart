import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:harmonymusic/services/cloud/cloud_playback_receiver.dart';
import 'package:harmonymusic/services/crash_diagnostics_service.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Ends a cloud playback session before this process goes away.
///
/// Closing the app is the same intent as tapping "Leave sync": whatever this
/// device was driving must not be left playing on the other end, and the
/// server's target marker must not outlive the app that claimed it - a stale
/// marker makes the devices sheet keep reporting this machine as "Playing
/// here". Both exit paths call exit(0), which skips the detached lifecycle
/// callback, so this is the only place it can run.
///
/// Bounded on purpose: an unreachable server must not hold the window open.
/// Losing the session cleanup is a far smaller failure than refusing to quit.
Future<void> _endCloudSessionBeforeExit(CloudPlaybackReceiver receiver) async {
  if (!receiver.isEngaged) return;
  try {
    await receiver.leaveSync().timeout(const Duration(seconds: 3));
  } catch (error, stackTrace) {
    CrashDiagnosticsService.instance.record(
      'cloud-playback',
      'Unable to leave sync while closing the app',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

class DesktopSystemTray with TrayListener {
  DesktopSystemTray({
    required AudioHandler audioHandler,
    required PlayerController playerController,
    required SettingsScreenController settingsScreenController,
    required CloudPlaybackReceiver playbackReceiver,
  }) : _audioHandler = audioHandler,
       _playerController = playerController,
       _settingsScreenController = settingsScreenController,
       _playbackReceiver = playbackReceiver {
    trayManager.addListener(this);
    Future.delayed(const Duration(seconds: 2), () => initSystemTray());
  }

  final AudioHandler _audioHandler;
  final PlayerController _playerController;
  final SettingsScreenController _settingsScreenController;
  final CloudPlaybackReceiver _playbackReceiver;
  WindowListener? listener;

  Future<void> initSystemTray() async {
    String path = Platform.isWindows
        ? 'assets/icons/icon.ico'
        : 'assets/icons/icon.png';

    await windowManager.ensureInitialized();

    await trayManager.setIcon(path);

    // create context menu
    final Menu menu = Menu(
      items: [
        MenuItem(
          label: 'Show/Hide',
          onClick: (menuItem) async => await windowManager.isVisible()
              ? await windowManager.hide()
              : await windowManager.show(),
        ),
        MenuItem.separator(),
        MenuItem(
          label: 'Prev',
          onClick: (menuItem) async {
            if (_playerController.currentQueue.isNotEmpty) {
              _playerController.requestPrev();
            }
          },
        ),
        MenuItem(
          label: 'Play/Pause',
          onClick: (menuItem) async {
            if (_playerController.currentQueue.isNotEmpty) {
              _playerController.requestPlayPause();
            }
          },
        ),
        MenuItem(
          label: 'Next',
          onClick: (menuItem) async {
            if (_playerController.currentQueue.isNotEmpty) {
              _playerController.requestNext();
            }
          },
        ),
        MenuItem.separator(),
        MenuItem(
          label: 'Quit',
          onClick: (menuItem) async {
            await _endCloudSessionBeforeExit(_playbackReceiver);
            await _audioHandler.customAction("saveSession");
            exit(0);
          },
        ),
      ],
    );

    // set context menu
    await trayManager.setContextMenu(menu);

    await windowManager.setPreventClose(true);
    listener = CloseWindowListener(
      audioHandler: _audioHandler,
      playerController: _playerController,
      settingsScreenController: _settingsScreenController,
      playbackReceiver: _playbackReceiver,
    );
    windowManager.addListener(listener!);
  }

  void dispose() {
    trayManager.removeListener(this);
    final windowListener = listener;
    if (windowListener != null) {
      windowManager.removeListener(windowListener);
    }
  }

  @override
  Future<void> onTrayIconMouseDown() async {
    if (Platform.isWindows) {
      await windowManager.show();
    } else {
      await trayManager.popUpContextMenu();
    }

    super.onTrayIconMouseDown();
  }

  @override
  Future<void> onTrayIconRightMouseDown() async {
    if (Platform.isWindows) {
      await trayManager.popUpContextMenu();
    } else {
      await windowManager.show();
    }

    super.onTrayIconRightMouseDown();
  }
}

class CloseWindowListener extends WindowListener {
  CloseWindowListener({
    required AudioHandler audioHandler,
    required PlayerController playerController,
    required SettingsScreenController settingsScreenController,
    required CloudPlaybackReceiver playbackReceiver,
  }) : _audioHandler = audioHandler,
       _playerController = playerController,
       _settingsScreenController = settingsScreenController,
       _playbackReceiver = playbackReceiver;

  final AudioHandler _audioHandler;
  final PlayerController _playerController;
  final SettingsScreenController _settingsScreenController;
  final CloudPlaybackReceiver _playbackReceiver;

  @override
  Future<void> onWindowClose() async {
    if (_settingsScreenController.backgroundPlayEnabled.value &&
        _playerController.buttonState.value == PlayButtonState.playing) {
      await windowManager.hide();
    } else {
      await _endCloudSessionBeforeExit(_playbackReceiver);
      await _audioHandler.customAction("saveSession");
      exit(0);
    }
  }
}
