import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/data/repositories/hive_settings_repository.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:harmonymusic/services/resolver/resolver_configuration.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory hiveDir;
  late HiveSettingsRepository settings;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('resolver_config_test_');
    Hive.init(hiveDir.path);
    await Hive.openBox(BoxNames.appPrefs);
    settings = HiveSettingsRepository();
  });

  tearDown(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  test('normalizes debug URL and rejects credentials or paths', () {
    expect(
      ResolverConfiguration.normalize(
        'http://192.168.8.22:8088/',
        production: false,
      ).toString(),
      'http://192.168.8.22:8088',
    );
    expect(
      () => ResolverConfiguration.normalize(
        'http://user:secret@host:8088',
        production: false,
      ),
      throwsFormatException,
    );
    expect(
      () => ResolverConfiguration.normalize(
        'http://host:8088/private',
        production: false,
      ),
      throwsFormatException,
    );
  });

  test('production requires HTTPS', () {
    expect(
      () => ResolverConfiguration.normalize(
        'http://resolver.example',
        production: true,
      ),
      throwsFormatException,
    );
    expect(
      ResolverConfiguration.normalize(
        'https://resolver.example/',
        production: true,
      ).toString(),
      'https://resolver.example',
    );
  });

  test('debug and production overrides are persisted separately', () async {
    await settings.setResolverDebugOverride('http://192.168.8.22:8088');
    await settings.setResolverProductionOverride('https://resolver.example');

    expect(settings.getResolverDebugOverride(), 'http://192.168.8.22:8088');
    expect(
      settings.getResolverProductionOverride(),
      'https://resolver.example',
    );
  });

  test('resolver defaults enabled and can be opted out', () async {
    expect(settings.getResolverEnabled(), isTrue);
    await settings.setResolverEnabled(false);
    expect(settings.getResolverEnabled(), isFalse);
  });

  test('discovered debug endpoint takes precedence over build fallback', () {
    final configuration = ResolverConfiguration.load(
      settings,
      releaseMode: false,
      discovered: Uri.parse('http://192.168.8.44:8088'),
    );
    expect(configuration.baseUrl.toString(), 'http://192.168.8.44:8088');
  });
}
