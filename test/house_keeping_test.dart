import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/utils/house_keeping.dart';

void main() {
  group('shouldDeleteStreamCacheEntry', () {
    test('keeps non-expired map-shaped stream cache entries', () {
      final entry = _streamCacheEntry(
        lowUrl: _urlWithExpire(secondsFromNow: 3600),
        highUrl: _urlWithExpire(secondsFromNow: 3600),
      );

      expect(shouldDeleteStreamCacheEntry(entry), isFalse);
    });

    test('deletes expired map-shaped stream cache entries', () {
      final entry = _streamCacheEntry(
        lowUrl: _urlWithExpire(secondsFromNow: -60),
        highUrl: _urlWithExpire(secondsFromNow: -60),
      );

      expect(shouldDeleteStreamCacheEntry(entry), isTrue);
    });

    test('deletes malformed map-shaped stream cache entries', () {
      final entry = _streamCacheEntry(
        lowUrl: _urlWithExpire(secondsFromNow: 3600),
        highUrl: _urlWithExpire(secondsFromNow: 3600),
      )..['highQualityAudio'] = null;

      expect(shouldDeleteStreamCacheEntry(entry), isTrue);
    });

    test('deletes malformed legacy list entries without throwing', () {
      expect(shouldDeleteStreamCacheEntry([true, 'bad']), isTrue);
      expect(shouldDeleteStreamCacheEntry('bad'), isTrue);
    });
  });
}

Map<String, dynamic> _streamCacheEntry({
  required String lowUrl,
  required String highUrl,
}) {
  return {
    'playable': true,
    'statusMSG': 'OK',
    'lowQualityAudio': {'url': lowUrl},
    'highQualityAudio': {'url': highUrl},
  };
}

String _urlWithExpire({required int secondsFromNow}) {
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + secondsFromNow;
  return 'https://example.test/audio?expire=$expiry&signature=test';
}
