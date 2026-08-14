import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/auth0_service.dart';
import 'package:harmonymusic/utils/runtime_platform.dart';

/// Windows keeps its own credentials in secure storage instead of the Auth0
/// SDK's credential manager, so restoring a session there is code we wrote and
/// has to be checked ourselves.
///
/// It used to read the cached profile and stop, which meant a device whose
/// refresh token had been revoked months earlier still launched looking fully
/// signed in while every cloud call quietly 401'd behind it — the visible bug.
/// The fix has an equal and opposite failure mode: treat "I could not mint a
/// token" as "the session is over" and every offline launch signs the user out.
/// These pin both ends.
void main() {
  const key = 'auth0_credentials';

  String storedCredentials({
    required Duration expiresIn,
    String? refreshToken = 'refresh-token',
  }) => jsonEncode({
    'accessToken': 'stored-access-token',
    'idToken': 'stored-id-token',
    'refreshToken': refreshToken,
    'expiresAt': DateTime.now().toUtc().add(expiresIn).toIso8601String(),
    'user': {'sub': 'auth0|user-1', 'email': 'user-1@example.test'},
  });

  Auth0Service serviceWith(
    _FakeSecureStorage storage, {
    required Dio refreshClient,
    String audience = 'https://resolver.test',
  }) => Auth0Service.forTesting(
    storage: storage,
    refreshClient: refreshClient,
    audience: audience,
  );

  group('windows session restore', () {
    test('a still-valid stored token restores without any network call', () async {
      final storage = _FakeSecureStorage({
        key: storedCredentials(expiresIn: const Duration(hours: 1)),
      });
      final client = _StubDio();

      final profile = await serviceWith(
        storage,
        refreshClient: client.dio,
      ).tryRestoreSession();

      expect(profile?.sub, 'auth0|user-1');
      expect(
        client.requestCount,
        0,
        reason: 'a token that has not expired needs nothing from Auth0',
      );
    });

    test('a rejected refresh grant ends the session', () async {
      final storage = _FakeSecureStorage({
        key: storedCredentials(expiresIn: const Duration(seconds: -1)),
      });
      // 403 `invalid_grant` is what Auth0 answers for a revoked or rotated-away
      // refresh token; it arrives as a 400 on the token endpoint.
      final client = _StubDio(failure: _Failure.rejectedGrant);

      final profile = await serviceWith(
        storage,
        refreshClient: client.dio,
      ).tryRestoreSession();

      expect(profile, isNull);
      expect(
        storage.store.containsKey(key),
        isFalse,
        reason: 'a dead grant must not be left behind to be retried forever',
      );
    });

    test('a 401 from the token endpoint also ends the session', () async {
      final storage = _FakeSecureStorage({
        key: storedCredentials(expiresIn: const Duration(seconds: -1)),
      });
      final client = _StubDio(failure: _Failure.unauthorized);

      final profile = await serviceWith(
        storage,
        refreshClient: client.dio,
      ).tryRestoreSession();

      expect(profile, isNull);
    });

    test('an offline launch keeps the user signed in', () async {
      final storage = _FakeSecureStorage({
        key: storedCredentials(expiresIn: const Duration(seconds: -1)),
      });
      // No response at all — the shape of every "no network" failure.
      final client = _StubDio(failure: _Failure.offline);

      final profile = await serviceWith(
        storage,
        refreshClient: client.dio,
      ).tryRestoreSession();

      expect(
        profile?.sub,
        'auth0|user-1',
        reason: 'an unreachable Auth0 is not evidence the grant was revoked',
      );
      expect(
        storage.store.containsKey(key),
        isTrue,
        reason: 'the credentials must survive so a later launch can recover',
      );
    });

    test('an expired token with nothing to renew it ends the session', () async {
      final storage = _FakeSecureStorage({
        key: storedCredentials(
          expiresIn: const Duration(seconds: -1),
          refreshToken: null,
        ),
      });
      final client = _StubDio();

      final profile = await serviceWith(
        storage,
        refreshClient: client.dio,
      ).tryRestoreSession();

      expect(
        profile,
        isNull,
        reason: 'no request could ever recover it, so it is as dead as a '
            'rejected grant',
      );
      expect(client.requestCount, 0);
    });

    test('a successful refresh restores and stores the new token', () async {
      final storage = _FakeSecureStorage({
        key: storedCredentials(expiresIn: const Duration(seconds: -1)),
      });
      final client = _StubDio(
        response: {
          'access_token': 'fresh-access-token',
          'expires_in': 3600,
          'refresh_token': 'rotated-refresh-token',
        },
      );

      final profile = await serviceWith(
        storage,
        refreshClient: client.dio,
      ).tryRestoreSession();

      expect(profile?.sub, 'auth0|user-1');
      final stored = jsonDecode(storage.store[key]!) as Map<String, dynamic>;
      expect(stored['accessToken'], 'fresh-access-token');
      expect(stored['refreshToken'], 'rotated-refresh-token');
    });

    test('an unconfigured audience is not mistaken for an expired session', () async {
      final storage = _FakeSecureStorage({
        key: storedCredentials(expiresIn: const Duration(seconds: -1)),
      });
      final client = _StubDio(failure: _Failure.rejectedGrant);

      // With no audience there is no Resolver token to mint for anybody, so
      // `accessToken` returns null unconditionally. That is a missing setting,
      // not a session that ended.
      final profile = await serviceWith(
        storage,
        refreshClient: client.dio,
        audience: '',
      ).tryRestoreSession();

      expect(profile?.sub, 'auth0|user-1');
      expect(client.requestCount, 0);
    });

    test('no stored credentials restores nothing', () async {
      final profile = await serviceWith(
        _FakeSecureStorage({}),
        refreshClient: _StubDio().dio,
      ).tryRestoreSession();

      expect(profile, isNull);
    });

    test('a revoked grant is announced without waiting for a relaunch', () async {
      final storage = _FakeSecureStorage({
        key: storedCredentials(expiresIn: const Duration(seconds: -1)),
      });
      final service = serviceWith(
        storage,
        refreshClient: _StubDio(failure: _Failure.rejectedGrant).dio,
      );
      final revocations = <void>[];
      final subscription = service.onSessionRevoked.listen(revocations.add);
      addTearDown(subscription.cancel);

      await service.accessToken();
      await Future<void>.delayed(Duration.zero);

      expect(
        revocations, hasLength(1),
        reason: 'the UI stays on a signed-in account until it is told '
            'otherwise, however many calls are quietly 401ing behind it',
      );
    });

    test('a network failure is never announced as a revocation', () async {
      final storage = _FakeSecureStorage({
        key: storedCredentials(expiresIn: const Duration(seconds: -1)),
      });
      final service = serviceWith(
        storage,
        refreshClient: _StubDio(failure: _Failure.offline).dio,
      );
      final revocations = <void>[];
      final subscription = service.onSessionRevoked.listen(revocations.add);
      addTearDown(subscription.cancel);

      await service.accessToken();
      await Future<void>.delayed(Duration.zero);

      expect(revocations, isEmpty);
    });
  },
      // Every assertion here runs through `RuntimePlatform.isWindows` branches
      // in the service, which are inert on any other host.
      skip: RuntimePlatform.isWindows
          ? null
          : 'Windows-only credential handling');
}

