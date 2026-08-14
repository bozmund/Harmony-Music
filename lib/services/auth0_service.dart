import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/runtime_platform.dart';
import 'app_contracts.dart';
import 'cloud/harmony_cloud_client.dart';

/// Service that wraps Auth0 authentication for Harmony Music.
///
/// Platform-branched credential persistence:
/// - Android/iOS/macOS → auth0_flutter's built-in CredentialsManager.
/// - Windows          → flutter_secure_storage (SDK doesn't manage
///                      credentials on desktop).
class Auth0Service implements AuthServiceContract {
  // The Windows runner and installed protocol registration are compiled with
  // this callback. Unlike mobile, Windows cannot discover a custom scheme
  // dynamically from the bundled .env file before protocol activation.
  static String get _windowsCallbackScheme =>
      kDebugMode ? 'harmonymusic-dev' : 'harmonymusic';
  static const _accountSelectionLoginParameters = <String, String>{
    // Force Auth0 to authenticate again instead of silently reusing its SSO
    // session. The Google connection has a static upstream
    // prompt=select_account setting, so reaching Google opens its account
    // chooser while this value remains scoped to Auth0 reauthentication.
    'prompt': 'login',
  };

  Auth0Service._(
    this._auth0,
    this._domain,
    this._clientId,
    this._scheme,
    this._audience,
    this._storage,
    this.isConfigured, {
    Dio? refreshClient,
  }) : _refreshClient = refreshClient ?? Dio();

  /// Builds a service around a caller-supplied credential store and HTTP client.
  ///
  /// Exists so the Windows session rules — an offline launch keeps you signed
  /// in, a rejected grant does not — can be asserted against real code rather
  /// than a source-text guard. Those two outcomes are indistinguishable from
  /// outside the class, and getting them the wrong way round signs every
  /// Windows user out the first time they open the app without a connection.
  @visibleForTesting
  factory Auth0Service.forTesting({
    required FlutterSecureStorage storage,
    required Dio refreshClient,
    String domain = 'test.auth0.test',
    String clientId = 'test-client',
    String scheme = 'harmonymusic',
    String audience = 'https://resolver.test',
  }) => Auth0Service._(
    Auth0(domain, clientId),
    domain,
    clientId,
    scheme,
    audience,
    storage,
    true,
    refreshClient: refreshClient,
  );

  late final Auth0 _auth0;
  late final String _domain;
  late final String _clientId;
  late final String _scheme;
  late final String _audience;
  late final FlutterSecureStorage _storage;
  final Dio _refreshClient;
  Future<String?>? _windowsRefreshInFlight;

  final _sessionRevoked = StreamController<void>.broadcast();

  /// Set by [_markWindowsSessionRevoked] so [_restoreWindowsSession] can tell a
  /// grant Auth0 actually rejected from a token we merely failed to reach the
  /// network to mint. Both come back from [_windowsAccessToken] as a bare null,
  /// and treating them alike would sign the user out on every offline launch.
  bool _windowsSessionRevoked = false;

  final bool isConfigured;

  /// Fires when a stored session stops being usable while the app is running —
  /// a refresh token Auth0 rejected, not a network failure.
  ///
  /// Windows only for now. The mobile path routes through `CredentialsManager`,
  /// whose failures arrive as a single opaque exception that cannot distinguish
  /// a revoked grant from a dead connection; guessing there would sign phone
  /// users out whenever they walked into a tunnel. Mobile keeps surfacing a
  /// lapsed session on the next launch, which it already does correctly.
  @override
  Stream<void> get onSessionRevoked => _sessionRevoked.stream;

  Future<void> dispose() => _sessionRevoked.close();

  bool get isSupportedPlatform =>
      RuntimePlatform.isAndroid ||
      RuntimePlatform.isIOS ||
      RuntimePlatform.isMacOS ||
      RuntimePlatform.isWindows;

  bool get isAvailable => isConfigured && isSupportedPlatform;

  String get _callbackScheme =>
      RuntimePlatform.isWindows ? _windowsCallbackScheme : _scheme;

