import '../ui/player/player_controller.dart';

/// Windows System Media Transport Controls are unavailable in browsers.
class WindowsAudioService {
  WindowsAudioService(PlayerController playerController);

  void dispose() {}
}
