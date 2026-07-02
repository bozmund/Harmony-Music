import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/utils/get_localization.dart';

/// The localization/*.json files are the source of truth;
/// lib/utils/get_localization.dart is generated from them
/// (`dart run localization/generator.dart`). These tests fail whenever the
/// two drift apart — e.g. someone edits a JSON without regenerating, or
/// hand-edits the generated file.
void main() {
  late Map<String, Map<String, String>> generated;
  late Map<String, Map<String, dynamic>> sources;

  setUpAll(() {
    generated = Languages().keys;
    sources = {
      for (final file in Directory('localization')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json')))
        file.uri.pathSegments.last.split('.').first:
            jsonDecode(file.readAsStringSync()),
    };
  });

  test('every localization JSON has a generated language and vice versa', () {
    expect(generated.keys.toSet(), sources.keys.toSet());
  });

  test('generated strings match the JSON sources exactly', () {
    final problems = <String>[];
    for (final lang in sources.keys) {
      final source = sources[lang]!;
      final built = generated[lang] ?? const <String, String>{};
      for (final key in source.keys) {
        if (!built.containsKey(key)) {
          problems.add('$lang: "$key" missing from generated file');
        } else if (built[key] != source[key]) {
          problems.add('$lang: "$key" value differs from JSON');
        }
      }
      for (final key in built.keys) {
        if (!source.containsKey(key)) {
          problems.add('$lang: "$key" exists only in the generated file');
        }
      }
    }
    expect(
      problems,
      isEmpty,
      reason:
          'Regenerate with: dart run localization/generator.dart '
          '&& dart format lib/utils/get_localization.dart',
    );
  });

  test('the runtime Chinese lookup keys exist as languages', () {
    // The .tr extension resolves Traditional/Simplified Chinese via the
    // zh_Hant / zh_Hans keys; the old generator emitted zh-TW / zh-CN,
    // which silently made Chinese fall back to English.
    expect(generated.containsKey('zh_Hant'), isTrue);
    expect(generated.containsKey('zh_Hans'), isTrue);
  });

  test('English covers every key used with .tr fallback safety', () {
    // English is the final fallback for every other locale, so any key
    // present in another language must exist in English too.
    final english = generated['en']!;
    final missing = <String>{};
    for (final lang in generated.keys) {
      if (lang == 'en') continue;
      for (final key in generated[lang]!.keys) {
        if (!english.containsKey(key)) missing.add('$lang→$key');
      }
    }
    expect(
      missing,
      isEmpty,
      reason: 'Keys translated elsewhere but missing from en.json',
    );
  });
}
