import 'dart:io';

import 'package:dio/dio.dart';

import 'cloud_sync_event.dart';

class HarmonyCloudClient {
  HarmonyCloudClient({
    Dio? dio,
    required Future<String?> Function() accessToken,
    this.baseUrl = 'https://harmony-resolver.duckdns.org/cloud/',
  }) : _dio = dio ?? Dio(),
       _accessToken = accessToken;

  final Dio _dio;
  final Future<String?> Function() _accessToken;
  final String baseUrl;

  Future<void> registerDevice(String deviceId, String name) async {
    await _dio.postUri<void>(
      Uri.parse(baseUrl).resolve('v1/devices/register'),
      data: {'deviceId': deviceId, 'name': name},
      options: await _options(),
    );
  }

  Future<Map<String, dynamic>> sync({
    required String deviceId,
    required int checkpoint,
    required List<CloudSyncEvent> events,
  }) async {
    final response = await _dio.postUri<Map<String, dynamic>>(
      Uri.parse(baseUrl).resolve('v1/sync'),
      data: {
        'deviceId': deviceId,
        'checkpoint': checkpoint,
        'events': events.map((event) => event.toJson()).toList(),
      },
      options: await _options(),
    );
    return response.data ?? const <String, dynamic>{};
  }

  Future<void> pause(String deviceId, bool paused) async {
    await _dio.postUri<void>(
      Uri.parse(baseUrl).resolve('v1/sync/pause'),
      data: {'deviceId': deviceId, 'paused': paused},
      options: await _options(),
    );
  }

  Future<void> deleteAccount() async {
    await _dio.deleteUri<void>(
      Uri.parse(baseUrl).resolve('v1/account'),
      options: await _options(),
    );
  }

  Future<Map<String, dynamic>> nextAudio({
    required String deviceId,
    required List<String> videoIds,
  }) async {
    final response = await _dio.postUri<Map<String, dynamic>>(
      Uri.parse(baseUrl).resolve('v1/audio/next'),
      data: {'deviceId': deviceId, 'videoIds': videoIds},
      options: await _options(),
    );
    return response.data ?? const <String, dynamic>{};
  }

  Future<void> uploadAudio({
    required String uploadUrl,
    required String uploadToken,
    required String filePath,
  }) async {
    await _dio.putUri<void>(
      Uri.parse(uploadUrl),
      data: File(filePath).openRead(),
      options: Options(
        headers: {
          'X-Upload-Token': uploadToken,
          Headers.contentTypeHeader: 'application/octet-stream',
        },
        sendTimeout: const Duration(minutes: 10),
        receiveTimeout: const Duration(minutes: 3),
      ),
    );
  }

  Future<Options> _options() async {
    final token = await _accessToken();
    return Options(
      headers: {
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    );
  }
}
