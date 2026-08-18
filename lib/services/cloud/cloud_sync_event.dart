import 'dart:convert';

class CloudSyncEvent {
  const CloudSyncEvent({
    required this.eventId,
    required this.deviceSequence,
    required this.hlcPhysicalMs,
    required this.hlcLogical,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
  });

  final String eventId;
  final int deviceSequence;
  final int hlcPhysicalMs;
  final int hlcLogical;
  final String entityType;
  final String entityId;
  final String operation;
  final Object? payload;

  Map<String, dynamic> toJson() => {
    'eventId': eventId,
    'deviceSequence': deviceSequence,
    'hlcPhysicalMs': hlcPhysicalMs,
    'hlcLogical': hlcLogical,
    'entityType': entityType,
    'entityId': entityId,
    'operation': operation,
    'payload': payload,
  };

  factory CloudSyncEvent.fromJson(dynamic raw) {
    final json = Map<String, dynamic>.from(raw as Map);
    return CloudSyncEvent(
      eventId: json['eventId'] as String,
      deviceSequence: json['deviceSequence'] as int,
      hlcPhysicalMs: json['hlcPhysicalMs'] as int,
      hlcLogical: json['hlcLogical'] as int,
      entityType: json['entityType'] as String,
      entityId: json['entityId'] as String,
      operation: json['operation'] as String,
      payload: json['payload'],
    );
  }
}

String canonicalJson(Object? value) => jsonEncode(_canonical(value));

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {
      for (final key in keys)
        key: _canonical(
          value[key] ??
              value.entries
                  .firstWhere((entry) => entry.key.toString() == key)
                  .value,
        ),
    };
  }
  if (value is Iterable) return value.map(_canonical).toList();
  if (value is Uri || value is Duration || value is DateTime) {
    return value.toString();
  }
  if (value is num || value is bool || value is String || value == null) {
    return value;
  }
  return value.toString();
}

String stableFingerprint(String input) {
  var hash = BigInt.parse('14695981039346656037');
  final prime = BigInt.parse('1099511628211');
  final mask = BigInt.parse('9223372036854775807');
  for (final unit in input.codeUnits) {
    hash ^= BigInt.from(unit);
    hash = (hash * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
