import 'package:flutter/foundation.dart';

import '../../domain/repositories/settings_repository.dart';

enum ResolverEnvironment { debug, production }

class ResolverConfiguration {
  const ResolverConfiguration({
    required this.environment,
    required this.enabled,
    required this.baseUrl,
  });

  static const debugBuildDefault = String.fromEnvironment(
    'RESOLVER_DEBUG_BASE_URL',
    defaultValue: 'https://harmony-resolver.duckdns.org/resolver',
  );
  static const productionBuildDefault = String.fromEnvironment(
    'RESOLVER_PRODUCTION_BASE_URL',
    defaultValue: 'https://harmony-resolver.duckdns.org/resolver',
  );

  final ResolverEnvironment environment;
  final bool enabled;
  final Uri? baseUrl;

  bool get isProduction => environment == ResolverEnvironment.production;

  factory ResolverConfiguration.load(
    SettingsRepository settings, {
    bool releaseMode = kReleaseMode,
    Uri? discovered,
  }) {
    final environment = releaseMode
        ? ResolverEnvironment.production
        : ResolverEnvironment.debug;
    final override = releaseMode
        ? settings.getResolverProductionOverride()
        : settings.getResolverDebugOverride();
    final buildDefault = releaseMode
        ? productionBuildDefault
        : debugBuildDefault;
    final candidate = override?.trim().isNotEmpty == true
        ? override
        : discovered?.toString() ??
              (buildDefault.trim().isNotEmpty ? buildDefault : null);
    return ResolverConfiguration(
      environment: environment,
      enabled: settings.getResolverEnabled(),
      baseUrl: candidate == null
          ? null
          : normalize(candidate, production: releaseMode),
    );
  }

  static Uri normalize(String value, {required bool production}) {
    final parsed = Uri.parse(value.trim());
    if (!parsed.hasScheme || parsed.host.isEmpty) {
      throw const FormatException(
        'Resolver URL must include a scheme and host.',
      );
    }
    if (parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment ||
        (parsed.path.isNotEmpty &&
            parsed.path != '/' &&
            parsed.path != '/resolver')) {
      throw const FormatException(
        'Resolver URL cannot contain credentials, a path, query, or fragment.',
      );
    }
    if (production && parsed.scheme != 'https') {
      throw const FormatException('Production Resolver URL must use HTTPS.');
    }
    if (!production && parsed.scheme != 'http' && parsed.scheme != 'https') {
      throw const FormatException('Resolver URL must use HTTP or HTTPS.');
    }
    return parsed.replace(
      path: parsed.path == '/resolver' ? '/resolver/' : '',
      query: null,
      fragment: null,
    );
  }
}
