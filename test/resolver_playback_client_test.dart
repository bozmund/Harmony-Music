import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/data/repositories/hive_settings_repository.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:harmonymusic/services/resolver/resolver_playback_client.dart';
import 'package:harmonymusic/services/resolver/resolver_discovery_service.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory hiveDir;
  late HiveSettingsRepository settings;
  late HttpServer server;
  final fixture = Uint8List.fromList('OggSvalid-opus-fixture'.codeUnits);

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('resolver_playback_test_');
    Hive.init(hiveDir.path);
    await Hive.openBox(BoxNames.appPrefs);
    settings = HiveSettingsRepository();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    await settings.setResolverDebugOverride(
      'http://${server.address.address}:${server.port}',
    );
  });

  tearDown(() async {
    await server.close(force: true);
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  test(
    'follows 202, attaches token, validates Ogg, and reopens ranges',
    () async {
      var requestCount = 0;
      final authorizationHeaders = <String?>[];
      final ranges = <String?>[];
      final ifRanges = <String?>[];
      server.listen((request) async {
        requestCount++;
        authorizationHeaders.add(
          request.headers.value(HttpHeaders.authorizationHeader),
        );
        ranges.add(request.headers.value(HttpHeaders.rangeHeader));
        ifRanges.add(request.headers.value(HttpHeaders.ifRangeHeader));
        if (requestCount == 1) {
          request.response
            ..statusCode = HttpStatus.accepted
            ..headers.set(HttpHeaders.retryAfterHeader, '0');
          await request.response.close();
          return;
        }
        final range = request.headers.value(HttpHeaders.rangeHeader);
        request.response.headers.contentType = ContentType('audio', 'ogg');
        request.response.headers.set(HttpHeaders.etagHeader, '"fixture-v1"');
        if (range != null) {
          request.response
            ..statusCode = HttpStatus.partialContent
            ..headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes 4-7/${fixture.length}',
            )
            ..add(fixture.sublist(4, 8));
        } else {
          request.response
            ..statusCode = HttpStatus.ok
            ..contentLength = fixture.length
            ..add(fixture);
        }
        await request.response.close();
      });

      final client = ResolverPlaybackClient(
        settings: settings,
        accessToken: () async => 'test-token',
      );
      final source = await client.open('dQw4w9WgXcQ');
      expect(source, isNotNull);

      final initial = await source!.request();
      expect(await initial.stream.expand((chunk) => chunk).toList(), fixture);
      final range = await source.request(4, 8);
      expect(
        await range.stream.expand((chunk) => chunk).toList(),
        fixture.sublist(4, 8),
      );
      expect(authorizationHeaders, everyElement('Bearer test-token'));
      expect(ranges.last, 'bytes=4-7');
      expect(ifRanges.last, '"fixture-v1"');
    },
  );

  test('rejects non-Ogg response', () async {
    server.listen((request) async {
      request.response.headers.contentType = ContentType('audio', 'ogg');
      request.response.add('not-an-ogg'.codeUnits);
      await request.response.close();
    });
    final client = ResolverPlaybackClient(
      settings: settings,
      accessToken: () async => null,
    );
    expect(await client.open('dQw4w9WgXcQ'), isNull);
  });

  test(
    'falls back to mDNS result without leaking token over discovered HTTP',
    () async {
      await settings.setResolverDebugOverride('http://127.0.0.1:1');
      String? authorization;
      server.listen((request) async {
        authorization = request.headers.value(HttpHeaders.authorizationHeader);
        request.response.headers.contentType = ContentType('audio', 'ogg');
        request.response.add(fixture);
        await request.response.close();
      });
      final discovered = Uri.parse(
        'http://${server.address.address}:${server.port}',
      );
      final client = ResolverPlaybackClient(
        settings: settings,
        accessToken: () async => 'must-not-leak',
        discovery: _FakeDiscovery(discovered),
      );

      final source = await client.open('dQw4w9WgXcQ');
      expect(source, isNotNull);
      expect(authorization, isNull);
      await source!.disposeInitial();
    },
  );
}

class _FakeDiscovery extends ResolverDiscoveryService {
  _FakeDiscovery(this.endpoint);
  final Uri endpoint;

  @override
  Future<List<Uri>> discover({
    Duration timeout = const Duration(seconds: 3),
  }) async => [endpoint];
}
