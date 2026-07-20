import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ResolverHealth {
  const ResolverHealth({required this.ready, required this.dependencies});
  final bool ready;
  final Map<String, String> dependencies;
}

class ResolverClient {
  ResolverClient({Dio? dio, Future<String?> Function()? accessToken})
    : _dio = dio ?? Dio(),
      _accessToken = accessToken;

  final Dio _dio;
  final Future<String?> Function()? _accessToken;

  Future<ResolverHealth> check(Uri baseUrl) async {
    final response = await _dio.getUri<Map<String, dynamic>>(
      baseUrl.resolve('/health/ready'),
      options: Options(
        receiveTimeout: const Duration(seconds: 5),
        sendTimeout: const Duration(seconds: 5),
      ),
    );
    final data = response.data ?? const <String, dynamic>{};
    final rawDependencies = data['dependencies'];
    return ResolverHealth(
      ready: response.statusCode == 200 && data['status'] == 'ready',
      dependencies: rawDependencies is Map
          ? rawDependencies.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const {},
    );
  }

  Future<Options> authorizedOptions(
    Uri baseUrl, {
    Map<String, String>? headers,
  }) async {
    final token = baseUrl.scheme == 'https' || !kReleaseMode
        ? await _accessToken?.call()
        : null;
    return Options(
      headers: {
        ...?headers,
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );
  }
}
