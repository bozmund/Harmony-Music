import 'dart:convert';

import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/runtime_platform.dart';

/// Service that wraps Auth0 authentication for Harmony Music.
///
/// Platform-branched credential persistence:
/// - Android/iOS/macOS → auth0_flutter's built-in CredentialsManager.
/// - Windows          → flutter_secure_storage (SDK doesn't manage
///                      credentials on desktop).
class Auth0Service {
  Auth0Service._(
    this._auth0,
    this._scheme,
    this._audience,
    this._storage,
    this.isConfigured,
  );

  late final Auth0 _auth0;
  late final String _scheme;
  late final String _audience;
  late final FlutterSecureStorage _storage;

  final bool isConfigured;

  bool get isSupportedPlatform =>
      RuntimePlatform.isAndroid ||
      RuntimePlatform.isIOS ||
      RuntimePlatform.isMacOS;

  bool get isAvailable => isConfigured && isSupportedPlatform;

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
      return _restoreFromSecureStorage();
    }
    // Android / iOS / macOS — use built-in CredentialsManager.
    try {
      final credentials = await _auth0.credentialsManager.credentials();
      return credentials.user;
    } catch (_) {
      return null;
    }
  }

  /// Open Auth0 Universal Login (hosted page — handles both login & register).
  ///
  /// Returns the authenticated user profile, or throws on failure.
  Future<UserProfile> login() async {
    if (!isSupportedPlatform) {
      throw UnsupportedError('Auth0 login is not supported on this platform.');
    }
    if (!isConfigured) {
      throw StateError(
        'Auth0 is not configured. Add AUTH0_DOMAIN and AUTH0_CLIENT_ID to .env.',
      );
    }
    final credentials = RuntimePlatform.isWindows
        ? await _auth0.windowsWebAuthentication().login(
            appCustomURL: '$_scheme://callback',
            audience: _audience.isEmpty ? null : _audience,
          )
        : await _auth0
              .webAuthentication(scheme: _scheme)
              .login(audience: _audience.isEmpty ? null : _audience);
    await _persistCredentials(credentials);
    return credentials.user;
  }

  /// Log the user out and clear the stored session.
  Future<void> logout() async {
    if (!isAvailable) return;
    try {
      if (RuntimePlatform.isWindows) {
        await _auth0.windowsWebAuthentication().logout(
          appCustomURL: '$_scheme://callback',
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
  Future<String?> accessToken() async {
    if (!isAvailable || _audience.isEmpty) return null;
    try {
      if (RuntimePlatform.isWindows) {
        final raw = await _storage.read(key: 'auth0_credentials');
        if (raw == null) return null;
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return map['accessToken'] as String?;
      }
      final credentials = await _auth0.credentialsManager.credentials(
        minTtl: 60,
        parameters: {'audience': _audience},
      );
      return credentials.accessToken;
    } catch (_) {
      return null;
    }
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

  Future<UserProfile?> _restoreFromSecureStorage() async {
    try {
      final raw = await _storage.read(key: 'auth0_credentials');
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return UserProfile.fromMap(map['user'] as Map<String, dynamic>);
    } catch (_) {
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
