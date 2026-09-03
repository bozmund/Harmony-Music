import 'package:dio/dio.dart';

import 'cloud_sync_event.dart';

class CloudPlaybackDevice {
  const CloudPlaybackDevice({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.presence,
    required this.isCurrentDevice,
    required this.isAudioTarget,
  });

  final String deviceId;
  final String name;
  final String platform;
  final String presence;
  final bool isCurrentDevice;
  final bool isAudioTarget;

  factory CloudPlaybackDevice.fromJson(Map<String, dynamic> json) =>
      CloudPlaybackDevice(
        deviceId: json['deviceId'].toString(),
        name: json['name']?.toString() ?? 'Harmony device',
        platform: json['platform']?.toString() ?? 'unknown',
        presence: json['presence']?.toString() ?? 'unavailable',
        isCurrentDevice: json['isCurrentDevice'] == true,
        isAudioTarget: json['isAudioTarget'] == true,
      );
}

class CloudPlaybackCommand {
  const CloudPlaybackCommand({
    required this.commandId,
    required this.type,
    required this.payload,
  });

  final String commandId;
  final String type;
  final Map<String, dynamic> payload;

  factory CloudPlaybackCommand.fromJson(Map<String, dynamic> json) =>
      CloudPlaybackCommand(
        commandId: json['commandId'].toString(),
        type: json['type'].toString(),
        payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
      );
}

class CloudPlaybackSession {
  const CloudPlaybackSession({
    required this.sessionId,
    required this.targetDeviceId,
    required this.sequence,
    required this.state,
    this.currentSongId,
    this.positionMs = 0,
    this.durationMs,
    this.playing = false,
  });

  final String sessionId;
  final String targetDeviceId;
  final int sequence;

  /// Durable v2 state: ordered `queueIds`, `index` and modes.
  final Map<String, dynamic> state;

  /// Last progress the target persisted. Live progress arrives over the socket;
  /// these fields exist so a device opening mid-session does not start at zero.
  final String? currentSongId;
  final int positionMs;
  final int? durationMs;
  final bool playing;

  factory CloudPlaybackSession.fromJson(Map<String, dynamic> json) =>
      CloudPlaybackSession(
        sessionId: json['sessionId'].toString(),
        targetDeviceId: json['targetDeviceId'].toString(),
        sequence: (json['sequence'] as num?)?.toInt() ?? 0,
        state: Map<String, dynamic>.from(json['state'] as Map? ?? const {}),
        currentSongId: json['currentSongId']?.toString(),
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt(),
        playing: json['playing'] == true,
      );
}

class HarmonyCloudClient {
  HarmonyCloudClient({
    Dio? dio,
    required Future<String?> Function() accessToken,
    this.baseUrl = defaultBaseUrl,
  }) : _dio = dio ?? Dio(),
       _accessToken = accessToken;

  static const defaultBaseUrl = 'https://harmony-resolver.duckdns.org/cloud/';

  final Dio _dio;
  final Future<String?> Function() _accessToken;
  final String baseUrl;

  Future<void> registerDevice({
    required String deviceId,
    required String name,
    required String platform,
    required String appVersion,
  }) async {
    await _dio.postUri<void>(
      Uri.parse(baseUrl).resolve('v1/devices/register'),
      data: {
        'deviceId': deviceId,
        'name': name,
        'platform': platform,
        'appVersion': appVersion,
      },
      options: await _options(),
    );
  }

