import '../l10n/app_localizations.dart';

class PlayingFrom {
  PlayingFromType type;
  String name;

  PlayingFrom({required this.type, this.name = ""});

  String typeString(AppLocalizations l10n) {
    switch (type) {
      case PlayingFromType.ALBUM:
        return l10n.playingFromAlbum;
      case PlayingFromType.PLAYLIST:
        return l10n.playingFromPlaylist;
      case PlayingFromType.SELECTION:
        return l10n.playingFromSelection;
      case PlayingFromType.ARTIST:
        return l10n.playingFromArtist;
    }
  }

  String nameString(AppLocalizations l10n) {
    if (type == PlayingFromType.SELECTION) return l10n.randomSelection;
    return name;
  }
}

enum PlayingFromType { ALBUM, PLAYLIST, SELECTION, ARTIST }
