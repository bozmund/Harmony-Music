import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../retry.dart';
import '../youtube_http_client.dart';

///
class PlayerSource {
  final String root;

  ///
  PlayerSource(this.root);

  /// Same as default constructor
  PlayerSource.parse(this.root);

  ///
  static Future<PlayerSource> get(
    YoutubeHttpClient httpClient,
    String url,
  ) async {
    if (_cache[url]?.expired ?? true) {
      final val = await retry(httpClient, () async {
        final raw = await httpClient.getString(url);
        return PlayerSource.parse(raw);
      });
      if (_cache[url] == null) {
        _cache[url] = _CachedValue(val);
      } else {
        _cache[url]!.update(val);
      }
    }
    return _cache[url]!.value;
  }

  static final Map<String, _CachedValue<PlayerSource>> _cache = {};
}

class _CachedValue<T> {
  T _value;
  int expireTime;
  final int cacheTime;

  T get value {
    if (expired) {
      throw StateError('Value $_value is expired!');
    }
    return _value;
  }

  bool get expired {
    final now = DateTime.now().millisecondsSinceEpoch;
    return now > expireTime;
  }

  set value(T other) => _value = other;

  _CachedValue(this._value, [this.cacheTime = 600000])
      : expireTime = DateTime.now().millisecondsSinceEpoch + cacheTime;

  void update(T newValue) {
    final now = DateTime.now().millisecondsSinceEpoch;
    expireTime = now + cacheTime;
    value = newValue;
  }
}

Future<String?> getVisitorDataCommon() async {
  try {
    final x = await http
        .get(Uri.parse("https://www.youtube.com/sw.js_data"), headers: {
      "user-agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36"
    });
    String resBody = x.body;
    if (x.statusCode == 200 && resBody.contains(")]}'")) {
      resBody = resBody.replaceFirst(")]}'", "");
      final visitorData_ = (jsonDecode(resBody))[0][2][0][0][13];
      return visitorData_;
    }
  } catch (e) {
    if (e is SocketException) {
      rethrow;
    }
  }
  return null;
}
