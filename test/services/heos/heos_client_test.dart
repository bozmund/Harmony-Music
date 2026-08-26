import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/heos/heos_client.dart';
import 'package:harmonymusic/services/heos/heos_models.dart';

void main() {
  group('heosCommand', () {
    test('encodes query parameters for HEOS CLI commands', () {
      final command = heosCommand('browse/play_stream', {
        'pid': '123',
        'url': 'https://example.com/audio.m4a?token=a b&sig=1',
      });

      expect(command, startsWith('heos://browse/play_stream?'));
      expect(command, contains('pid=123'));
      expect(command, contains('url=https%3A%2F%2Fexample.com%2Faudio.m4a'));
      expect(command, contains('token%3Da+b%26sig%3D1'));
    });
  });

  group('HeosResponse', () {
    test('parses HEOS message fields and player payloads', () {
      final response = HeosResponse.fromJson({
        'heos': {
          'command': 'player/get_players',
          'result': 'success',
          'message': 'pid=1&name=Living+Room',
        },
        'payload': [
          {'pid': 1, 'name': 'Living Room', 'model': 'Home 150'},
        ],
      });

      expect(response.isSuccess, isTrue);
      expect(response.command, 'player/get_players');
      expect(response.message['pid'], '1');
      expect(response.message['name'], 'Living Room');

      final players = response.payload
          .whereType<Map>()
          .map((item) => HeosPlayer.fromJson(Map<String, dynamic>.from(item)))
          .toList();

      expect(players, hasLength(1));
      expect(players.single.pid, '1');
      expect(players.single.name, 'Living Room');
    });
  });
}
