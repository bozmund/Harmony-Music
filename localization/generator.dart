import 'dart:convert';
import 'dart:io';

/// Regenerates lib/utils/get_localization.dart from the localization/*.json
/// files. Run from the repository root:
///
///     dart run localization/generator.dart
///     dart format lib/utils/get_localization.dart
///
/// The JSON files are the source of truth for every string; the `.tr`
/// runtime (embedded below) falls back to English and then to the raw key.
/// test/localization_sync_test.dart fails whenever the generated file and
/// the JSON sources drift apart.
Future<void> generate() async {
  const outputFile = './lib/utils/get_localization.dart';

  final languageFiles =
      Directory('./localization')
          .listSync(followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final buffer = StringBuffer()
    ..writeln('// This is auto generated file')
    ..writeln('// Do not modify this file manually')
    ..writeln('//')
    ..writeln('// Regenerate with: dart run localization/generator.dart')
    ..writeln()
    ..writeln("import 'dart:ui' as ui;")
    ..writeln()
    ..writeln("import 'package:flutter/widgets.dart';")
    ..writeln()
    ..writeln("import '../app/navigation/app_navigator.dart';")
    ..writeln()
    ..writeln('class Languages {')
    ..writeln('  Map<String, Map<String, String>> get keys => {');

  for (final file in languageFiles) {
    final languageCode = file.uri.pathSegments.last.split('.').first;
    final Map<String, dynamic> strings = jsonDecode(file.readAsStringSync());

    buffer.writeln('    ${_dartString(languageCode)}: {');
    for (final entry in strings.entries) {
      buffer.writeln(
        '      ${_dartString(entry.key)}: '
        '${_dartString(entry.value.toString())},',
      );
    }
    buffer.writeln('    },');
  }

  buffer
    ..writeln('  };')
    ..writeln('}')
    ..writeln()
    ..write(_translationRuntime);

  await File(outputFile).writeAsString(buffer.toString());
}

/// Encodes [value] as a double-quoted Dart string literal, escaping the
/// characters Dart treats specially (JSON escapes were already resolved by
/// jsonDecode, so `$` in particular must not become interpolation).
String _dartString(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
  return '"$escaped"';
}

const _translationRuntime = '''
extension HarmonyStringLocalization on String {
  String get tr {
    final translations = Languages().keys;
    for (final localeKey in _localeKeys()) {
      final translated = translations[localeKey]?[this];
      if (translated != null) return translated;
    }
    return translations['en']?[this] ?? this;
  }

  String get removeAllWhitespace => replaceAll(RegExp(r'\\s+'), '');

  List<String> _localeKeys() {
    final locale = _currentLocale();
    final keys = <String>[
      if (locale.languageCode == 'zh' && locale.scriptCode == 'Hant') 'zh_Hant',
      if (locale.languageCode == 'zh' && locale.scriptCode == 'Hans') 'zh_Hans',
      if (locale.countryCode != null && locale.countryCode!.isNotEmpty)
        '\${locale.languageCode}_\${locale.countryCode}',
      locale.languageCode,
      'en',
    ];
    return keys.toSet().toList();
  }

  Locale _currentLocale() {
    final BuildContext? context;
    try {
      context = AppNavigator.context;
    } catch (_) {
      return ui.PlatformDispatcher.instance.locale;
    }
    if (context != null) {
      return Localizations.maybeLocaleOf(context) ??
          ui.PlatformDispatcher.instance.locale;
    }
    return ui.PlatformDispatcher.instance.locale;
  }
}
''';

Future<void> main() async {
  await generate();
}
