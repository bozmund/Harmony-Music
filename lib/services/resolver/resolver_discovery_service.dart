import 'dart:async';
import 'dart:convert';

import 'package:nsd/nsd.dart' as nsd;

class ResolverDiscoveryService {
  static const serviceType = '_harmony-resolver._tcp';

  Future<List<Uri>> discover({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final discovery = await nsd.startDiscovery(
      serviceType,
      ipLookupType: nsd.IpLookupType.v4,
    );
    try {
      await Future<void>.delayed(timeout);
      return discovery.services
          .map(_toUri)
          .whereType<Uri>()
          .toSet()
          .toList(growable: false);
    } finally {
      await nsd.stopDiscovery(discovery);
    }
  }

  Uri? _toUri(nsd.Service service) {
    final addresses = service.addresses;
    final host = addresses != null && addresses.isNotEmpty
        ? addresses.first.address
        : service.host;
    final port = service.port;
    if (host == null || port == null) return null;
    final schemeBytes = service.txt?['scheme'];
    final scheme = schemeBytes == null ? 'http' : utf8.decode(schemeBytes);
    return Uri(scheme: scheme, host: host, port: port);
  }
}