  /// Where Auth0 sends the browser after a Windows sign-in, instead of straight
  /// at `harmonymusic://callback`.
  ///
  /// The custom scheme still does the actual handoff — this page performs it —
  /// but redirecting through a real page means the tab ends on "you can close
  /// this tab" rather than sitting on the Auth0 login form forever. Nothing can
  /// close it for the user: a tab only auto-closes when it never committed a
  /// page (which is why the *logout* tab vanishes), and `window.close()` does
  /// nothing in a tab the user did not script-open.
  ///
  /// The scheme rides as a path segment rather than a query parameter: Auth0
  /// matches `redirect_uri` against Allowed Callback URLs exactly, so a query
  /// string would have to be registered verbatim. Debug and release therefore
  /// have one registered URL each, and both must be listed alongside the custom
  /// schemes, which the plugin still validates `appCustomURL` against.
  String get _windowsRedirectUrl =>
      '${HarmonyCloudClient.defaultBaseUrl.replaceAll(RegExp(r'/+$'), '')}'
      '/auth/windows/callback/$_windowsCallbackScheme';

  /// Use [domain] from `.env` or a fallback so the app doesn't crash
  /// when `.env` is missing; the service will simply remain
  /// unauthenticated.
  static Auth0Service create() {
    final domain = dotenv.get('AUTH0_DOMAIN', fallback: '');
    final clientId = dotenv.get('AUTH0_CLIENT_ID', fallback: '');
    final scheme = dotenv.get(
      'AUTH0_REDIRECT_SCHEME',
      fallback: 'harmonymusic',
    );
    final audience = dotenv.get('AUTH0_AUDIENCE', fallback: '');
    return Auth0Service._(
      Auth0(domain, clientId),
      domain,
      clientId,
      scheme,
      audience,
      const FlutterSecureStorage(),
      domain.isNotEmpty && clientId.isNotEmpty,
    );
  }

  /// Try to restore a previously-authenticated session from the
  /// platform-specific credential store.
  ///
  /// Returns `null` when no session exists.
  Future<UserProfile?> tryRestoreSession() async {
    if (!isAvailable) return null;
    if (RuntimePlatform.isWindows) {
      return _restoreWindowsSession();
    }
    // Android / iOS / macOS — use built-in CredentialsManager.
    try {
      final credentials = await _auth0.credentialsManager.credentials();
      return credentials.user;
    } catch (error) {
      _logSessionRestoreFailure(error);
      return null;
    }
  }

  /// Open Auth0 Universal Login (hosted page — handles both login & register).
  ///
  /// Returns the authenticated user profile, or throws on failure.
  Future<UserProfile> login({bool chooseAccount = false}) async {
    if (!isSupportedPlatform) {
      throw UnsupportedError('Auth0 login is not supported on this platform.');
    }
    if (!isConfigured) {
      throw StateError(
        'Auth0 is not configured. Add AUTH0_DOMAIN and AUTH0_CLIENT_ID to .env.',
      );
    }
    const scopes = {'openid', 'profile', 'email', 'offline_access'};
    final parameters = chooseAccount
        ? _accountSelectionLoginParameters
        : const <String, String>{};
    final credentials = RuntimePlatform.isWindows
        ? await _auth0.windowsWebAuthentication().login(
            appCustomURL: '$_callbackScheme://callback',
            redirectUrl: _windowsRedirectUrl,
            audience: _audience.isEmpty ? null : _audience,
            scopes: scopes,
            parameters: parameters,
          )
        : await _auth0
              .webAuthentication(scheme: _scheme)
              .login(
                audience: _audience.isEmpty ? null : _audience,
                scopes: scopes,
                parameters: parameters,
              );
    await _persistCredentials(credentials);
    return credentials.user;
  }

  /// Log the user out and clear the stored session.
  Future<void> logout() async {
    if (!isAvailable) return;
    try {
      if (RuntimePlatform.isWindows) {
        await _auth0.windowsWebAuthentication().logout(
          appCustomURL: '$_callbackScheme://callback',
        );
      } else {
        await _auth0.webAuthentication(scheme: _scheme).logout();
      }
    } catch (_) {
      // Logout can fail if the browser session is already gone; that's OK.
    }
    await _clearPersistedCredentials();
  }

  /// The underlying Auth0 client (for advanced use).
  Auth0 get auth0 => _auth0;

