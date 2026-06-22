import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'player_source.dart';

Future<String?> getVisitorData({bool generateNew = false}) async {
  final tempDir =
      Directory("${(await getTemporaryDirectory()).path}/streamTemp");
  if (!tempDir.existsSync()) {
    tempDir.createSync(recursive: true);
  }

  final file = File("${tempDir.path}/visitordata.json");
  if (await file.exists() && !generateNew) {
    dynamic data;
    try {
      data = jsonDecode(await file.readAsString());
    } catch (e) {}
    if (data == null ||
        DateTime.now().millisecondsSinceEpoch > (data![1] + 6 * 3600000)) {
      generateNew = true;
    } else {
      return data[0];
    }
  }

  final visitorData_ = await getVisitorDataCommon();
  if (visitorData_ != null) {
    file.writeAsString(
        jsonEncode([visitorData_, DateTime.now().millisecondsSinceEpoch]),
        flush: true);
  }

  return visitorData_;
}
