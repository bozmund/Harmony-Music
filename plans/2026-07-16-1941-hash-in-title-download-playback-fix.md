# Downloaded songs with `#` in the title fail to play (Source error)

## Context

On-device testing surfaced a session-restore `(0) Source error` for the downloaded song "Skengdo x AM - Lightwork #DesertEdition". The new ExoPlayer log pinpoints the root cause:

```
FileDataSource$FileDataSourceException: uri has query and/or fragment, which are not supported.
path=/data/user/0/.../files/Music/Skengdo x AM - Lightwork , fragment=DesertEdition (...).opus
Caused by: FileNotFoundException: ... Lightwork : open failed: ENOENT
```

Two compounding defects:
1. **Playback** — `_createAudioSource` (`lib/services/audio_handler.dart:1250-1277`) builds the source with `AudioSource.uri(Uri.tryParse(url)!)`. For downloaded songs, `url` is a raw filesystem path; `Uri.tryParse` treats `#` as a fragment separator (and `?` as query), truncating the path ExoPlayer receives. The previously added restore-retry fired correctly but couldn't help: `checkNGetUrl` returns the same broken download path again.
2. **Download** — the filename sanitizer (`lib/services/downloader.dart:274`, regex `[/\\"<>*?:!\[\]¡|%]`) strips many special characters but not `#`, so titles with `#` produce files whose paths break `Uri.parse`-based playback.

The preload paths (`playback_preload_manager.dart:198`, `playback_preload_service.dart:90`) are gated by `isPreloadableNetworkUrl` (http/https only) and are unaffected. The cached-songs path (`file://$_cacheDir/cachedSongs/$songId.mp3`) uses safe YouTube IDs, unaffected — but goes through the same construction sites, so it must keep working.

## Change

**`lib/services/audio_handler.dart`** — add a small private helper on `MyAudioHandler` and use it at both URI construction sites in `_createAudioSource`:

```dart
/// Local file paths can contain '#' or '?' from song titles; Uri.parse
/// treats those as fragment/query separators and truncates the path, so
/// build file URIs with Uri.file instead.
Uri _playableUri(String url) {
  if (url.startsWith('file://')) {
    return Uri.file(url.substring('file://'.length));
  }
  if (_isLocalSourceUrl(url) ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(url)) {
    return Uri.file(url);
  }
  return Uri.parse(url);
}
```
- Line 1268 (`LockCachingAudioSource(Uri.parse(url), ...)`) → `LockCachingAudioSource(_playableUri(url), ...)`
- Line 1276 (`AudioSource.uri(Uri.tryParse(url)!, ...)`) → `AudioSource.uri(_playableUri(url), ...)`

Reuses the existing `_isLocalSourceUrl` classifier (`audio_handler.dart:1150`). The `file://` branch strips the prefix from the raw string (not via `toFilePath()`, which would itself lose anything after `#`) — cached-song URLs are formed as `"file://$_cacheDir/..."` where `_cacheDir` starts with `/`, so the remainder is a valid absolute path. The drive-letter regex covers Windows desktop download paths, which `_isLocalSourceUrl` misses (it only checks `startsWith('/')`).

**`lib/services/downloader.dart:274`** — add `#` to the invalid-character regex so new downloads never embed it in filenames: `RegExp(r'[/\\"<>*?:!\[\]¡|%#]')`. (Existing files with `#` keep working via the playback fix.)

Keep the earlier session-restore retry — it remains correct for genuinely stale/expired stream URLs.

## Verification

- `flutter analyze --no-pub` via the `harmony-flutter-dart` MCP tool (timeout 600000).
- Run `flutter test test/audio_handler_source_swap_test.dart test/playback_session_persistence_test.dart` to confirm no regressions in source-creation behavior.
- Manual verification by the user on device (per project convention): the existing downloaded "#DesertEdition" song should now restore and play after an app restart; a fresh download of a `#`-titled song should produce a filename without `#`; cached (non-downloaded) songs and normal streaming should be unaffected.
