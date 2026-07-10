import 'package:flutter/widgets.dart';

import 'app_localizations.dart';
import 'app_localizations_en.dart';
import 'app_localizations_hr.dart';

AppLocalizations appLocalizationsForLanguageCode(String languageCode) =>
    languageCode == 'hr' ? AppLocalizationsHr() : AppLocalizationsEn();

extension AppLocalizationsBuildContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}

extension AppLocalizationsDynamicLabels on AppLocalizations {
  String libraryTab(String key) => switch (key) {
    'songs' => songs,
    'searches' => searches,
    'playlists' => playlists,
    'albums' => albums,
    'artists' => artists,
    _ => key,
  };

  String sectionTitle(String value) =>
      switch (value.toLowerCase().replaceAll(RegExp(r'\s+'), '')) {
        'discover' => discover,
        'quickpicks' => quickpicks,
        'trending' => trending,
        'songs' => songs,
        'playlists' => playlists,
        'albums' => albums,
        'artists' => artists,
        'communityplaylists' => communityplaylists,
        'featuredplaylists' => featuredplaylists,
        'results' => results,
        _ => value,
      };
}
