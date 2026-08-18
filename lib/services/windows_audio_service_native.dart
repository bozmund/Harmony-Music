import 'dart:async';

import 'package:harmonymusic/utils/helper.dart';
import 'package:smtc_windows/smtc_windows.dart';

import '../ui/player/player_controller.dart';

class WindowsAudioService {
  WindowsAudioService(this.playerController) {
    _initService();
  }

  SMTCWindows? smtc;
  final PlayerController playerController;

  void _initService() {
    late final SMTCWindows session;
    try {
      session = SMTCWindows(enabled: false);
      smtc = session;
      session.buttonPressStream.listen((event) async {
        switch (event) {
          case PressedButton.play:
            playerController.requestPlay();
            await session.setPlaybackStatus(PlaybackStatus.playing);
            break;
          case PressedButton.pause:
            playerController.requestPause();
            await session.setPlaybackStatus(PlaybackStatus.paused);
            break;
          case PressedButton.next:
            playerController.requestNext();
            break;
          case PressedButton.previous:
            playerController.requestPrev();
            break;
          default:
            break;
        }
      });
    } catch (e) {
      printERROR('Error: $e');
      return;
    }

    playerController.buttonState.listen((state) async {
      switch (state) {
        case PlayButtonState.playing:
          await session.setPlaybackStatus(PlaybackStatus.playing);
          break;
        case PlayButtonState.paused:
        case PlayButtonState.loading:
          await session.setPlaybackStatus(PlaybackStatus.paused);
          break;
      }
    });

    playerController.progressBarStatus.listen((status) async {
      await session.setPosition(status.current);
    });

    playerController.currentSong.listen((song) async {
      if (song == null) return;
      if (!session.enabled) await session.enableSmtc();
      await session.updateMetadata(
        MusicMetadata(
          title: song.title,
          album: song.album,
          albumArtist: song.artist,
          artist: song.artist,
          thumbnail: song.artUri.toString(),
        ),
      );
      await session.setEndTime(playerController.progressBarStatus.value.total);
    });
  }

  void dispose() {
    unawaited(_disposeSmtc());
  }

  Future<void> _disposeSmtc() async {
    final session = smtc;
    if (session == null) return;
    try {
      await session.clearMetadata();
      await session.disableSmtc();
      await session.dispose();
    } catch (e) {
      printERROR('Error while disposing SMTC: $e');
    }
  }
}
