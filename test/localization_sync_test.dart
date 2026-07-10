import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/l10n/l10n.dart';

void main() {
  late Map<String, dynamic> english;
  late Map<String, dynamic> croatian;

  setUpAll(() {
    english = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync());
    croatian = jsonDecode(File('lib/l10n/app_hr.arb').readAsStringSync());
  });

  test('English and Croatian ARBs expose identical resources', () {
    Set<String> resources(Map<String, dynamic> arb) => arb.keys
        .where((key) => key != '@@locale' && !key.startsWith('@'))
        .toSet();

    expect(resources(croatian), resources(english));
  });

  test('localized placeholders have matching declarations', () {
    final problems = <String>[];
    for (final key in english.keys.where((key) => key.startsWith('@'))) {
      if (key == '@@locale') continue;
      final enPlaceholders =
          (english[key] as Map<String, dynamic>?)?['placeholders'];
      final hrPlaceholders =
          (croatian[key] as Map<String, dynamic>?)?['placeholders'];
      if (jsonEncode(enPlaceholders) != jsonEncode(hrPlaceholders)) {
        problems.add(key.substring(1));
      }
    }
    expect(problems, isEmpty, reason: 'Placeholder declarations differ');
  });

  test('legacy localization runtime is not referenced', () {
    final violations = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains(RegExp(r'\.tr\b')) ||
          source.contains('get_localization.dart')) {
        violations.add(entity.path);
      }
    }
    expect(violations, isEmpty);
  });

  test('background labels follow the persisted language code', () {
    expect(appLocalizationsForLanguageCode('en').songs, 'Songs');
    expect(appLocalizationsForLanguageCode('hr').songs, 'Pjesme');
    expect(appLocalizationsForLanguageCode('unsupported').songs, 'Songs');
  });
}