  /// Returns a refreshed Resolver API access token when a session exists.
  /// Missing sessions remain anonymous; token values must never be logged.
  Future<String?> accessToken({bool forceRefresh = false}) async {
    if (!isAvailable || _audience.isEmpty) return null;
    try {
      if (RuntimePlatform.isWindows) {
        return _windowsAccessToken(forceRefresh: forceRefresh);
      }
      final credentials = await _auth0.credentialsManager.credentials(
        // A debug-triggered refresh deliberately exceeds any normal access
        // token lifetime, making CredentialsManager use its refresh token.
        minTtl: forceRefresh ? 365 * 24 * 60 * 60 : 60,
        parameters: {'audience': _audience},
      );
      return credentials.accessToken;
    } catch (_) {
      return null;
    }
  }

  void _logSessionRestoreFailure(Object error) {
    if (!kDebugMode) return;
    // Deliberately log only the exception type. Auth SDK exception messages
    // can contain request details and must never expose tokens or user data.
    developer.log(
      'Auth0 session restoration failed (${error.runtimeType}).',
      name: 'harmony.auth',
    );
  }

  // ---------------------------------------------------------------------------
  // Persistence helpers
  // ---------------------------------------------------------------------------

  Future<void> _persistCredentials(Credentials credentials) async {
    final userJson = credentials.user.toJson();
    if (RuntimePlatform.isWindows) {
      await _storage.write(
        key: 'auth0_credentials',
        value: jsonEncode({
          'accessToken': credentials.accessToken,
          'idToken': credentials.idToken,
          'refreshToken': credentials.refreshToken,
          'expiresAt': credentials.expiresAt.toUtc().toIso8601String(),
          'user': userJson,
        }),
      );
    } else {
      // Android/iOS/macOS — CredentialsManager already saved it automatically.
      // We still save explicitly to be safe.
      try {
        await _auth0.credentialsManager.storeCredentials(credentials);
      } catch (_) {
        // Ignore; the SDK may have already saved it.
      }
    }
  }

  /// Windows keeps its own credentials, so restoring one has to prove the token
  /// still works. Reading the cached profile alone — which is all this used to
  /// do — meant a device whose refresh token died months ago still launched
  /// looking signed in, while every cloud call quietly 401'd behind it. Mobile
  /// never had the problem: `CredentialsManager.credentials()` throws on a dead
  /// grant, which is exactly the signal this reconstructs.
  Future<UserProfile?> _restoreWindowsSession() async {
    final profile = await _restoreFromSecureStorage();
    if (profile == null) return null;
    // With no audience configured there is no Resolver token to mint, so
    // `accessToken` returns null for every caller. That is a missing setting,
    // not an expired session, and must not read as one.
    if (_audience.isEmpty) return profile;

    _windowsSessionRevoked = false;
    String? token;
    try {
      token = await _windowsAccessToken(forceRefresh: false);
    } catch (error) {
      // Anything the refresh did not anticipate (a malformed stored blob, a
      // socket teardown) is not evidence the grant is gone. Keep the session
      // and let the next attempt decide.
      _logSessionRestoreFailure(error);
      return profile;
    }
    if (token != null) return profile;
    // Only a grant Auth0 rejected ends the session. A network failure leaves
    // the stored credentials alone and the user signed in, so the next launch
    // with a connection can recover on its own.
    return _windowsSessionRevoked ? null : profile;
  }

  /// The stored session is unusable and has been cleared. Records it for an
  /// in-progress restore and tells anyone watching, so a session that dies
  /// mid-run surfaces immediately instead of at the next launch.
  void _markWindowsSessionRevoked() {
    _windowsSessionRevoked = true;
    if (!_sessionRevoked.isClosed) _sessionRevoked.add(null);
  }

  Future<UserProfile?> _restoreFromSecureStorage() async {
    try {
      final raw = await _storage.read(key: 'auth0_credentials');
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return UserProfile.fromMap(map['user'] as Map<String, dynamic>);
    } catch (error) {
      _logSessionRestoreFailure(error);
      return null;
    }
  }

