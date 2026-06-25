import 'dart:async';

import 'package:get/get.dart';
import 'package:harmonymusic/utils/helper.dart';
import 'package:smtc_windows/smtc_windows.dart';

import '../ui/player/player_controller.dart';

class WindowsAudioService extends GetxService {
  late SMTCWindows smtc;
  final playerController = Get.find<PlayerController>();

  @override
  void onInit() {
    _initService();
    super.onInit();
  }

  _initService() {
    smtc = SMTCWindows(enabled: false);
    try {
      smtc.buttonPressStream.listen((event) async {
        switch (event) {
          case PressedButton.play:
            playerController.requestPlay();
            await smtc.setPlaybackStatus(PlaybackStatus.playing);
            break;
          case PressedButton.pause:
            playerController.requestPause();
            await smtc.setPlaybackStatus(PlaybackStatus.paused);
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
      printERROR("Error: $e");
    }

    playerController.buttonState.listen((state) async {
      switch (state) {
        case PlayButtonState.playing:
          await smtc.setPlaybackStatus(PlaybackStatus.playing);
          break;
        case PlayButtonState.paused:
          await smtc.setPlaybackStatus(PlaybackStatus.paused);
          break;
        case PlayButtonState.loading:
          await smtc.setPlaybackStatus(PlaybackStatus.paused);
          break;
      }
    });

    playerController.progressBarStatus.listen((status) async {
      await smtc.setPosition(status.current);
    });

    playerController.currentSong.listen((song) async {
      if (song != null) {
        if (!smtc.enabled) await smtc.enableSmtc();
        await smtc.updateMetadata(
          MusicMetadata(
            title: song.title,
            album: song.album,
            albumArtist: song.artist,
            artist: song.artist,
            thumbnail: song.artUri.toString(),
          ),
        );
        await smtc.setEndTime(playerController.progressBarStatus.value.total);
      }
    });
  }

  @override
  void onClose() {
    // GetX expects a sync lifecycle hook; run cleanup async without dropping errors.
    unawaited(_disposeSmtc());
    super.onClose();
  }

  Future<void> _disposeSmtc() async {
    try {
      await smtc.clearMetadata();
      await smtc.disableSmtc();
      await smtc.dispose();
    } catch (e) {
      printERROR("Error while disposing SMTC: $e");
    }
  }
}
