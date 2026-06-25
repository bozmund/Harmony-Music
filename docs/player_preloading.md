# Player Preloading

## Old Flow

Before the preload remaster, the player treated playback as a one-song source.
When the user selected a song, `MyAudioHandler` cleared the current audio
source, fetched the selected song's stream URL, added a new source, and then
started playback. The UI followed `audioHandler.mediaItem`, so visible song
info could feel delayed when stream lookup or source loading was slow.

## New Flow

Playback now has two user-selectable modes:

- **Classic**: the default stable one-song source flow.
- **Preloaded**: an experimental Android-only mode that enables nearby-song
  preloading.

The selected `MediaItem` is published immediately when a song change starts.
`PlayerController` updates title, artist, artwork, queue highlight, progress,
and lyrics state right away. Slower side effects such as favorite lookup,
recently played writes, and radio continuation happen after the visible state
has already changed.

On Android, the optional preload layer can prepare nearby songs while playback
is active. The preload range setting is numeric:

- `1..5`: prepare songs within that distance of the current song.

Classic mode is the default, so existing users do not spend extra network or
battery unless they choose the preloaded mode.

## Preload Lifecycle

`PlaybackPreloadService` owns `PlaybackPreloadManager` and is called by
`MyAudioHandler` only when preloaded playback is enabled. `MyAudioHandler` still
owns the active queue, playback index, and current one-song audio source.

When playback is active and the range is greater than zero, the handler computes
candidate queue indices around the current song. In shuffle mode, this uses the
shuffle order without mutating the current shuffle position. For each candidate,
the preload manager resolves `HMStreamingData`, stores stream URL metadata in
`SongsUrlCache`, and downloads a temporary prefix of the selected audio stream.

The prefix target is based on roughly three seconds of audio:

```text
target bytes = bitrate / 8 * 3 seconds + safety margin
```

The target is clamped so unusually low or high bitrate data does not create tiny
or runaway temp files. This is a best-effort decoded-time target; exact playable
seconds can vary by codec and container.

## Playback With A Preloaded Prefix

When a selected song has a ready temporary prefix and normal song caching is not
enabled, `_createAudioSource` uses `PreloadedPrefixAudioSource`. That source
serves cached prefix bytes first and falls through to network range requests for
the rest of the stream. If no prefix is available, playback falls back to the
normal `AudioSource.uri` or existing `LockCachingAudioSource` behavior.

The preload files are temporary only. They do not create offline songs and do
not populate `SongsCache`.

## Cleanup

Changing the preload range, queue, shuffle state, loop state, or playback state
invalidates the preload window. Temporary prefix files outside the configured
range are deleted. Explicit pause clears preload files; internal song-change
stops do not clear them, so a prepared prefix can still be used during the
transition.

## Failure Behavior

If stream info fails, playback retries once with a fresh URL. If retry also
fails, the selected song remains visible, playback moves to error/paused state,
and the existing snackbar tells the user what happened. The app does not
auto-skip or revert to the previous song.
