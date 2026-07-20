import 'dart:async';
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
  late List<ResolverPlaybackClient> clients;
  final fixture = Uint8List.fromList('OggSvalid-opus-fixture'.codeUnits);

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('resolver_playback_test_');
    Hive.init(hiveDir.path);
    await Hive.openBox(BoxNames.appPrefs);
    settings = HiveSettingsRepository();
    clients = <ResolverPlaybackClient>[];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    await settings.setResolverDebugOverride(
      'http://${server.address.address}:${server.port}',
    );
  });

  tearDown(() async {
    for (final client in clients) {
      client.dispose();
    }
    await server.close(force: true);
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  test('uses the accepted Resolver connection pool bounds', () {
    expect(ResolverPlaybackClient.maxConnectionsPerAuthority, 4);
    expect(
      ResolverPlaybackClient.idleConnectionTimeout,
      const Duration(minutes: 5),
    );
    expect(
      ResolverPlaybackClient.defaultConnectionTimeout,
      const Duration(seconds: 5),
    );
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
      clients.add(client);
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
    clients.add(client);
    expect(await client.open('dQw4w9WgXcQ'), isNull);
  });

  test('retries public playback anonymously after token rejection', () async {
    final authorizationHeaders = <String?>[];
    server.listen((request) async {
      final authorization = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      authorizationHeaders.add(authorization);
      if (authorization != null) {
        request.response.statusCode = HttpStatus.unauthorized;
      } else {
        request.response.headers.contentType = ContentType('audio', 'ogg');
        request.response.add(fixture);
      }
      await request.response.close();
    });
    final client = ResolverPlaybackClient(
      settings: settings,
      accessToken: () async => 'stale-token',
    );
    clients.add(client);

    final source = await client.open('dQw4w9WgXcQ');

    expect(source, isNotNull);
    expect(authorizationHeaders, ['Bearer stale-token', null]);
    await source!.disposeInitial();
  });

  test('retries public prefetch anonymously after token rejection', () async {
    final authorizationHeaders = <String?>[];
    server.listen((request) async {
      final authorization = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      authorizationHeaders.add(authorization);
      await request.drain<void>();
      request.response.statusCode = authorization == null
          ? HttpStatus.accepted
          : HttpStatus.unauthorized;
      await request.response.close();
    });
    final client = ResolverPlaybackClient(
      settings: settings,
      accessToken: () async => 'stale-token',
    );
    clients.add(client);

    await client.prefetch(['dQw4w9WgXcQ']);

    expect(authorizationHeaders, ['Bearer stale-token', null]);
  });

  test(
    'shares connections across warm-up, retries, playback, and ranges',
    () async {
      final remotePorts = <int>[];
      final authorizationHeaders = <String?>[];
      var healthRequests = 0;
      server.listen((request) async {
        remotePorts.add(request.connectionInfo!.remotePort);
        if (request.uri.path.endsWith('/health/live')) {
          healthRequests++;
          await Future<void>.delayed(const Duration(milliseconds: 40));
          request.response
            ..statusCode = HttpStatus.ok
            ..contentLength = 0;
          await request.response.close();
          return;
        }

        final authorization = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        authorizationHeaders.add(authorization);
        if (request.method == 'POST') {
          await request.drain<void>();
          request.response
            ..statusCode = authorization == null
                ? HttpStatus.accepted
                : HttpStatus.unauthorized
            ..contentLength = 0;
          await request.response.close();
          return;
        }
        if (authorization != null) {
          request.response
            ..statusCode = HttpStatus.unauthorized
            ..contentLength = 0;
          await request.response.close();
          return;
        }

        final range = request.headers.value(HttpHeaders.rangeHeader);
        request.response.headers
          ..contentType = ContentType('audio', 'ogg')
          ..set(HttpHeaders.etagHeader, '"shared-v1"');
        if (range == null) {
          request.response
            ..statusCode = HttpStatus.ok
            ..contentLength = fixture.length
            ..add(fixture);
        } else {
          request.response
            ..statusCode = HttpStatus.partialContent
            ..contentLength = 4
            ..headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes 4-7/${fixture.length}',
            )
            ..add(fixture.sublist(4, 8));
        }
        await request.response.close();
      });
      final client = ResolverPlaybackClient(
        settings: settings,
        accessToken: () async => 'stale-token',
      );
      clients.add(client);

      await Future.wait([client.warmUp(), client.warmUp()]);
      await client.prefetch(['dQw4w9WgXcQ']);
      final source = await client.open('dQw4w9WgXcQ');
      expect(source, isNotNull);
      final initial = await source!.request();
      expect(await initial.stream.expand((chunk) => chunk).toList(), fixture);
      final range = await source.request(4, 8);
      expect(
        await range.stream.expand((chunk) => chunk).toList(),
        fixture.sublist(4, 8),
      );

      expect(healthRequests, 1);
      expect(
        authorizationHeaders,
        containsAllInOrder([
          'Bearer stale-token',
          null,
          'Bearer stale-token',
          null,
          null,
        ]),
      );
      expect(remotePorts.toSet(), hasLength(1));

      final requestCountBeforeDisposal = remotePorts.length;
      client.dispose();
      await client.warmUp();
      await client.prefetch(['dQw4w9WgXcQ']);
      expect(await client.open('dQw4w9WgXcQ'), isNull);
      expect(remotePorts, hasLength(requestCountBeforeDisposal));
      await expectLater(source.request(8, 12), throwsA(anything));
    },
  );

  test('cancellation aborts a blocked response without closing pool', () async {
    final requestSeen = Completer<void>();
    var requestCount = 0;
    server.listen((request) async {
      requestCount++;
      if (requestCount == 1) {
        if (!requestSeen.isCompleted) requestSeen.complete();
        // Leave response headers blocked. Cancelling must abort this request.
        return;
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('audio', 'ogg')
        ..contentLength = fixture.length
        ..add(fixture);
      await request.response.close();
    });
    final client = ResolverPlaybackClient(
      settings: settings,
      accessToken: () async => null,
    );
    clients.add(client);
    final cancellation = ResolverOpenCancellation();
    final stopwatch = Stopwatch()..start();
    final resultFuture = client.open('dQw4w9WgXcQ', cancellation: cancellation);

    await requestSeen.future.timeout(const Duration(seconds: 1));
    cancellation.cancel();

    expect(await resultFuture.timeout(const Duration(seconds: 1)), isNull);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    final source = await client.open('dQw4w9WgXcQ');
    expect(source, isNotNull);
    await source!.disposeInitial();
    expect(requestCount, 2);
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
      clients.add(client);

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
