import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../utils/helper.dart';
import '../constant.dart';
import 'heos_models.dart';

class HeosDiscoveryService {
  static final _multicastAddress = InternetAddress('239.255.255.250');
  static const _multicastPort = 1900;
  static const _searchTarget = 'urn:schemas-denon-com:device:ACT-Denon:1';

  Future<List<HeosDevice>> discover({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      ttl: 4,
    );
    final devices = <String, HeosDevice>{};
    final completer = Completer<List<HeosDevice>>();
    late final StreamSubscription<RawSocketEvent> subscription;
    Timer? timer;

    void finish() {
      if (completer.isCompleted) return;
      timer?.cancel();
      unawaited(subscription.cancel());
      socket.close();
      completer.complete(devices.values.toList());
    }

    subscription = socket.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = socket.receive()) != null) {
          final packet = datagram!;
          final headers = _parseHeaders(utf8.decode(packet.data));
          if (!_isHeosResponse(headers)) continue;
          final location = Uri.tryParse(headers['location'] ?? '');
          final ipAddress = location?.host.isNotEmpty == true
              ? location!.host
              : packet.address.address;
          devices[ipAddress] = HeosDevice(
            ipAddress: ipAddress,
            name: headers['server'] ?? 'HEOS speaker',
            model: headers['st'],
            location: location,
          );
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        printERROR('HEOS discovery failed: $error', tag: LogTags.heos);
        printERROR(stackTrace, tag: LogTags.heos);
        finish();
      },
    );

    socket.send(
      utf8.encode(_mSearchRequest()),
      _multicastAddress,
      _multicastPort,
    );
    timer = Timer(timeout, finish);
    return completer.future;
  }

  Map<String, String> _parseHeaders(String response) {
    final headers = <String, String>{};
    final lines = const LineSplitter().convert(response);
    for (final line in lines.skip(1)) {
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      headers[line.substring(0, separator).trim().toLowerCase()] = line
          .substring(separator + 1)
          .trim();
    }
    return headers;
  }

  bool _isHeosResponse(Map<String, String> headers) {
    final target = '${headers['st'] ?? ''} ${headers['usn'] ?? ''}'
        .toLowerCase();
    return target.contains('schemas-denon-com') ||
        target.contains('act-denon') ||
        target.contains('heos');
  }

  String _mSearchRequest() {
    return [
      'M-SEARCH * HTTP/1.1',
      'HOST: 239.255.255.250:1900',
      'MAN: "ssdp:discover"',
      'MX: 2',
      'ST: $_searchTarget',
      '',
      '',
    ].join('\r\n');
  }
}