  Future<List<CloudPlaybackDevice>> playbackDevices(
    String currentDeviceId,
  ) async {
    final response = await _dio.getUri<List<dynamic>>(
      Uri.parse(
        baseUrl,
      ).resolve('v1/playback/devices?currentDeviceId=$currentDeviceId'),
      options: await _options(),
    );
    return (response.data ?? const <dynamic>[])
        .whereType<Map>()
        .map(
          (item) =>
              CloudPlaybackDevice.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<void> removePlaybackDevice(String deviceId) async {
    await _dio.deleteUri<void>(
      Uri.parse(baseUrl).resolve('v1/devices/${Uri.encodeComponent(deviceId)}'),
      options: await _options(),
    );
  }

  Future<void> updatePlaybackPresence(String deviceId) async {
    await _dio.postUri<void>(
      Uri.parse(baseUrl).resolve('v1/playback/presence'),
      data: {'deviceId': deviceId},
      options: await _options(),
    );
  }

  Future<bool> submitPlaybackCommand({
    required String sourceDeviceId,
    required String targetDeviceId,
    required String type,
    required Map<String, Object?> payload,
  }) async {
    final response = await _dio.postUri<void>(
      Uri.parse(baseUrl).resolve('v1/playback/commands'),
      data: {
        'sourceDeviceId': sourceDeviceId,
        'targetDeviceId': targetDeviceId,
        'type': type,
        'payload': payload,
      },
      options: await _options(),
    );
    return response.statusCode == 202;
  }

  Future<void> registerFcmToken({
    required String deviceId,
    required String token,
  }) async {
    await _dio.putUri<void>(
      Uri.parse(baseUrl).resolve('v1/playback/push-registration'),
      data: {'deviceId': deviceId, 'provider': 'fcm', 'token': token},
      options: await _options(),
    );
  }

  Future<List<CloudPlaybackCommand>> pendingPlaybackCommands(
    String deviceId,
  ) async {
    final response = await _dio.getUri<List<dynamic>>(
      Uri.parse(baseUrl).resolve('v1/playback/commands?deviceId=$deviceId'),
      options: await _options(),
    );
    return (response.data ?? const <dynamic>[])
        .whereType<Map>()
        .map(
          (item) =>
              CloudPlaybackCommand.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<void> acknowledgePlaybackCommand({
    required String commandId,
    required String deviceId,
    required bool applied,
  }) async {
    await _dio.postUri<void>(
      Uri.parse(baseUrl).resolve('v1/playback/commands/$commandId/ack'),
      data: {'targetDeviceId': deviceId, 'applied': applied},
      options: await _options(),
    );
  }

  Future<CloudPlaybackSession?> playbackSession() async {
    final response = await _dio.getUri<dynamic>(
      Uri.parse(baseUrl).resolve('v1/playback/session'),
      options: await _options(),
    );
    if (response.statusCode == 204 || response.data == null) return null;
    return CloudPlaybackSession.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  /// Declares this device the audio target for what it is already playing, so
  /// another device can subscribe to it as a remote.
  ///
  /// Unlike [startPlaybackSession] nothing is handed anywhere and no command is
  /// emitted — the caller keeps playing exactly as it was. Returns null when
  /// the server refuses, which includes a 409 for a session another device
  /// already owns and a 404 on servers predating the endpoint.
  Future<String?> claimPlaybackSession({
    required String deviceId,
    required Map<String, Object?> state,
  }) async {
    try {
      final response = await _dio.postUri<Map<String, dynamic>>(
        Uri.parse(baseUrl).resolve('v1/playback/session/claim'),
        data: {'deviceId': deviceId, 'state': state},
        options: await _options(),
      );
      return response.data?['sessionId']?.toString();
    } on DioException catch (error) {
      // Refusing is a normal outcome, not a failure to report: 409 means
      // another device legitimately owns the session, and 404 means the server
      // has not been updated yet. Either way this device simply keeps playing
      // without advertising.
      final status = error.response?.statusCode;
      if (status == 409 || status == 404) return null;
      rethrow;
    }
  }

  Future<String> startPlaybackSession({
    required String sourceDeviceId,
    required String targetDeviceId,
    required Map<String, Object?> state,
  }) async {
    final response = await _dio.postUri<Map<String, dynamic>>(
      Uri.parse(baseUrl).resolve('v1/playback/session/start'),
      data: {
        'sourceDeviceId': sourceDeviceId,
        'targetDeviceId': targetDeviceId,
        'state': state,
      },
      options: await _options(),
    );
    return response.data?['sessionId']?.toString() ?? '';
  }

  Future<void> sendSessionCommand({
    required String sourceDeviceId,
    required String targetDeviceId,
    required String type,
    required Map<String, Object?> payload,
  }) async {
    await _dio.postUri<void>(
      Uri.parse(baseUrl).resolve('v1/playback/session/command'),
      data: {
        'sourceDeviceId': sourceDeviceId,
        'targetDeviceId': targetDeviceId,
        'type': type,
        'payload': payload,
      },
      options: await _options(),
    );
  }

  Future<void> updatePlaybackSessionState({
    required String deviceId,
    required Map<String, Object?> state,
  }) async {
    await _dio.postUri<void>(
      Uri.parse(baseUrl).resolve('v1/playback/session/state'),
      data: {'deviceId': deviceId, 'state': state},
      options: await _options(),
    );
  }

  Future<void> switchPlaybackTarget({
    required String sourceDeviceId,
    required String targetDeviceId,
    required Map<String, Object?> state,
  }) async {
    await _dio.postUri<void>(
      Uri.parse(baseUrl).resolve('v1/playback/session/target'),
      data: {
        'sourceDeviceId': sourceDeviceId,
        'targetDeviceId': targetDeviceId,
        'state': state,
      },
      options: await _options(),
    );
  }

  Future<void> endPlaybackSession() async {
    await _dio.deleteUri<void>(
      Uri.parse(baseUrl).resolve('v1/playback/session'),
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

  Future<Options> _options() async {
    final token = await _accessToken();
    return Options(
      headers: {
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    );
  }
}
