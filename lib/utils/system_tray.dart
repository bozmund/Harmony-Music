import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class DesktopSystemTray with TrayListener {
  DesktopSystemTray({
    required AudioHandler audioHandler,
    required PlayerController playerController,
    required SettingsScreenController settingsScreenController,
  }) : _audioHandler = audioHandler,
       _playerController = playerController,
       _settingsScreenController = settingsScreenController {
    trayManager.addListener(this);
    Future.delayed(const Duration(seconds: 2), () => initSystemTray());
  }

  final AudioHandler _audioHandler;
  final PlayerController _playerController;
  final SettingsScreenController _settingsScreenController;
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
  }) : _audioHandler = audioHandler,
       _playerController = playerController,
       _settingsScreenController = settingsScreenController;

  final AudioHandler _audioHandler;
  final PlayerController _playerController;
  final SettingsScreenController _settingsScreenController;

  @override
  Future<void> onWindowClose() async {
    if (_settingsScreenController.backgroundPlayEnabled.value &&
        _playerController.buttonState.value == PlayButtonState.playing) {
      await windowManager.hide();
    } else {
      await _audioHandler.customAction("saveSession");
      exit(0);
    }
  }
}