/// A `Dio` whose HTTP layer never leaves the process, following the same
/// adapter-substitution idiom as `fakeCloudDio()` in the integration fakes.
///
/// Going through the real Dio pipeline rather than stubbing `postUri` matters
/// here: the code under test branches on `DioException.response?.statusCode`,
/// and it is Dio itself that decides which failures carry a response at all.
class _StubDio {
  _StubDio({Map<String, dynamic>? response, _Failure? failure}) {
    dio = Dio()
      ..httpClientAdapter = _StubAdapter(
        response: response,
        failure: failure,
        onRequest: () => requestCount++,
      );
  }

  late final Dio dio;
  int requestCount = 0;
}

enum _Failure { rejectedGrant, unauthorized, offline }

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({this.response, this.failure, required this.onRequest});

  final Map<String, dynamic>? response;
  final _Failure? failure;
  final void Function() onRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    onRequest();
    if (failure == _Failure.offline) {
      // No response at all — the shape of every "no network" failure.
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Failed host lookup',
      );
    }
    final status = switch (failure) {
      // 400 `invalid_grant` is what Auth0 answers for a revoked or
      // rotated-away refresh token.
      _Failure.rejectedGrant => 400,
      _Failure.unauthorized => 401,
      _ => 200,
    };
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode(response ?? const <String, dynamic>{})),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage(Map<String, String> initial) : store = {...initial};

  final Map<String, String> store;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    store.remove(key);
  }
}
