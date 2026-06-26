import 'package:get/get.dart';

class PlayingFrom {
  PlayingFromType type;
  String name;

  PlayingFrom({required this.type, this.name = ""});

  get typeString {
    switch (type) {
      case PlayingFromType.ALBUM:
        return "playingFromAlbum".tr;
      case PlayingFromType.PLAYLIST:
        return "playingFromPlaylist".tr;
      case PlayingFromType.SELECTION:
        return "playingFromSelection".tr;
      case PlayingFromType.ARTIST:
        return "playingFromArtist".tr;
    }
  }

  get nameString {
    if (type == PlayingFromType.SELECTION) return "randomSelection".tr;
    return name;
  }
}

enum PlayingFromType { ALBUM, PLAYLIST, SELECTION, ARTIST }

