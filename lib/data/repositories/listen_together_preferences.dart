import 'package:hive/hive.dart';

import '../../services/constant.dart';
import '../../services/listen_together/sync_transport.dart';

class ListenTogetherPreferences {
  Box get _box => Hive.box(BoxNames.appPrefs);
  String get deviceName =>
      _box.get(PrefKeys.listenTogetherDeviceName) ?? 'Harmony device';
  Future<void> setDeviceName(String value) =>
      _box.put(PrefKeys.listenTogetherDeviceName, value.trim());

  TransportKind get transport {
    final value = _box.get(PrefKeys.listenTogetherTransport)?.toString();
    return TransportKind.values.firstWhere(
      (item) => item.name == value,
      orElse: () => TransportKind.both,
    );
  }

  Future<void> setTransport(TransportKind value) =>
      _box.put(PrefKeys.listenTogetherTransport, value.name);
}
