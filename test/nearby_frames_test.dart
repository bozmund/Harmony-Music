import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/listen_together/nearby_frames.dart';

void main() {
  test('Nearby frames reassemble a large payload in order', () {
    final codec = NearbyFrameCodec(chunkSize: 8);
    final payload = Uint8List.fromList(List.generate(1000, (i) => i % 251));
    final frames = codec.encode(payload);
    Uint8List? result;
    for (final frame in frames.reversed) {
      result = codec.add(frame) ?? result;
    }
    expect(result, payload);
  });

  test('stale partial transfers are discarded', () {
    final codec = NearbyFrameCodec(
      chunkSize: 2,
      timeout: const Duration(seconds: 1),
    );
    final frames = codec.encode(Uint8List.fromList([1, 2, 3, 4]));
    expect(codec.add(frames.first, now: DateTime(2026)), isNull);
    expect(
      codec.add(
        frames.last,
        now: DateTime(2026).add(const Duration(seconds: 2)),
      ),
      isNull,
    );
  });

  test('reset drops partial transfers between sessions', () {
    final codec = NearbyFrameCodec(chunkSize: 2);
    final frames = codec.encode(Uint8List.fromList([1, 2, 3, 4]));
    expect(codec.add(frames.first), isNull);
    codec.reset();
    expect(codec.add(frames.last), isNull);
  });
}
