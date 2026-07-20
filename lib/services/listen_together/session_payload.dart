import 'package:audio_service/audio_service.dart';

import '../../models/media_Item_builder.dart';

/// Serialize a song for the session wire, stripping any local-source `url`
/// (downloaded/cached file paths) that would be unresolvable on other devices
/// — the receiver re-resolves its own stream from the `videoId`.
///
/// Lives outside [ListenTogetherController] so [PlayerController] can build
/// payloads without importing the controller (which would recreate the
/// construction cycle the gate abstraction exists to avoid).
Map<String, dynamic> sessionSafeSongJson(MediaItem item) {
  final json = MediaItemBuilder.toJson(item);
  final url = json['url'];
  if (url is String && isLocalSourceUrl(url)) {
    json.remove('url');
  }
  return json;
}

bool isLocalSourceUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (uri.scheme == 'file') return true;
  if (uri.scheme == 'http' || uri.scheme == 'https') return false;
  return url.startsWith('/') || url.contains('/cache');
}

/// Split [items] into consecutive chunks of at most [size] elements,
/// preserving order. Used to keep large enqueue-list payloads within a
/// reasonable per-frame size on the session transport.
List<List<T>> chunkList<T>(List<T> items, int size) {
  assert(size > 0);
  final chunks = <List<T>>[];
  for (var i = 0; i < items.length; i += size) {
    chunks.add(
      items.sublist(i, i + size > items.length ? items.length : i + size),
    );
  }
  return chunks;
}