  Future<String?> _windowsAccessToken({required bool forceRefresh}) async {
    final raw = await _storage.read(key: 'auth0_credentials');
    if (raw == null) return null;
    final credentials = jsonDecode(raw) as Map<String, dynamic>;
    final accessToken = credentials['accessToken'] as String?;
    final expiresAt = DateTime.tryParse(
      credentials['expiresAt']?.toString() ?? '',
    )?.toUtc();
    final needsRefresh =
        forceRefresh ||
        expiresAt == null ||
        !expiresAt.isAfter(
          DateTime.now().toUtc().add(const Duration(minutes: 1)),
        );
    if (!needsRefresh) return accessToken;

    final refreshToken = credentials['refreshToken'] as String?;
    if (refreshToken == null || refreshToken.isEmpty) {
      // An expired access token with nothing to renew it is as dead as a
      // rejected grant — there is no request that could ever recover it.
      _markWindowsSessionRevoked();
      await _clearPersistedCredentials();
      return null;
    }
    return _windowsRefreshInFlight ??= _refreshWindowsCredentials(
      credentials,
      refreshToken,
    ).whenComplete(() => _windowsRefreshInFlight = null);
  }

  Future<String?> _refreshWindowsCredentials(
    Map<String, dynamic> credentials,
    String refreshToken,
  ) async {
    try {
      final response = await _refreshClient.postUri<Map<String, dynamic>>(
        Uri.https(_domain, '/oauth/token'),
        data: {
          'grant_type': 'refresh_token',
          'client_id': _clientId,
          'refresh_token': refreshToken,
          // Without this the refresh grant mints a token for Auth0's *default*
          // audience instead of the Resolver API, and Harmony Cloud answers 401
          // to every call made with it — socket upgrade, session read, command
          // drain, state publish. It never recovers on its own either: each
          // retry refreshes and gets another audience-less token, so a Windows
          // device silently drops out of cross-device playback the first time
          // its login token expires. Login and the mobile path have always sent
          // the audience; only this one leg forgot.
          if (_audience.isNotEmpty) 'audience': _audience,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final data = response.data;
      final accessToken = data?['access_token'] as String?;
      final expiresIn = (data?['expires_in'] as num?)?.toInt();
      if (accessToken == null || accessToken.isEmpty || expiresIn == null) {
        return null;
      }
      credentials['accessToken'] = accessToken;
      credentials['refreshToken'] = data?['refresh_token'] ?? refreshToken;
      credentials['expiresAt'] = DateTime.now()
          .toUtc()
          .add(Duration(seconds: expiresIn))
          .toIso8601String();
      await _storage.write(
        key: 'auth0_credentials',
        value: jsonEncode(credentials),
      );
      return accessToken;
    } on DioException catch (error) {
      // An invalid or revoked refresh token cannot recover silently. Network
      // failures keep the stored session intact so a later retry can succeed.
      if (error.response?.statusCode == 400 ||
          error.response?.statusCode == 401) {
        _markWindowsSessionRevoked();
        await _clearPersistedCredentials();
      }
      return null;
    }
  }

  Future<void> _clearPersistedCredentials() async {
    if (RuntimePlatform.isWindows) {
      await _storage.delete(key: 'auth0_credentials');
    } else {
      try {
        await _auth0.credentialsManager.clearCredentials();
      } catch (_) {
        // Ignore.
      }
    }
  }
}

// ---------------------------------------------------------------------------
// UserProfile serialization helpers (auth0_flutter v2 UserProfile can be
// serialized via toJson / fromJson).
// ---------------------------------------------------------------------------

extension _UserProfileJson on UserProfile {
  Map<String, dynamic> toJson() => {
    'sub': sub,
    'name': name,
    'given_name': givenName,
    'family_name': familyName,
    'middle_name': middleName,
    'nickname': nickname,
    'preferred_username': preferredUsername,
    'profile': profileUrl?.toString(),
    'picture': pictureUrl?.toString(),
    'website': websiteUrl?.toString(),
    'email': email,
    'email_verified': isEmailVerified,
    'gender': gender,
    'birthdate': birthdate,
    'zoneinfo': zoneinfo,
    'locale': locale,
    'phone_number': phoneNumber,
    'phone_number_verified': isPhoneNumberVerified,
    'updated_at': updatedAt?.toIso8601String(),
    'address': address,
    'custom_claims': customClaims,
  };
}
