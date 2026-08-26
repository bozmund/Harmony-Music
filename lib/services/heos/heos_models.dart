enum HeosCastStatus { disconnected, discovering, connected, casting, error }

class HeosDevice {
  const HeosDevice({
    required this.ipAddress,
    required this.name,
    this.model,
    this.location,
  });

  final String ipAddress;
  final String name;
  final String? model;
  final Uri? location;

  HeosDevice copyWith({String? name, String? model, Uri? location}) {
    return HeosDevice(
      ipAddress: ipAddress,
      name: name ?? this.name,
      model: model ?? this.model,
      location: location ?? this.location,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HeosDevice &&
          runtimeType == other.runtimeType &&
          ipAddress == other.ipAddress;

  @override
  int get hashCode => ipAddress.hashCode;
}

class HeosPlayer {
  const HeosPlayer({
    required this.pid,
    required this.name,
    this.model,
    this.ipAddress,
  });

  final String pid;
  final String name;
  final String? model;
  final String? ipAddress;

  factory HeosPlayer.fromJson(Map<String, dynamic> json) {
    return HeosPlayer(
      pid: json['pid']?.toString() ?? '',
      name: json['name']?.toString() ?? 'HEOS speaker',
      model: json['model']?.toString(),
      ipAddress: json['ip']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HeosPlayer &&
          runtimeType == other.runtimeType &&
          pid == other.pid;

  @override
  int get hashCode => pid.hashCode;
}

class HeosResponse {
  const HeosResponse({
    required this.command,
    required this.message,
    this.result,
    this.payload = const [],
  });

  final String command;
  final Map<String, String> message;
  final String? result;
  final List<dynamic> payload;

  factory HeosResponse.fromJson(Map<String, dynamic> json) {
    final heos = json['heos'];
    final heosMap = heos is Map ? Map<String, dynamic>.from(heos) : {};
    final message = _parseMessage(heosMap['message']?.toString());
    final payload = json['payload'];
    return HeosResponse(
      command: heosMap['command']?.toString() ?? '',
      result: heosMap['result']?.toString(),
      message: message,
      payload: payload is List ? payload : const [],
    );
  }

  bool get isSuccess => result == null || result == 'success';

  static Map<String, String> _parseMessage(String? value) {
    if (value == null || value.isEmpty) return const {};
    return Uri.splitQueryString(value);
  }
}
