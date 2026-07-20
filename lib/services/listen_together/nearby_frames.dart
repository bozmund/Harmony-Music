import 'dart:convert';
import 'dart:typed_data';

class NearbyFrameCodec {
  NearbyFrameCodec({
    this.chunkSize = 12 * 1024,
    this.timeout = const Duration(seconds: 30),
  });
  final int chunkSize;
  final Duration timeout;
  int _sequence = 0;
  final Map<String, _Assembly> _assemblies = {};

  void reset() => _assemblies.clear();

  List<Uint8List> encode(Uint8List payload) {
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    final count = payload.isEmpty ? 1 : (payload.length / chunkSize).ceil();
    return List.generate(count, (index) {
      final start = index * chunkSize;
      final end = (start + chunkSize).clamp(0, payload.length);
      return Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'v': 1,
            'id': id,
            'i': index,
            'n': count,
            'd': base64Encode(payload.sublist(start, end)),
          }),
        ),
      );
    });
  }

  Uint8List? add(Uint8List frame, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    _assemblies.removeWhere(
      (_, value) => clock.difference(value.created) > timeout,
    );
    final json = jsonDecode(utf8.decode(frame)) as Map<String, dynamic>;
    if (json['v'] != 1) return null;
    final id = json['id'] as String;
    final index = json['i'] as int;
    final count = json['n'] as int;
    if (count <= 0 || index < 0 || index >= count) return null;
    final assembly = _assemblies.putIfAbsent(id, () => _Assembly(clock, count));
    if (assembly.count != count) {
      _assemblies.remove(id);
      return null;
    }
    assembly.parts[index] = base64Decode(json['d'] as String);
    if (assembly.parts.length != count) return null;
    final bytes = <int>[];
    for (var i = 0; i < count; i++) {
      final part = assembly.parts[i];
      if (part == null) return null;
      bytes.addAll(part);
    }
    _assemblies.remove(id);
    return Uint8List.fromList(bytes);
  }
}

class _Assembly {
  _Assembly(this.created, this.count);
  final DateTime created;
  final int count;
  final Map<int, Uint8List> parts = {};
}
