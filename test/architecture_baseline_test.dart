import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/app/providers/app_locale_provider.dart';
import 'package:harmonymusic/l10n/app_localizations.dart';
import 'package:harmonymusic/l10n/app_localizations_en.dart';
import 'package:harmonymusic/utils/lang_mapping.dart';

void main() {
  test('pubspec standardizes app tests on mocktail instead of mockito', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('mocktail:'));
    expect(pubspec, isNot(contains('mockito:')));
  });

  test('bundled Auth0 environment contains only public client settings', () {
    final envFile = File('.env');
    expect(envFile.existsSync(), isTrue);

    final keys = envFile
        .readAsLinesSync()
        .where((line) => line.contains('=') && !line.trimLeft().startsWith('#'))
        .map((line) => line.split('=').first.trim())
        .toSet();
    expect(keys, {
      'AUTH0_DOMAIN',
      'AUTH0_CLIENT_ID',
      'AUTH0_REDIRECT_SCHEME',
      'AUTH0_AUDIENCE',
    });
    expect(
      keys.where((key) => RegExp(r'SECRET|PASSWORD|TOKEN').hasMatch(key)),
      isEmpty,
    );
  });

  test('Flutter gen-l10n baseline exposes the app title', () {
    expect(AppLocalizationsEn().appTitle, 'Harmony Music');
  });

  test('Flutter gen-l10n only builds English and Croatian', () {
    final activeArbs = Directory('lib/l10n')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.arb'))
        .map((file) => file.uri.pathSegments.last)
        .toSet();
    final generatedLocales = AppLocalizations.supportedLocales
        .map((locale) => locale.languageCode)
        .toSet();

    expect(activeArbs, {'app_en.arb', 'app_hr.arb'});
    expect(generatedLocales, {'en', 'hr'});
    expect(langMap.keys.toSet(), {'en', 'hr'});
    expect(Directory('lib/l10n/unused').existsSync(), isTrue);
    expect(
      Directory('lib/l10n/unused').listSync().whereType<File>(),
      isNotEmpty,
    );
  });

  test('old persisted language codes fall back to English', () {
    final settingsController = File(
      'lib/ui/screens/Settings/settings_screen_controller.dart',
    ).readAsStringSync();

    expect(AppLocaleController('de').locale.languageCode, 'en');
    expect(AppLocaleController('hr').locale.languageCode, 'hr');
    expect(settingsController, contains('_normalizeAppLanguageCode'));
    expect(settingsController, contains('langMap.containsKey(languageCode)'));
  });

  test('player UI rebuilds from scoped observable state', () {
    final dartFiles = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains('ref.watch(playerControllerProvider)')),
        reason:
            '${file.path} should read the controller and listen to scoped '
            'ObservableValue/ObservableList instances instead.',
      );
      expect(
        source,
        isNot(contains('animation: playerController,')),
        reason: '${file.path} should not rebuild on every player notification.',
      );
    }
  });
}
