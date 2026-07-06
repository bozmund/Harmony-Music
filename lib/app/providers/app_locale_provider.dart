import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'repository_providers.dart';

class AppLocaleController extends ChangeNotifier {
  AppLocaleController(String initialLanguageCode)
    : _locale = _localeFromLanguageCode(initialLanguageCode);

  Locale _locale;

  Locale get locale => _locale;

  void setLanguageCode(String languageCode) {
    final nextLocale = _localeFromLanguageCode(languageCode);
    if (_locale == nextLocale) return;
    _locale = nextLocale;
    notifyListeners();
  }

  static Locale _localeFromLanguageCode(String languageCode) {
    return switch (languageCode) {
      'hr' => const Locale('hr'),
      _ => const Locale('en'),
    };
  }
}

final appLocaleControllerProvider = ChangeNotifierProvider<AppLocaleController>(
  (ref) => AppLocaleController(
    ref.watch(settingsRepositoryProvider).getLanguageCode(),
  ),
);
