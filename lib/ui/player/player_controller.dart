import 'dart:async';
import 'dart:io' show SocketException;
import 'package:dio/dio.dart' show DioException;
import 'package:harmonymusic/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:flutter_lyric/flutter_lyric.dart';

import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/lyrics_repository.dart';
import '../../domain/repositories/playback_session_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../models/media_Item_builder.dart';
import '../../models/playing_from.dart';

import '../../app/navigation/app_navigator.dart';
import '../../services/app_platform_service.dart';
import '../../services/downloader.dart';
import '../../services/listen_together/listen_together_gate.dart';
import '../../services/listen_together/session_message.dart';
import '../../services/listen_together/session_payload.dart';
import '../../services/cloud/playback_socket_client.dart';
import '../../services/cloud/playback_modes.dart';
import '../../services/heos/heos_cast_controller.dart';
import '../../services/heos/heos_models.dart';
import '../../services/playback_command_service.dart';
import '../../services/previous_track_policy.dart';
import '../../utils/runtime_platform.dart';
import '../../utils/observable_state.dart';
import 'remote_progress_anchor.dart';
import '../screens/Library/library_controller.dart';
import '../screens/Playlist/playlist_screen_controller.dart';
import '../widgets/snackbar.dart';
import '/services/synced_lyrics_service.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '../../services/windows_audio_service.dart';
import '../../utils/helper.dart';
import '../screens/Home/home_screen_controller.dart';
import '../widgets/bottom_nav_bar_dimensions.dart';
import '../widgets/sliding_up_panel.dart';
import '/models/duration_state.dart';
import '/services/app_contracts.dart';

import '/services/constant.dart';

class PlayerController extends ChangeNotifier implements TickerProvider {
  PlayerController({
    required AudioHandler audioHandler,
    required SettingsScreenController settingsController,
    required HomeScreenController homeScreenController,
    required Downloader downloader,
    required SettingsRepository settingsRepository,
    required LibraryRepository libraryRepository,
    required LyricsRepository lyricsRepository,
    required PlaybackSessionRepository playbackSessionRepository,
    required MusicServiceContract musicService,
    required PlaybackCommandService playbackCommands,
    required HeosCastController heosCastController,
  }) : _audioHandler = audioHandler,
       _settingsController = settingsController,
       _homeScreenController = homeScreenController,
       _downloader = downloader,
       _settingsRepository = settingsRepository,
       _libraryRepository = libraryRepository,
       _lyricsRepository = lyricsRepository,
       _playbackSessionRepository = playbackSessionRepository,
       _musicServices = musicService,
       _playbackCommands = playbackCommands,
       heosCastController = heosCastController;

  final SettingsRepository _settingsRepository;
  final LibraryRepository _libraryRepository;
  final LyricsRepository _lyricsRepository;
  final PlaybackSessionRepository _playbackSessionRepository;
  final AudioHandler _audioHandler;
  final SettingsScreenController _settingsController;
  final HomeScreenController _homeScreenController;
  final Downloader _downloader;
  final MusicServiceContract _musicServices;
  final PlaybackCommandService _playbackCommands;

  /// Set by [ListenTogetherController] while a session is active. When this
  /// device is a guest, local control intents are forwarded to the host
  /// instead of being executed locally. Null when no session is active.
  ListenTogetherGate? listenTogetherGate;

  final HeosCastController heosCastController;
  final currentQueue = ObservableList<MediaItem>();

  final playerPaneOpacity = ObservableValue(1.0);
  final playerPanelTopVisible = ObservableValue(true);
  final playerPanelOpen = ObservableValue(false);
  final playerPanelMinHeight = ObservableValue(0.0);
  bool initFlagForPlayer = true;
  final isQueueReorderingInProcess = ObservableValue(false);

  /// Whether a tap's queue is still being fetched. The tapped song starts
  /// playing immediately against a placeholder queue of just itself, so without
  /// this the gap between "playing" and "queue filled" — which a retry can
  /// stretch to several seconds — is indistinguishable from a queue that simply
  /// never filled.
  final isQueueExpanding = ObservableValue(false);
  PanelController playerPanelController = PanelController();
  PanelController queuePanelController = PanelController();
  AnimationController? gesturePlayerStateAnimationController;
  Animation<double>? gesturePlayerStateAnimation;
  bool isRadioModeOn = false;
  String? radioContinuationParam;
  int _playNowSelectionGeneration = 0;
  dynamic radioInitiatorItem;
  Timer? sleepTimer;
  WindowsAudioService? _windowsAudioService;
  int timerDuration = 0;
  final timerDurationLeft = ObservableValue(0);
  final isSleepTimerActive = ObservableValue(false);
  final isSleepEndOfSongActive = ObservableValue(false);
  final volume = ObservableValue(100);

  final progressBarStatus = ObservableValue(
    ProgressBarState(
      buffered: Duration.zero,
      current: Duration.zero,
      total: Duration.zero,
    ),
  );

  final currentSongIndex = ObservableValue(0);
  final isFirstSong = true;
  final isLastSong = true;
  final isQueueLoopModeEnabled = ObservableValue(true);
  final isLoopModeEnabled = ObservableValue(false);
  final isShuffleModeEnabled = ObservableValue(false);
  final currentSong = ObservableNullable<MediaItem>();

  /// The audio-service bridge can briefly expose an empty media item while a
  /// new installation starts its Android service. It is not a playable track
  /// and must not reserve a blank mini-player panel.
  static bool isDisplayableSong(MediaItem? song) =>
      song != null &&
      song.playable == true &&
      song.id.trim().isNotEmpty &&
      (song.title.trim().isNotEmpty || MediaItemBuilder.isResolving(song));

  bool get hasDisplayableCurrentSong => isDisplayableSong(currentSong.value);

  /// True only when we do not yet know *what* this song is.
  ///
  /// Deliberately independent of [buttonState]: a seek or a previous-button
  /// restart on an already-resolved (often cached) song makes the audio engine
  /// emit a transient buffering event, and folding that in collapsed a title we
  /// already had into shimmer bars. Audio being busy is the play button's
  /// business, not the title's.
  bool get isCurrentSongLoading {
    final song = currentSong.value;
    if (song == null) return false;
    return MediaItemBuilder.isResolving(song) || song.title.trim().isEmpty;
  }

  /// True while an online song has been selected but its first playable frame
  /// has not arrived yet. Artwork uses this narrower state for its shimmer so
  /// an ordinary mid-song rebuffer does not hide an image we already have.
  bool get isCurrentOnlineSongInitiallyLoading {
    final song = currentSong.value;
    if (song == null) return false;
    final sourceUrl = song.extras?['url']?.toString() ?? '';
    final isOnline = !sourceUrl.contains('file');
    return isOnline &&
        (_isWaitingForCurrentSourceStart || _currentSongResolving);
  }

  int? beginRemoteSongTransition(List<MediaItem> queue, int index) {
    if (!_playbackCommands.isRemoteControlActive ||
        queue.isEmpty ||
        index < 0 ||
        index >= queue.length) {
      return null;
    }
    // Previous can pass [currentQueue] itself. Snapshot before mutating the
    // observable queue; otherwise clear() also empties the input list and the
    // subsequent index lookup throws a RangeError.
    final nextQueue = List<MediaItem>.from(queue);
    _remoteTransitionRollback ??= _RemoteSongTransitionSnapshot(
      queue: List<MediaItem>.from(currentQueue),
      index: currentSongIndex.value,
      song: currentSong.value,
      progress: ProgressBarState(
        current: progressBarStatus.value.current,
        buffered: progressBarStatus.value.buffered,
        total: progressBarStatus.value.total,
      ),
      buttonState: buttonState.value,
      isFavorite: isCurrentSongFav.value,
      remoteAnchor: _remoteAnchor,
      wasProgressTicking: _remoteProgressTicker != null,
    );
    final generation = ++_remoteSongTransitionGeneration;
    _pendingRemoteSongId = nextQueue[index].id;
    _stopRemoteProgressTicker();
    _optimisticSeekIssuedAt = null;
    currentQueue
      ..clear()
      ..addAll(nextQueue);
    currentQueue.refresh();
    currentSongIndex.value = index;
    _setCurrentSongAndRefreshFavorite(nextQueue[index]);
    progressBarStatus.update((value) {
      value.current = Duration.zero;
      value.buffered = Duration.zero;
      value.total = nextQueue[index].duration ?? Duration.zero;
    });
    _currentSongResolving = true;
    _setButtonState(PlayButtonState.loading);
    _clearLyricsForSongChange();
    _notifyPlayerChanged();
    return generation;
  }

  void failRemoteSongTransition(int? generation) {
    if (generation == null ||
        generation != _remoteSongTransitionGeneration ||
        _pendingRemoteSongId == null) {
      return;
    }
    final rollback = _remoteTransitionRollback;
    _pendingRemoteSongId = null;
    _remoteTransitionRollback = null;
    _currentSongResolving = false;
    if (rollback == null) return;
    currentQueue
      ..clear()
      ..addAll(rollback.queue);
    currentQueue.refresh();
    currentSongIndex.value = rollback.index;
    currentSong.value = rollback.song;
    isCurrentSongFav.value = rollback.isFavorite;
    progressBarStatus.value = rollback.progress;
    _remoteAnchor = rollback.remoteAnchor;
    _setButtonState(rollback.buttonState);
    if (rollback.wasProgressTicking) _startRemoteProgressTicker();
    _notifyPlayerChanged();
  }

  void _confirmRemoteSongTransition() {
    _pendingRemoteSongId = null;
    _remoteTransitionRollback = null;
    _currentSongResolving = false;
  }

  int _remoteSongTransitionGeneration = 0;
  String? _pendingRemoteSongId;
  _RemoteSongTransitionSnapshot? _remoteTransitionRollback;

  void _setCurrentSongAndRefreshFavorite(MediaItem song) {
    if (currentSong.value?.id != song.id) {
      isCurrentSongFav.value = false;
    }
    // Same id, richer content is the normal case here — a placeholder being
    // replaced by resolved metadata. A plain assignment compares equal and is
    // discarded, which is what pinned the title and artist on shimmer.
    currentSong.overwrite(song);
    _logSurface('song');
    unawaited(_checkFavFor(song));
  }

  /// Mirrors the whole queue published by the active account playback target,
  /// without starting a local audio engine on this controller.
  ///
  /// Items usually arrive as placeholders and are filled in by
  /// [mergeResolvedQueueItems] as metadata resolves. The full queue matters
  /// beyond cosmetics: next/previous are enabled by comparing the current song
  /// against `currentQueue.last`, so a one-item mirror disables both buttons.
  bool applyRemoteQueue(
    List<MediaItem> queue, {
    required int index,
    required int positionMs,
    int? durationMs,
    required bool playing,
  }) {
    final pendingSongId = _pendingRemoteSongId;
    final safeIndex = queue.isEmpty ? -1 : index.clamp(0, queue.length - 1);
    if (pendingSongId != null &&
        (safeIndex < 0 || queue[safeIndex].id != pendingSongId)) {
      return false;
    }
    _cloudRemoteStateActive = true;
    currentQueue
      ..clear()
      ..addAll(queue);
    currentQueue.refresh();
    currentSongIndex.value = safeIndex;
    if (safeIndex >= 0) {
      _setCurrentSongAndRefreshFavorite(queue[safeIndex]);
    }
    applyRemoteProgress({
      'positionMs': positionMs,
      'durationMs': durationMs,
      'playing': playing,
      'publishedAtMs': DateTime.now().millisecondsSinceEpoch,
    });
    _notifyPlayerChanged();
    return true;
  }

  /// Follows the audio target moving within a queue we already hold, without
  /// rebuilding it — a skip on the target must not reset resolved metadata.
  void applyRemoteIndex(int index) {
    if (!_cloudRemoteStateActive || currentQueue.isEmpty) return;
    final safeIndex = index.clamp(0, currentQueue.length - 1);
    final pendingSongId = _pendingRemoteSongId;
    if (pendingSongId != null && currentQueue[safeIndex].id != pendingSongId) {
      return;
    }
    if (currentSongIndex.value == safeIndex) return;
    currentSongIndex.value = safeIndex;
    _setCurrentSongAndRefreshFavorite(currentQueue[safeIndex]);
    _notifyPlayerChanged();
  }

  /// Swaps resolved metadata into the mirrored queue in place, preserving order
  /// and the current index.
  void mergeResolvedQueueItems(Map<String, MediaItem> resolved) {
    if (!_cloudRemoteStateActive || resolved.isEmpty) {
      printINFO(
        'mergeResolved skipped mirroring=$_cloudRemoteStateActive '
        'items=${resolved.length}',
        tag: LogTags.cloudPlayback,
      );
      return;
    }
    var changed = false;
    for (var i = 0; i < currentQueue.length; i++) {
      final replacement = resolved[currentQueue[i].id];
      if (replacement == null) continue;
      currentQueue[i] = replacement;
      changed = true;
      if (i == currentSongIndex.value) {
        _setCurrentSongAndRefreshFavorite(replacement);
        final total = replacement.duration;
        if (total != null && total > Duration.zero) {
          progressBarStatus.update((value) => value.total = total);
        }
      }
    }
    printINFO(
      'mergeResolved items=${resolved.length} changed=$changed '
      'currentIndex=${currentSongIndex.value} '
      'currentNowResolving='
      '${currentSong.value == null ? null : MediaItemBuilder.isResolving(currentSong.value!)}',
      tag: LogTags.cloudPlayback,
    );
    if (!changed) return;
    currentQueue.refresh();
    _logSurface('merge');
    _notifyPlayerChanged();
  }

  /// Applies a progress sample from the audio target and re-anchors the local
  /// extrapolator.
  ///
  /// Samples arrive every couple of seconds; without extrapolation the bar would
  /// visibly step rather than sweep.
  void applyRemoteProgress(Map<String, dynamic> progress) {
    _cloudRemoteStateActive = true;
    applyRemotePlaybackModes(CloudPlaybackModes.fromMap(progress));
    final songId = progress['currentSongId']?.toString();
    final pendingSongId = _pendingRemoteSongId;
    if (pendingSongId != null && songId != pendingSongId) {
      return;
    }
    _applyRemoteSongMetadata(songId, progress['songMetadata']);
    // While an optimistic seek is outstanding, frames sampled BEFORE the target
    // applied it still carry the old position. Applying one yanks the bar back
    // to where it was, then the post-seek frame snaps it forward again — the
    // visible flicker when seeking a remote device. Position is the tell:
    // pre-seek samples sit far from where we just asked to be.
    final optimisticAt = _optimisticSeekIssuedAt;
    if (optimisticAt != null) {
      final sampleMs = (progress['positionMs'] as num?)?.toInt() ?? 0;
      final withinWindow =
          DateTime.now().difference(optimisticAt) <
          _optimisticSeekConfirmWindow;
      if (!withinWindow) {
        _optimisticSeekIssuedAt = null;
      } else if ((sampleMs - _optimisticSeekPosition.inMilliseconds).abs() >
          3000) {
        return;
      } else {
        // The target reports roughly the seeked position: confirmed.
        _optimisticSeekIssuedAt = null;
      }
    }
    if (songId != null && songId != currentSong.value?.id) {
      final index = currentQueue.indexWhere((item) => item.id == songId);
      if (index >= 0) {
        currentSongIndex.value = index;
        _setCurrentSongAndRefreshFavorite(currentQueue[index]);
      }
    }

    final durationMs = (progress['durationMs'] as num?)?.toInt();
    final playing = progress['playing'] == true;
    final loading =
        progress['loading'] == true ||
        (currentSong.value != null &&
            MediaItemBuilder.isResolving(currentSong.value!));
    final reportedPositionMs = (progress['positionMs'] as num?)?.toInt() ?? 0;
    final positionMs = reportedPositionMs;
    final speed = (progress['speed'] as num?)?.toDouble() ?? 1.0;
    final publishedAtMs = (progress['publishedAtMs'] as num?)?.toInt();

    progressBarStatus.update((value) {
      if (!loading && durationMs != null && durationMs > 0) {
        value.total = Duration(milliseconds: durationMs);
      } else if (currentSong.value?.duration case final total?) {
        value.total = total;
      }
      value.current = _clampProgressPosition(
        Duration(milliseconds: positionMs < 0 ? 0 : positionMs),
        value.total,
      );
      // Nothing reports buffering for a remote device; showing the played
      // position keeps the bar from rendering a permanently empty buffer.
      value.buffered = value.current;
    });

    _remoteAnchor = RemoteProgressAnchor.fromSample(
      positionMs: positionMs,
      speed: speed,
      publishedAtMs: publishedAtMs,
      now: DateTime.now(),
    );
    if (pendingSongId != null && !loading) {
      _confirmRemoteSongTransition();
    }
    _currentSongResolving = loading;
    _setButtonState(
      loading
          ? PlayButtonState.loading
          : playing
          ? PlayButtonState.playing
          : PlayButtonState.paused,
    );
    if (playing && !loading) {
      _startRemoteProgressTicker();
    } else {
      _stopRemoteProgressTicker();
    }
    _syncRemoteMediaNotification(
      currentSong.value,
      playing: playing,
      loading: loading,
      position: Duration(milliseconds: positionMs < 0 ? 0 : positionMs),
    );
    _notifyPlayerChanged();
  }

  /// Mirrors the active account session's modes without sending commands back
  /// to its audio target.
  ///
  /// The controller's local audio handler remains parked while mirroring, but
  /// the preferences are updated now so the session modes survive disconnect.
  void applyRemotePlaybackModes(CloudPlaybackModes modes) {
    if (!modes.hasAny) return;
    var changed = false;
    final writes = <Future<void>>[];
    if (modes.shuffle case final enabled?) {
      if (isShuffleModeEnabled.value != enabled) {
        isShuffleModeEnabled.value = enabled;
        changed = true;
      }
      writes.add(_settingsRepository.setShuffleModeEnabled(enabled));
    }
    if (modes.repeat case final enabled?) {
      if (isLoopModeEnabled.value != enabled) {
        isLoopModeEnabled.value = enabled;
        changed = true;
      }
      writes.add(_settingsRepository.setLoopModeEnabled(enabled));
    }
    if (modes.queueLoop case final enabled?) {
      if (isQueueLoopModeEnabled.value != enabled) {
        isQueueLoopModeEnabled.value = enabled;
        changed = true;
      }
      writes.add(_settingsRepository.setQueueLoopModeEnabled(enabled));
    }
    if (writes.isNotEmpty) unawaited(Future.wait(writes));
    if (changed) _notifyPlayerChanged();
  }

  void _syncRemoteMediaNotification(
    MediaItem? song, {
    required bool playing,
    required bool loading,
    required Duration position,
  }) {
    if (!RuntimePlatform.isAndroid || song == null) return;
    unawaited(
      _audioHandler.customAction('setRemoteNotificationMirror', {
        'mediaItem': song,
        'playing': playing,
        'loading': loading,
        'positionMs': position.inMilliseconds,
      }),
    );
  }

  void _applyRemoteSongMetadata(String? songId, Object? rawMetadata) {
    if (songId == null || rawMetadata is! Map) {
      _logRemoteMetadata(songId, 'no metadata in frame');
      return;
    }
    final metadata = Map<String, dynamic>.from(rawMetadata);
    if (metadata['id']?.toString() != songId) {
      _logRemoteMetadata(songId, 'id mismatch ${metadata['id']}');
      return;
    }
    final title = metadata['title']?.toString() ?? '';
    // Empty metadata is the required resolving placeholder, not a settled
    // description that should replace the optimistic item.
    if (title.trim().isEmpty) {
      _logRemoteMetadata(songId, 'target still publishing an empty title');
      return;
    }
    _logRemoteMetadata(songId, 'applying "$title"');

    final queueIndex = currentQueue.indexWhere((item) => item.id == songId);
    final visibleSong = currentSong.value;
    final MediaItem base;
    if (queueIndex >= 0) {
      base = currentQueue[queueIndex];
    } else if (visibleSong != null && visibleSong.id == songId) {
      base = visibleSong;
    } else {
      base = MediaItemBuilder.placeholder(songId);
    }

    final durationMs = (metadata['durationMs'] as num?)?.toInt();
    final artworkValue = metadata['artworkUri']?.toString();
    final artworkUri = artworkValue == null || artworkValue.isEmpty
        ? null
        : Uri.tryParse(artworkValue);
    // A frame that carries no usable artwork says nothing about the song's
    // artwork — it is an id-only session, and the cover was resolved locally by
    // the backfill. Falling back to null here replaced a correct cover with the
    // placeholder every time a metadata frame arrived without one.
    final safeArtworkUri =
        artworkUri != null &&
            (artworkUri.scheme == 'https' || artworkUri.scheme == 'http')
        ? artworkUri
        : base.artUri;
    final targetDuration = durationMs != null && durationMs > 0
        ? Duration(milliseconds: durationMs)
        : base.duration;
    if (!MediaItemBuilder.isResolving(base) &&
        base.title == title &&
        base.artist == metadata['artist']?.toString() &&
        base.album == metadata['album']?.toString() &&
        base.duration == targetDuration &&
        base.artUri == safeArtworkUri) {
      return;
    }
    final extras = Map<String, dynamic>.from(base.extras ?? const {});
    extras.remove(MediaItemBuilder.resolvingExtra);
    final settled = base.copyWith(
      title: title,
      artist: metadata['artist']?.toString(),
      album: metadata['album']?.toString(),
      duration: targetDuration,
      artUri: safeArtworkUri,
      extras: extras,
    );
    if (queueIndex >= 0) {
      currentQueue[queueIndex] = settled;
    }
    if (visibleSong?.id == songId || queueIndex < 0) {
      _setCurrentSongAndRefreshFavorite(settled);
      currentSongIndex.value = queueIndex;
    }
  }

  /// Why a mirrored device did or did not take the target's song description.
  /// Deduped: progress frames arrive every couple of seconds and the answer is
  /// the same every time until something changes.
  void _logRemoteMetadata(String? songId, String outcome) {
    final line = 'remoteMetadata song=$songId $outcome';
    if (line == _lastRemoteMetadataLine) return;
    _lastRemoteMetadataLine = line;
    printINFO(line, tag: LogTags.cloudPlayback);
  }

  String? _lastRemoteMetadataLine;

  RemoteProgressAnchor _remoteAnchor = RemoteProgressAnchor.zero;
  Ticker? _remoteProgressTicker;

  Duration _optimisticSeekPosition = Duration.zero;
  DateTime? _optimisticSeekIssuedAt;
  static const _optimisticSeekConfirmWindow = Duration(seconds: 3);

  /// Reflects a seek on the remote target immediately instead of waiting a full
  /// round trip. Without this the extrapolation ticker, still anchored on the
  /// old position, drags the bar back the moment the user releases the thumb.
  void _applyOptimisticRemoteSeek(Duration position) {
    _optimisticSeekPosition = position;
    _optimisticSeekIssuedAt = DateTime.now();
    _remoteAnchor = RemoteProgressAnchor(
      position: position,
      anchoredAt: DateTime.now(),
      speed: _remoteAnchor.speed,
    );
    progressBarStatus.update((value) {
      value.current = _clampProgressPosition(position, value.total);
      value.buffered = value.current;
    });
    _notifyPlayerChanged();
  }

  void _startRemoteProgressTicker() {
    if (_remoteProgressTicker != null) return;
    final ticker = createTicker((_) {
      if (!_cloudRemoteStateActive) return;
      final now = DateTime.now();
      // Samples have dried up — hold position instead of sweeping to the end.
      // Deferred: a Ticker must not be disposed from inside its own callback.
      if (_remoteAnchor.isStale(now)) {
        scheduleMicrotask(_stopRemoteProgressTicker);
        return;
      }
      final projected = _remoteAnchor.project(now);
      progressBarStatus.update((value) {
        value.current = _clampProgressPosition(projected, value.total);
        value.buffered = value.current;
      });
    });
    _remoteProgressTicker = ticker;
    // TickerFuture only completes when the ticker is stopped, which is exactly
    // what dispose does; there is nothing to await.
    unawaited(ticker.start());
  }

  void _stopRemoteProgressTicker() {
    _remoteProgressTicker?.dispose();
    _remoteProgressTicker = null;
  }

  /// Whether the audio target is still resolving the song it was handed.
  void setCurrentSongResolving(
    bool resolving, {
    MediaItem? pendingSong,
    Duration pendingPosition = Duration.zero,
  }) {
    if (_currentSongResolving == resolving && pendingSong == null) return;
    _currentSongResolving = resolving;
    if (resolving) {
      if (pendingSong != null) {
        // The handed-off song will be seeked here before it plays, so this is
        // where "the source started" must be measured from.
        _expectedSourceStartPosition = pendingPosition;
        if (currentSong.value?.id != pendingSong.id) {
          _setCurrentSongAndRefreshFavorite(pendingSong);
          currentSongIndex.value = currentQueue.indexWhere(
            (item) => item.id == pendingSong.id,
          );
          _clearLyricsForSongChange();
        }
        progressBarStatus.update((value) {
          final pendingTotal =
              pendingSong.duration ??
              (pendingPosition > Duration.zero
                  ? pendingPosition
                  : Duration.zero);
          final heldPosition = _clampProgressPosition(
            pendingPosition,
            pendingTotal,
          );
          value.current = heldPosition;
          value.buffered = heldPosition;
          value.total = pendingTotal;
        });
      }
      _setButtonState(PlayButtonState.loading);
    } else {
      final playbackState = _audioHandler.playbackState.value;
      final processingState = playbackState.processingState;
      if (processingState == AudioProcessingState.loading) {
        _cancelBufferingGrace();
        _setButtonState(PlayButtonState.loading);
      } else if (processingState == AudioProcessingState.buffering) {
        // The tail of a handoff routinely lands mid-rebuffer. Same rule as the
        // playback-state listener: a blink of buffering is not worth a spinner.
        _armBufferingGrace(playbackState.playing);
      } else {
        _cancelBufferingGrace();
        _setButtonState(
          playbackState.playing
              ? PlayButtonState.playing
              : PlayButtonState.paused,
        );
      }
    }
    _notifyPlayerChanged();
  }

  bool _currentSongResolving = false;
  bool get isCurrentSongResolving => _currentSongResolving;

  /// Makes an incoming cloud handoff visible before metadata or audio resolves.
  ///
  /// The network target bypasses the local song-tap methods that normally
  /// initialize the collapsed panel. On wide screens that left audio playing
  /// with a zero-height or stale-hidden mini-player.
  Future<void> prepareIncomingCloudSong(
    MediaItem pendingSong, {
    Duration position = Duration.zero,
  }) async {
    setCurrentSongResolving(
      true,
      pendingSong: pendingSong,
      pendingPosition: position,
    );
    if (!playerPanelOpen.value) {
      playerPanelTopVisible.value = true;
      playerPaneOpacity.value = 1;
    }
    await _playerPanelCheck(restoreSession: true);
  }

  /// Backfill progress for the queue, so the UI can say "42 of 900" instead of
  /// silently filling in rows.
  void setQueueResolutionProgress({required int resolved, required int total}) {
    final next = total <= 0 || resolved >= total ? null : (resolved, total);
    if (_queueResolution == next) return;
    _queueResolution = next;
    _notifyPlayerChanged();
  }

  (int resolved, int total)? _queueResolution;
  (int resolved, int total)? get queueResolutionProgress => _queueResolution;

  void setCloudSocketStatus(PlaybackSocketStatus status) {
    if (_cloudSocketStatus == status) return;
    _cloudSocketStatus = status;
    _notifyPlayerChanged();
  }

  PlaybackSocketStatus _cloudSocketStatus = PlaybackSocketStatus.disconnected;
  PlaybackSocketStatus get cloudSocketStatus => _cloudSocketStatus;

  /// Set by [CloudPlaybackReceiver] so its session/command state lands in the
  /// same debug dump as the player's. A plain callback avoids a dependency
  /// cycle — the receiver already holds the controller.
  Map<String, Object?> Function()? cloudReceiverDiagnostics;

  /// True while this device mirrors another device's playback.
  bool get isMirroringRemotePlayback => _cloudRemoteStateActive;

  Future<void> clearRemoteMediaNotification() async {
    if (!RuntimePlatform.isAndroid) return;
    await _audioHandler.customAction('clearRemoteNotificationMirror');
  }

  Future<void> clearRemoteSessionState() async {
    await clearRemoteMediaNotification();
    if (!_cloudRemoteStateActive) return;
    _cloudRemoteStateActive = false;
    _pendingRemoteSongId = null;
    _remoteTransitionRollback = null;
    _currentSongResolving = false;
    _stopRemoteProgressTicker();
    _queueResolution = null;
    // Resync from the local handler: while mirroring, the listeners below were
    // gated off, so the observables still hold the remote device's state.
    final localQueue = _audioHandler.queue.value;
    currentQueue
      ..clear()
      ..addAll(localQueue);
    currentQueue.refresh();
    final localItem = _audioHandler.mediaItem.value;
    if (isDisplayableSong(localItem)) {
      _setCurrentSongAndRefreshFavorite(localItem!);
    } else {
      currentSong.value = null;
      isCurrentSongFav.value = false;
    }
    currentSongIndex.value = localItem == null
        ? -1
        : localQueue.indexWhere((item) => item.id == localItem.id);
    final state = _audioHandler.playbackState.value;
    progressBarStatus.update((value) {
      value.total = localItem?.duration ?? Duration.zero;
      value.current = _clampProgressPosition(state.updatePosition, value.total);
      value.buffered = _clampProgressPosition(
        state.bufferedPosition,
        value.total,
      );
    });
    _setButtonState(
      state.playing ? PlayButtonState.playing : PlayButtonState.paused,
    );
    _notifyPlayerChanged();
  }

  final isCurrentSongFav = ObservableValue(false);
  final playingFrom = ObservableValue(
    PlayingFrom(type: PlayingFromType.SELECTION),
  );
  final showLyricsFlag = ObservableValue(false);
  final isLyricsLoading = ObservableValue(false);
  final lyricsMode = ObservableValue(0);
  bool isDesktopLyricsDialogOpen = false;

  // 0 for play, 1 for pause, 2 for blank
  final gesturePlayerVisibleState = ObservableValue(2);
  final lyricController = LyricController();
  String? _loadedSyncedLyrics;
  int _lyricsLoadGeneration = 0;
  ObservableMap<String, dynamic> lyrics = ObservableMap({
    "synced": "",
    "plainLyrics": "",
  });
  ScrollController scrollController = ScrollController();
  final GlobalKey<ScaffoldState> homeScaffoldKey = GlobalKey<ScaffoldState>();

  final buttonState = ObservableValue(PlayButtonState.paused);
  bool _cloudRemoteStateActive = false;

  // track whether wakelock is currently enabled to avoid repeated calls
  bool _wakelockActive = false;
  bool _playbackWakeLockActive = false;
  Future<void>? _playbackCommand;

  var _newSongFlag = true;
  final isCurrentSongBuffered = ObservableValue(false);

  // Edge detection for externally-initiated repeat/shuffle changes
  // (see _reflectExternalRepeatShuffleChanges).
  AudioServiceRepeatMode? _lastSeenRepeatMode;
  AudioServiceShuffleMode? _lastSeenShuffleMode;

  StreamSubscription<bool>? keyboardSubscription;
  var _initialized = false;
  var _disposed = false;
  var _playerChangeNotificationScheduled = false;
  static const _sourceStartProgressWindow = Duration(seconds: 10);
  static const _outgoingSourcePositionTolerance = Duration(milliseconds: 500);

  /// How much forward progress below the expected start proves no seek is
  /// coming. Long enough that a source still on its way to a resumed position
  /// is never mistaken for one that started somewhere else.
  static const _staleExpectedStartProof = Duration(seconds: 2);
  Duration _pendingPlaybackStartPosition = Duration.zero;
  Duration _pendingSourceOutgoingPosition = Duration.zero;
  String? _pendingPlaybackStartSongId;
  bool _pendingSourceTransitionObserved = false;
  final List<StreamSubscription<dynamic>> _observableSubscriptions = [];
  VoidCallback? _heosListener;

  List<MediaItem> get displayQueue =>
      displayQueueFor(currentQueue, currentSongIndex.value);

  int realQueueIndexForDisplayIndex(int displayIndex) {
    return realQueueIndexForDisplayIndexIn(
      queueLength: currentQueue.length,
      currentIndex: currentSongIndex.value,
      displayIndex: displayIndex,
    );
  }

  static List<MediaItem> displayQueueFor(
    List<MediaItem> queue,
    int currentIndex,
  ) {
    if (!_isValidQueueIndex(queue.length, currentIndex)) {
      return List<MediaItem>.from(queue);
    }

    return <MediaItem>[
      ...queue.sublist(currentIndex),
      ...queue.sublist(0, currentIndex),
    ];
  }

  static int realQueueIndexForDisplayIndexIn({
    required int queueLength,
    required int currentIndex,
    required int displayIndex,
  }) {
    if (queueLength <= 0 || displayIndex < 0 || displayIndex >= queueLength) {
      return displayIndex;
    }
    if (currentIndex < 0 || currentIndex >= queueLength) {
      return displayIndex;
    }
    return (currentIndex + displayIndex) % queueLength;
  }

  static List<MediaItem> realQueueAfterDisplayReorder({
    required List<MediaItem> queue,
    required int currentIndex,
    required int oldDisplayIndex,
    required int newDisplayIndex,
  }) {
    if (!_isValidQueueIndex(queue.length, currentIndex)) {
      return List<MediaItem>.from(queue);
    }
    if (oldDisplayIndex < 0 ||
        oldDisplayIndex >= queue.length ||
        newDisplayIndex < 0 ||
        newDisplayIndex > queue.length) {
      return List<MediaItem>.from(queue);
    }

    final displayQueue = displayQueueFor(queue, currentIndex);
    var insertIndex = newDisplayIndex;
    if (oldDisplayIndex < insertIndex) {
      insertIndex--;
    }
    final movedItem = displayQueue.removeAt(oldDisplayIndex);
    displayQueue.insert(insertIndex, movedItem);

    final currentItem = queue[currentIndex];
    final displayCurrentIndex = displayQueue.indexWhere(
      (item) => item.id == currentItem.id,
    );
    if (displayCurrentIndex == -1) {
      return List<MediaItem>.from(queue);
    }

    final realQueue = List<MediaItem>.filled(queue.length, currentItem);
    for (
      var displayIndex = 0;
      displayIndex < displayQueue.length;
      displayIndex++
    ) {
      final realIndex =
          (currentIndex + displayIndex - displayCurrentIndex) % queue.length;
      realQueue[realIndex < 0 ? realIndex + queue.length : realIndex] =
          displayQueue[displayIndex];
    }
    return realQueue;
  }

  static bool _isValidQueueIndex(int queueLength, int index) =>
      queueLength > 0 && index >= 0 && index < queueLength;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _bindObservableState();
    await _init();
    if (RuntimePlatform.isWindows) {
      _windowsAudioService = WindowsAudioService(this);
    }
    await _restorePrevSession();
  }

  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);

  void _bindObservableState() {
    void watchValue<T>(ObservableValue<T> value) {
      _observableSubscriptions.add(value.listen((_) => _notifyPlayerChanged()));
    }

    void watchList<T>(ObservableList<T> value) {
      _observableSubscriptions.add(value.listen((_) => _notifyPlayerChanged()));
    }

    void watchMap<K, V>(ObservableMap<K, V> value) {
      _observableSubscriptions.add(value.listen((_) => _notifyPlayerChanged()));
    }

    watchList(currentQueue);
    watchValue(playerPaneOpacity);
    watchValue(playerPanelTopVisible);
    watchValue(playerPanelOpen);
    watchValue(playerPanelMinHeight);
    watchValue(isQueueReorderingInProcess);
    watchValue(timerDurationLeft);
    watchValue(isSleepTimerActive);
    watchValue(isSleepEndOfSongActive);
    watchValue(volume);
    watchValue(currentSongIndex);
    watchValue(isQueueLoopModeEnabled);
    watchValue(isLoopModeEnabled);
    watchValue(isShuffleModeEnabled);
    watchValue(currentSong);
    watchValue(isCurrentSongFav);
    watchValue(playingFrom);
    watchValue(showLyricsFlag);
    watchValue(isLyricsLoading);
    watchValue(lyricsMode);
    watchValue(gesturePlayerVisibleState);
    watchMap(lyrics);
    watchValue(buttonState);
    watchValue(isCurrentSongBuffered);
    _heosListener = _handleHeosStateChanged;
    heosCastController.addListener(_heosListener!);
  }

  void _notifyPlayerChanged() {
    if (_disposed || _playerChangeNotificationScheduled) return;
    _playerChangeNotificationScheduled = true;
    scheduleMicrotask(() {
      _playerChangeNotificationScheduled = false;
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  Future<void> _init() async {
    //_createAppDocDir();
    _listenForChangesInPlayerState();
    _listenForChangesInPosition();
    _listenForChangesInBufferedPosition();
    _listenForChangesInDuration();
    _listenForPlaylistChange();
    _listenForKeyboardActivity();
    _setInitLyricsMode();
    isLoopModeEnabled.value = _settingsRepository.getLoopModeEnabled();
    isShuffleModeEnabled.value = _settingsRepository.getShuffleModeEnabled();
    isQueueLoopModeEnabled.value = _settingsRepository
        .getQueueLoopModeEnabled();

    if (RuntimePlatform.isDesktop) {
      await setVolume(_settingsRepository.getVolume());
    }

    if (_settingsRepository.getPlayerUi() == 1) {
      initGesturePlayerStateAnimationController();
    }

    // only for android auto
    if (RuntimePlatform.isAndroid) {
      _listenForCustomEvents();
    }
  }

  void initGesturePlayerStateAnimationController() {
    gesturePlayerStateAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    gesturePlayerStateAnimation = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: gesturePlayerStateAnimationController!,
        curve: Curves.easeIn,
      ),
    );
  }

  void _setInitLyricsMode() {
    lyricsMode.value = _settingsRepository.getLyricsMode();
  }

  void panelListener(double x) {
    if (x >= 0 && x <= 0.2) {
      playerPaneOpacity.value = 1 - (x * 5);
      playerPanelTopVisible.value = true;
    } else if (x > 0.2) {
      playerPanelTopVisible.value = false;
    }

    // 0.6 threshold (not exact 1.0): the flag must flip while the panel is
    // clearly past halfway so dependent UI (nav bar) doesn't wait on the
    // animation landing exactly on the bound, and doesn't thrash mid-drag.
    if (x > 0.6) {
      playerPanelOpen.value = true;
    } else {
      playerPanelOpen.value = false;
    }
  }

  void _listenForKeyboardActivity() {
    var keyboardVisibilityController = KeyboardVisibilityController();
    keyboardSubscription = keyboardVisibilityController.onChange.listen((
      bool visible,
    ) async {
      visible
          ? await playerPanelController.hide()
          : await playerPanelController.show();
    });
  }

  void _listenForChangesInPlayerState() {
    final playerStateSubscription = _audioHandler.playbackState.listen((
      playerState,
    ) {
      if (_cloudRemoteStateActive) return;
      final isPlaying = playerState.playing;
      final processingState = playerState.processingState;
      _reflectExternalRepeatShuffleChanges(playerState);
      if (!_isWaitingForCurrentSourceStart &&
          isPlaying &&
          processingState == AudioProcessingState.buffering &&
          _isInsideSourceStartGuard(playerState.updatePosition)) {
        _restorePendingSourceStartFromGuard();
      }
      if (_isWaitingForCurrentSourceStart &&
          processingState != AudioProcessingState.ready) {
        _pendingSourceTransitionObserved = true;
      }
      // A playing source can briefly report ready at its requested position
      // before falling back to buffering. Only a real position tick proves it
      // started; clearing here would release the timer and rebuffer grace too
      // early. A restored paused source cannot produce such a tick, so it is
      // the one state-only transition that completes immediately.
      if (_isWaitingForCurrentSourceStart &&
          _isReadyPausedPendingSource(playerState)) {
        _clearPendingSourceStart();
      }
      if (processingState == AudioProcessingState.completed ||
          processingState == AudioProcessingState.error) {
        _clearPendingSourceStart();
        _clearSourceStartGuard();
      }

      final immediateLoading =
          _currentSongResolving ||
          processingState == AudioProcessingState.loading ||
          (_isWaitingForCurrentSourceStart &&
              processingState != AudioProcessingState.completed &&
              processingState != AudioProcessingState.error);
      if (immediateLoading) {
        _cancelBufferingGrace();
        _setButtonState(PlayButtonState.loading);
      } else if (processingState == AudioProcessingState.buffering) {
        _armBufferingGrace(isPlaying);
      } else {
        _cancelBufferingGrace();
        if (!isPlaying ||
            processingState == AudioProcessingState.error ||
            processingState == AudioProcessingState.completed) {
          _setButtonState(PlayButtonState.paused);
        } else {
          _setButtonState(PlayButtonState.playing);
        }
      }

      if (heosCastController.isConnected) {
        _setButtonState(
          heosCastController.isPlaying
              ? PlayButtonState.playing
              : PlayButtonState.paused,
        );
      }

      // Keep the screen awake whenever playback is active and the setting is enabled.
      final shouldEnable =
          _settingsController.keepScreenAwake.value && isPlaying;
      _setWakelock(shouldEnable);
      final shouldHoldPlaybackWakeLock =
          isPlaying &&
          processingState != AudioProcessingState.completed &&
          processingState != AudioProcessingState.error &&
          processingState != AudioProcessingState.idle;
      _setPlaybackWakeLock(shouldHoldPlaybackWakeLock);
    });
    _observableSubscriptions.add(playerStateSubscription);
  }

  /// Mirror repeat/shuffle changes made by external media controllers (car
  /// head units over Bluetooth/AVRCP, notification, Android Auto) into the UI
  /// observables so the icons stay truthful. Edge-detected: the BehaviorSubject
  /// replays an initial PlaybackState (repeatMode none) on subscribe, which
  /// must not clobber the settings-seeded values during startup.
  void _reflectExternalRepeatShuffleChanges(PlaybackState playerState) {
    final repeatMode = playerState.repeatMode;
    if (_lastSeenRepeatMode != null && repeatMode != _lastSeenRepeatMode) {
      final enabled = repeatMode != AudioServiceRepeatMode.none;
      if (isLoopModeEnabled.value != enabled) {
        isLoopModeEnabled.value = enabled;
      }
    }
    _lastSeenRepeatMode = repeatMode;

    final shuffleMode = playerState.shuffleMode;
    if (_lastSeenShuffleMode != null && shuffleMode != _lastSeenShuffleMode) {
      final enabled = shuffleMode != AudioServiceShuffleMode.none;
      if (isShuffleModeEnabled.value != enabled) {
        isShuffleModeEnabled.value = enabled;
        // Mirror the queue-loop coupling from toggleShuffleMode.
        if (enabled && !isQueueLoopModeEnabled.value) {
          isQueueLoopModeEnabled.value = true;
        } else if (!enabled) {
          isQueueLoopModeEnabled.value = _settingsRepository
              .getQueueLoopModeEnabled();
        }
      }
    }
    _lastSeenShuffleMode = shuffleMode;
  }

  void _setButtonState(PlayButtonState state) {
    if (buttonState.value == state) return;
    buttonState.value = state;
    _logSurface('button');
    _notifyPlayerChanged();
  }

  /// A seek or a restart on a cached song makes the engine dip into buffering
  /// for a few dozen milliseconds. Swapping the play icon for a spinner that
  /// fast reads as a glitch, so only a rebuffer that outlasts this window is
  /// worth telling the user about. Genuine loads bypass it.
  static const _bufferingSpinnerGrace = Duration(milliseconds: 350);
  Timer? _bufferingGraceTimer;

  void _armBufferingGrace(bool isPlaying) {
    if (buttonState.value == PlayButtonState.loading) return;
    // Set the button first, then arm: _setButtonState must never cancel the
    // grace timer, or arming would immediately kill its own timer.
    _setButtonState(
      isPlaying ? PlayButtonState.playing : PlayButtonState.paused,
    );
    if (_bufferingGraceTimer != null) return; // one shot per buffering episode
    _bufferingGraceTimer = Timer(_bufferingSpinnerGrace, () {
      _bufferingGraceTimer = null;
      if (_disposed || _cloudRemoteStateActive) return;
      if (_audioHandler.playbackState.value.processingState ==
          AudioProcessingState.buffering) {
        _setButtonState(PlayButtonState.loading);
      }
    });
  }

  void _cancelBufferingGrace() {
    _bufferingGraceTimer?.cancel();
    _bufferingGraceTimer = null;
  }

  /// Dumps every input that decides whether the title/artist render as text or
  /// as shimmer. Diagnosing this from the outside kept failing because the two
  /// causes look identical on screen: a song we never resolved, and a resolved
  /// song whose play button is stuck on loading. Deduped, so it only prints
  /// when something actually changes.
  void _logSurface(String reason) {
    final song = currentSong.value;
    // The handler's own view, not the controller's. Reading a spinner that
    // vanishes early means asking which position tick cleared the pending
    // start and what the player claimed at that moment — none of which was
    // recorded, so a report of "loading is wrong" could not be answered
    // without a second reproduction.
    final playback = _audioHandler.playbackState.value;
    final line =
        'surface[$reason] loading=$isCurrentSongLoading '
        'button=${buttonState.value.name} '
        'procState=${playback.processingState.name} '
        'playerPlaying=${playback.playing} '
        'updatePos=${playback.updatePosition.inMilliseconds} '
        'song=${song?.id} title="${song?.title}" artist="${song?.artist}" '
        'resolvingItem=${song == null ? null : MediaItemBuilder.isResolving(song)} '
        'resolvingFlag=$_currentSongResolving '
        'pendingStart=$_pendingPlaybackStartSongId '
        'waitingStart=$_isWaitingForCurrentSourceStart '
        'transitionSeen=$_pendingSourceTransitionObserved '
        'startFrom=${_pendingPlaybackStartPosition.inMilliseconds} '
        'mirroring=$_cloudRemoteStateActive '
        'pendingRemote=$_pendingRemoteSongId '
        'queue=${currentQueue.length} index=${currentSongIndex.value}';
    if (line == _lastSurfaceLine) return;
    _lastSurfaceLine = line;
    printINFO(line, tag: LogTags.cloudPlayback);
  }

  String? _lastSurfaceLine;

  void _setWakelock(bool enable) {
    if (_wakelockActive == enable) return; // no-op if already in desired state

    try {
      if (enable) {
        printINFO("Enabling wakelock", tag: LogTags.player);
        unawaited(AppPlatformService.setKeepScreenAwake(true));
        _wakelockActive = true;
      } else {
        printINFO("Disabling wakelock", tag: LogTags.player);
        unawaited(AppPlatformService.setKeepScreenAwake(false));
        _wakelockActive = false;
      }
    } catch (e) {
      printERROR(e, tag: LogTags.player);
    }
  }

  void _setPlaybackWakeLock(bool enable) {
    if (_playbackWakeLockActive == enable) return;

    try {
      unawaited(AppPlatformService.setPlaybackWakeLock(enable));
      _playbackWakeLockActive = enable;
    } catch (e) {
      printERROR(e, tag: LogTags.player);
    }
  }

  void _listenForChangesInPosition() {
    final positionSubscription = AudioService.position.listen((position) {
      if (_cloudRemoteStateActive) return;
      // Android can keep emitting the previous just_audio source's position
      // while an incoming cloud song is still resolving. The placeholder has
      // already reset the bar; do not let those stale ticks move it again.
      if (_currentSongResolving) return;
      if (_isWaitingForCurrentSourceStart) {
        final playbackState = _audioHandler.playbackState.value;
        if (!_isReadySourceStart(playbackState) ||
            !_isSourceStartPosition(position) ||
            !_hasSourcePlaybackProgress(position)) {
          // A tick arrived and was refused. Counting them separates a spinner
          // stuck because no position ever ticked from one stuck because every
          // tick failed a condition - identical from the outside, opposite
          // causes. Logged once per second so a pinned spinner is explained
          // without drowning the log at tick rate.
          _sourceStartTicksSeen++;
          _sourceStartLastRejectedPosition = position;
          _abandonStaleExpectedStart(playbackState, position);
          final now = DateTime.now();
          final last = _sourceStartLastRejectionLoggedAt;
          if (last == null ||
              now.difference(last) >= const Duration(seconds: 1)) {
            _sourceStartLastRejectionLoggedAt = now;
            printINFO(
              'sourceStart tick rejected pos=${position.inMilliseconds} '
              'expected=${_pendingPlaybackStartPosition.inMilliseconds} '
              'ready=${_isReadySourceStart(playbackState)} '
              'inWindow=${_isSourceStartPosition(position)} '
              'advanced=${_hasSourcePlaybackProgress(position)} '
              'procState=${playbackState.processingState.name} '
              'playerPlaying=${playbackState.playing} '
              'updatePos=${playbackState.updatePosition.inMilliseconds} '
              'ticks=$_sourceStartTicksSeen song=${currentSong.value?.id}',
              tag: LogTags.cloudPlayback,
            );
          }
          return;
        }
        // This is where the spinner ends. Its three conditions are loose for a
        // fresh tap — the expected start is zero, so any tick under ten seconds
        // satisfies the position checks, and `transitionSeen` is set by *any*
        // non-ready state including the `idle` left by tearing down the
        // previous source. A tick belonging to the old source can therefore end
        // the spinner while the new song is still resolving. Recording the tick
        // that did it is what tells the two cases apart.
        printINFO(
          'sourceStart cleared by tick pos=${position.inMilliseconds} '
          'expected=${_pendingPlaybackStartPosition.inMilliseconds} '
          'procState=${playbackState.processingState.name} '
          'playerPlaying=${playbackState.playing} '
          'updatePos=${playbackState.updatePosition.inMilliseconds} '
          'song=${currentSong.value?.id}',
          tag: LogTags.cloudPlayback,
        );
        _clearPendingSourceStart();
        _setButtonState(PlayButtonState.playing);
      }
      _clearSourceStartGuardIfPast(position);
      final oldState = progressBarStatus.value;
      final clampedPosition = _clampProgressPosition(position, oldState.total);
      if (isSleepEndOfSongActive.value) {
        timerDurationLeft.value =
            oldState.total.inSeconds - clampedPosition.inSeconds;
        if (timerDurationLeft.value == 1) {
          requestPause();
          cancelSleepTimer();
        }
      }
      progressBarStatus.update((val) {
        val.current = clampedPosition;
        val.buffered = oldState.buffered;
        val.total = oldState.total;
      });
      lyricController.setProgress(clampedPosition);
    });
    _observableSubscriptions.add(positionSubscription);
  }

  void _listenForChangesInBufferedPosition() {
    final bufferedPositionSubscription = _audioHandler.playbackState.listen((
      playbackState,
    ) async {
      if (_cloudRemoteStateActive) return;
      if (_currentSongResolving) return;
      final oldState = progressBarStatus.value;
      // Loading/buffer events may contain an extrapolated position for a source
      // that has not produced audio yet. The position stream is the sole owner
      // of completing a playing source transition.
      if (_isWaitingForCurrentSourceStart) return;

      final currentPosition = oldState.current;
      final bufferedPosition = _clampProgressPosition(
        playbackState.bufferedPosition,
        oldState.total,
      );
      progressBarStatus.update((val) {
        val.buffered = bufferedPosition;
        val.current = currentPosition;
        val.total = oldState.total;
      });

      if (progressBarStatus.value.total.inSeconds != 0 &&
          playbackState.bufferedPosition.inSeconds /
                  progressBarStatus.value.total.inSeconds >=
              0.98) {
        if (_newSongFlag) {
          await _audioHandler.customAction("checkWithCacheDb", {
            'mediaItem': currentSong.value!,
          });
          _newSongFlag = false;
        }
      }
    });
    _observableSubscriptions.add(bufferedPositionSubscription);
  }

  void _listenForChangesInDuration() {
    final mediaItemSubscription = _audioHandler.mediaItem.listen((
      mediaItem,
    ) async {
      // While mirroring a remote target this device's own handler is idle; any
      // event from it would overwrite the mirrored song and zero the bar.
      if (_cloudRemoteStateActive) return;
      if (mediaItem == null || !isDisplayableSong(mediaItem)) {
        currentSong.value = null;
        _clearPendingSourceStart();
        _clearSourceStartGuard();
        progressBarStatus.update((val) {
          val.total = Duration.zero;
          val.current = Duration.zero;
          val.buffered = Duration.zero;
        });
        _notifyPlayerChanged();
        return;
      }

      final previousSongId = currentSong.value?.id;
      final isSameSong = previousSongId == mediaItem.id;
      // Where the source being replaced stopped. Captured before the new
      // item lands, because the old source keeps reporting this position
      // until the new one is actually installed.
      final outgoingPosition = progressBarStatus.value.current;
      printINFO(mediaItem.title, tag: LogTags.player);
      _newSongFlag = true;
      isCurrentSongBuffered.value = false;
      // The audio target installs a placeholder for the handed-off song before
      // resolving it, so the handler's real item arrives under an id we already
      // hold. Assigning it must not be swallowed as "no change".
      currentSong.overwrite(mediaItem);
      _logSurface('handler');
      currentSongIndex.value = currentQueue.indexWhere(
        (element) => element.id == currentSong.value!.id,
      );
      if (!isSameSong) {
        _beginPendingSourceStart(
          mediaItem.id,
          outgoingPosition: outgoingPosition,
        );
      }
      final nextTotal = mediaItem.duration ?? Duration.zero;
      progressBarStatus.update((val) {
        // A same-song rebroadcast (e.g. shuffle rewriting the queue) can carry
        // a stale item without a duration — keep the known total instead of
        // collapsing it to zero, which would pin the progress bar at 0:00.
        val.total = nextTotal > Duration.zero
            ? nextTotal
            : (isSameSong ? val.total : Duration.zero);
        val.current = isSameSong
            ? _clampProgressPosition(val.current, val.total)
            : Duration.zero;
        val.buffered = isSameSong
            ? _clampProgressPosition(val.buffered, val.total)
            : Duration.zero;
      });
      // Coalesced: the observable writes above already scheduled a
      // microtask notification via _notifyPlayerChanged; a direct
      // notifyListeners() here would rebuild every listener twice per song
      // change (a visible hitch on next/prev).
      _notifyPlayerChanged();
      if (!isSameSong) {
        _clearLyricsForSongChange();
      }
      final appContext = AppNavigator.context;
      if (isDesktopLyricsDialogOpen && appContext != null) {
        Navigator.pop(appContext);
      }

      // reset player visible state when player is in gesture mode
      if (_settingsController.playerUi.value == 1) {
        gesturePlayerVisibleState.value = 2;
      }

      unawaited(_updateCurrentSongSideEffects(mediaItem));
    });
    _observableSubscriptions.add(mediaItemSubscription);
  }

  Duration _clampProgressPosition(Duration position, Duration total) {
    if (position < Duration.zero) return Duration.zero;
    if (total > Duration.zero && position > total) return total;
    return position;
  }

  bool get _isWaitingForCurrentSourceStart =>
      _pendingPlaybackStartSongId != null &&
      _pendingPlaybackStartSongId == currentSong.value?.id;

  /// Whether the player has landed where this source was asked to start.
  ///
  /// Measured against the *expected* start, not against zero. A cloud handoff
  /// resumes mid-track — hand a song over 59s in and the target correctly seeks
  /// to 0:59, which a "must be near zero" test reads as "the source never
  /// started". The pending start then never cleared, pinning the play button on
  /// loading, and with it the title and artist shimmer — on a song that was
  /// fully resolved and audibly playing. Skipping to another track cleared it
  /// only because that one does start at zero.
  bool _isSourceStartPosition(Duration position) {
    return (position - _pendingPlaybackStartPosition).abs() <=
        _sourceStartProgressWindow;
  }

  bool _hasSourcePlaybackProgress(Duration position) {
    return position > _pendingPlaybackStartPosition;
  }

  bool _isReadySourceStart(PlaybackState playbackState) {
    return _pendingSourceTransitionObserved &&
        playbackState.processingState == AudioProcessingState.ready &&
        playbackState.playing &&
        _isSourceStartPosition(playbackState.updatePosition);
  }

  /// Session restoration prepares a source and seeks to its saved position
  /// without automatically resuming. That is a completed transition, not a
  /// loading state, even though it is paused and no longer near zero.
  bool _isReadyPausedPendingSource(PlaybackState playbackState) {
    return _pendingSourceTransitionObserved &&
        playbackState.processingState == AudioProcessingState.ready &&
        !playbackState.playing &&
        !_isOutgoingSourcePosition(playbackState.updatePosition);
  }

  /// Whether a ready-paused report still belongs to the source being
  /// replaced rather than to the pending one.
  ///
  /// Tapping a song while another is paused leaves the old source loaded and
  /// still reporting ready-paused at its own position, seconds before the new
  /// source is installed. Treating that as the pending source having landed
  /// clears the pending start and drops the button to paused for the whole
  /// resolve - the "player stopped" seen while a song is plainly loading.
  ///
  /// Zero is exempt: a restore that legitimately prepares at zero would
  /// otherwise never clear and would pin the button on loading instead.
  bool _isOutgoingSourcePosition(Duration position) {
    if (_pendingSourceOutgoingPosition <= Duration.zero) return false;
    return (position - _pendingSourceOutgoingPosition).abs() <=
        _outgoingSourcePositionTolerance;
  }

  void _beginPendingSourceStart(
    String songId, {
    Duration outgoingPosition = Duration.zero,
  }) {
    _pendingPlaybackStartSongId = songId;
    _pendingSourceTransitionObserved = false;
    _pendingSourceOutgoingPosition = outgoingPosition;
    _sourceStartTicksSeen = 0;
    _sourceStartLastRejectedPosition = null;
    _sourceStartLastRejectionLoggedAt = null;
    _sourceStartFirstObservedPosition = null;
    // Zero unless something told us this source resumes elsewhere.
    _pendingPlaybackStartPosition =
        _expectedSourceStartPosition ?? Duration.zero;
    _sourceStartGuardSongId = songId;
    _sourceStartGuardPosition = _pendingPlaybackStartPosition;
    _setButtonState(PlayButtonState.loading);
  }

  bool _isInsideSourceStartGuard(Duration position) {
    if (_sourceStartGuardSongId != currentSong.value?.id) return false;
    final progress = position - _sourceStartGuardPosition;
    return progress >= Duration.zero && progress <= _sourceStartProgressWindow;
  }

  void _restorePendingSourceStartFromGuard() {
    final songId = _sourceStartGuardSongId;
    if (songId == null || songId != currentSong.value?.id) return;
    _pendingPlaybackStartSongId = songId;
    _pendingSourceTransitionObserved = true;
    _pendingPlaybackStartPosition = _sourceStartGuardPosition;
    progressBarStatus.update((value) {
      value.current = _sourceStartGuardPosition;
      value.buffered = _sourceStartGuardPosition;
    });
    lyricController.setProgress(_sourceStartGuardPosition);
    _cancelBufferingGrace();
    _setButtonState(PlayButtonState.loading);
  }

  void _clearSourceStartGuardIfPast(Duration position) {
    if (_sourceStartGuardSongId != currentSong.value?.id) return;
    if (position - _sourceStartGuardPosition <= _sourceStartProgressWindow) {
      return;
    }
    _clearSourceStartGuard();
  }

  void _clearSourceStartGuard() {
    _sourceStartGuardSongId = null;
    _sourceStartGuardPosition = Duration.zero;
  }

  /// Moves the goalposts when the user seeks before the source ever reported
  /// its first ready frame. The start is now measured from where the thumb was
  /// dropped, not from zero — otherwise [_isSourceStartPosition] can never be
  /// satisfied, the pending start never clears, and the play button stays
  /// pinned on loading with the progress bar frozen for the rest of the track.
  /// Gives up on an expected start the source is never going to reach.
  ///
  /// The expected start outlives whatever set it: a cancelled handoff leaves
  /// "resume at 26.7s" behind while the source restarts from zero. Both
  /// position conditions then fail forever - the position is below the expected
  /// start, and too far from it to be inside the window - so the spinner stays
  /// up until playback organically reaches that mark, or for the whole track if
  /// it never does. The audio is fine throughout; only the UI is stuck.
  ///
  /// Sustained forward progress below the expected start is proof the seek is
  /// not coming, so move the goalposts to where the source actually is. A
  /// source still on its way to a resumed position has not played [
  /// _staleExpectedStartProof] worth of audio short of it, so it is unaffected.
  void _abandonStaleExpectedStart(
    PlaybackState playbackState,
    Duration position,
  ) {
    if (playbackState.processingState != AudioProcessingState.ready ||
        !playbackState.playing ||
        position >= _pendingPlaybackStartPosition) {
      return;
    }
    final firstSeen = _sourceStartFirstObservedPosition;
    // A position below the anchor is a different source, not progress.
    if (firstSeen == null || position < firstSeen) {
      _sourceStartFirstObservedPosition = position;
      return;
    }
    if (position - firstSeen < _staleExpectedStartProof) return;
    printINFO(
      'sourceStart abandoning unreachable expected start '
      'expected=${_pendingPlaybackStartPosition.inMilliseconds} '
      'pos=${position.inMilliseconds} '
      'ticks=$_sourceStartTicksSeen song=${currentSong.value?.id}',
      tag: LogTags.cloudPlayback,
    );
    _retargetPendingSourceStart(position);
  }

  void _retargetPendingSourceStart(Duration position) {
    if (!_isWaitingForCurrentSourceStart) return;
    _pendingPlaybackStartPosition = position;
    _expectedSourceStartPosition = position;
    _sourceStartGuardPosition = position;
  }

  int _sourceStartTicksSeen = 0;
  Duration? _sourceStartLastRejectedPosition;
  DateTime? _sourceStartLastRejectionLoggedAt;
  Duration? _sourceStartFirstObservedPosition;

  void _clearPendingSourceStart() {
    _sourceStartTicksSeen = 0;
    _sourceStartLastRejectedPosition = null;
    _sourceStartLastRejectionLoggedAt = null;
    _sourceStartFirstObservedPosition = null;
    _pendingPlaybackStartSongId = null;
    _pendingSourceTransitionObserved = false;
    _pendingPlaybackStartPosition = Duration.zero;
    _pendingSourceOutgoingPosition = Duration.zero;
    _expectedSourceStartPosition = null;
  }

  /// Where the next source is expected to begin, when that is known before the
  /// audio handler reports the song. Only a resumed source sets this; a normal
  /// tap starts at zero and leaves it null.
  Duration? _expectedSourceStartPosition;
  String? _sourceStartGuardSongId;
  Duration _sourceStartGuardPosition = Duration.zero;

  Future<void> _updateCurrentSongSideEffects(MediaItem mediaItem) async {
    await _checkFavFor(mediaItem);
    await _addToRP(mediaItem);
    await _backfillLibraryDuration(mediaItem);
    if (currentSong.value?.id == mediaItem.id &&
        isRadioModeOn &&
        currentQueue.isNotEmpty &&
        mediaItem.id == currentQueue.last.id) {
      await _addRadioContinuation(radioInitiatorItem!);
    }
  }

  /// Some sources add a song to the library with no duration; the real
  /// value only arrives once playback resolves the audio source. Persist it
  /// then (and patch the on-screen list) so the library stops showing a
  /// blank duration for that track.
  Future<void> _backfillLibraryDuration(MediaItem mediaItem) async {
    final duration = mediaItem.duration;
    if (duration == null || duration <= Duration.zero) return;
    await _libraryRepository.backfillSongDuration(mediaItem.id, duration);
    LibrarySongsControllerRegistry.current?.applyResolvedDuration(
      mediaItem.id,
      duration,
    );
  }

  void _listenForPlaylistChange() {
    final queueSubscription = _audioHandler.queue.listen((queue) {
      // Same reason as _listenForChangesInDuration: a local queue event would
      // replace the mirrored remote queue with this device's idle one.
      if (_cloudRemoteStateActive) return;
      currentQueue.value = queue;
      currentQueue.refresh();
      final song = currentSong.value;
      if (song != null) {
        currentSongIndex.value = queue.indexWhere(
          (element) => element.id == song.id,
        );
      }
      _notifyPlayerChanged();
    });
    _observableSubscriptions.add(queueSubscription);
  }

  Future<void> _restorePrevSession() async {
    final restorePrevSessionEnabled = _settingsRepository
        .getRestorePlaybackSession();
    if (restorePrevSessionEnabled) {
      final songList = await _playbackSessionRepository.getQueue();
      final currentIndex = await _playbackSessionRepository.getIndex();
      final position = await _playbackSessionRepository.getPosition();
      if (songList.isNotEmpty && currentIndex != null && position != null) {
        await _playbackCommands.addQueueItems(songList);
        await _playerPanelCheck(restoreSession: true);
        await _playbackCommands.playByIndex(
          currentIndex,
          position: position,
          restoreSession: true,
        );
      }
    }
  }

  void _listenForCustomEvents() {
    final customEventSubscription = _audioHandler.customEvent.listen((
      event,
    ) async {
      if (event['eventType'] == 'playFromMediaId') {
        await _playViaAndroidAuto(event['songId'], event['libraryId']);
      } else if (event['eventType'] == 'playError') {
        notifyPlayError(event['message'] as String? ?? 'networkError');
      } else if (event['eventType'] == 'remoteNotificationCommand' &&
          _cloudRemoteStateActive) {
        switch (event['action']) {
          case 'play':
            await play();
          case 'pause':
            await pause();
          case 'next':
            await next();
          case 'previous':
            await prev();
          case 'seek':
            await seek(
              Duration(
                milliseconds: (event['positionMs'] as num?)?.toInt() ?? 0,
              ),
            );
        }
      }
    });
    _observableSubscriptions.add(customEventSubscription);
  }

  ///pushSongToPlaylist method clear previous song queue, plays the tapped song and push related
  ///songs into Queue
  Future<void> pushSongToQueue(
    MediaItem? mediaItem, {
    String? playlistId,
    bool radio = false,
  }) async {
    // A guest's "play now" would otherwise replace the host's queue. Treat a
    // concrete song as a request instead; radio/playlist-id expansion remains
    // host-controlled because it cannot be represented as one safe song.
    if (_isSessionGuest) {
      if (mediaItem == null) {
        _showSessionUnavailableSnackbar();
        return;
      }
      _routeToHost(SessionCommand.enqueue(sessionSafeSongJson(mediaItem)));
      _showAddedToSharedQueueSnackbar();
      return;
    }

    // Expanding a selection into its watch queue is a network request. A
    // searched song can therefore finish after a newer Recently Played tap and
    // otherwise send its queue/handoff last, making the older song win. Every
    // play-now intent claims a generation before starting any asynchronous
    // work; late results are discarded before they can mutate either player.
    final selectionGeneration = ++_playNowSelectionGeneration;

    /// update playing from value
    playingFrom.value = PlayingFrom(type: PlayingFromType.SELECTION, name: '');

    /// set global radio mode flag
    isRadioModeOn = radio;

    final queueUpdate = Future<List<MediaItem>?>.delayed(Duration.zero, () async {
      isQueueExpanding.value = true;
      try {
        final content = await _fetchWatchQueue(
          videoId: mediaItem?.id ?? "",
          radio: radio,
          playlistId: playlistId,
          selectionGeneration: selectionGeneration,
        );
        if (content == null ||
            selectionGeneration != _playNowSelectionGeneration) {
          return null;
        }
        radioContinuationParam = content['additionalParamsForNext'];
        final tracks = List<MediaItem>.from(content['tracks'] ?? const []);
        // An empty expansion is not worth clobbering the playing song's
        // placeholder queue with — that would leave the user with nothing.
        if (tracks.isEmpty) return null;
        await _playbackCommands.updateQueue(tracks);
        if (selectionGeneration != _playNowSelectionGeneration) return null;
        if (isShuffleModeEnabled.value) {
          await _playbackCommands.shuffleFromIndex(0);
        }

        // added here to broadcast current mediaItem via Audio Service as list is updated
        // if radio is started on current playing song
        if (radio && (currentSong.value?.id == mediaItem?.id)) {
          await _audioHandler.customAction("updateMediaItemInAudioService", {
            "index": 0,
          });
        }
        return tracks;
      } catch (error, stackTrace) {
        // Nothing downstream awaits this on the local path — it is consumed by
        // an `unawaited(...then(...))` — so an escaping error became an
        // unhandled async error and left the queue at the one placeholder song
        // with no trace of why.
        printERROR(
          'queue expansion failed for ${mediaItem?.id}: $error',
          tag: LogTags.player,
        );
        printERROR(stackTrace, tag: LogTags.player);
        return null;
      } finally {
        // A newer selection owns the indicator from the moment it claims a
        // generation; clearing it here would hide that one's progress.
        if (selectionGeneration == _playNowSelectionGeneration) {
          isQueueExpanding.value = false;
        }
      }
    });

    if (playlistId != null) {
      unawaited(_playerPanelCheck());
      final tracks = await queueUpdate;
      if (tracks == null ||
          selectionGeneration != _playNowSelectionGeneration) {
        return;
      }
      await _playbackCommands.playByIndex(0);
      return;
    }

    unawaited(
      queueUpdate.then((value) async {
        if (value == null ||
            selectionGeneration != _playNowSelectionGeneration) {
          return;
        }
        if (_settingsRepository.getDiscoverContentType() == "BOLI") {
          await _homeScreenController.changeDiscoverContent(
            "BOLI",
            songId: mediaItem!.id,
          );
        }
      }),
    );

    if (radio && (currentSong.value?.id == mediaItem?.id)) {
      return;
    }

    var transitionQueue = <MediaItem>[mediaItem!];
    var transitionIndex = 0;
    if (_playbackCommands.isRemoteControlActive) {
      final remoteQueue = await queueUpdate;
      if (remoteQueue == null ||
          selectionGeneration != _playNowSelectionGeneration) {
        return;
      }
      final remoteIndex = remoteQueue.indexWhere(
        (item) => item.id == mediaItem.id,
      );
      if (remoteIndex >= 0) {
        transitionQueue = remoteQueue;
        transitionIndex = remoteIndex;
      }
    }
    final remoteTransition = beginRemoteSongTransition(
      transitionQueue,
      transitionIndex,
    );
    try {
      unawaited(_playerPanelCheck());
      if (heosCastController.isConnected) {
        await _playbackCommands.updateQueue([mediaItem]);
        await _playQueueIndex(0);
      } else {
        await _playbackCommands.setSourceAndPlay(mediaItem);
      }
    } catch (_) {
      failRemoteSongTransition(remoteTransition);
      rethrow;
    }

    // disable queue loop mode when radio is started
    if (radio && isQueueLoopModeEnabled.value && !isShuffleModeEnabled.value) {
      await toggleQueueLoopMode();
    }
  }

  Future<void> playPlayListSong(
    List<MediaItem> mediaItems,
    int index, {
    PlayingFrom? playFrom,
  }) async {
    // A guest cannot safely replace the shared queue or play a local index.
    // Request the selected song as an append on the host instead.
    if (_isSessionGuest) {
      if (index < 0 || index >= mediaItems.length) return;
      _routeToHost(
        SessionCommand.enqueue(sessionSafeSongJson(mediaItems[index])),
      );
      _showAddedToSharedQueueSnackbar();
      return;
    }

    // A playlist/album tap also supersedes any standalone selection whose
    // watch-queue lookup is still running.
    _playNowSelectionGeneration++;
    // This queue arrives whole, so any expansion still running for an earlier
    // tap is both superseded and no longer worth indicating. Its own `finally`
    // deliberately will not clear the flag once outranked, so the new owner has
    // to.
    isQueueExpanding.value = false;
    isRadioModeOn = false;
    //open player pane,set current song and push first song into playing list,

    /// update playing from value
    playingFrom.value =
        playFrom ?? PlayingFrom(type: PlayingFromType.SELECTION);

    //for changing home content based on last iteration
    unawaited(
      Future.delayed(const Duration(seconds: 3), () async {
        if (_settingsRepository.getDiscoverContentType() == "BOLI") {
          await _homeScreenController.changeDiscoverContent(
            "BOLI",
            songId: mediaItems[index].id,
          );
        }
      }),
    );

    final remoteTransition = beginRemoteSongTransition(mediaItems, index);
    try {
      await _playerPanelCheck();
      await _playbackCommands.updateQueue(mediaItems);
      if (isShuffleModeEnabled.value) {
        await _playbackCommands.shuffleFromIndex(index);
        await _playQueueIndex(0);
        return;
      }
      await _playQueueIndex(index);
    } catch (_) {
      failRemoteSongTransition(remoteTransition);
      rethrow;
    }
  }

  Future<void> _playQueueIndex(int index) async {
    if (!heosCastController.isConnected) {
      await _playbackCommands.playByIndex(index);
      return;
    }
    await _castQueueIndex(index);
  }

  Future<void> _castQueueIndex(int index) async {
    if (currentQueue.isEmpty || index < 0 || index >= currentQueue.length) {
      return;
    }
    final song = currentQueue[index];
    currentSong.value = song;
    currentSongIndex.value = index;
    await _audioHandler.customAction("updateMediaItemInAudioService", {
      "index": index,
    });
    await heosCastController.cast(song);
    _markHeosPlaybackStarted(song);
  }

  void _markHeosPlaybackStarted(MediaItem song) {
    _clearPendingSourceStart();
    currentSong.value = song;
    currentSongIndex.value = currentQueue.indexWhere(
      (element) => element.id == song.id,
    );
    progressBarStatus.update((value) {
      value.current = Duration.zero;
      value.buffered = Duration.zero;
      value.total = song.duration ?? value.total;
    });
    _setButtonState(PlayButtonState.playing);
    unawaited(_updateCurrentSongSideEffects(song));
  }

  void _handleHeosStateChanged() {
    if (heosCastController.isConnected) {
      _setButtonState(
        heosCastController.isPlaying
            ? PlayButtonState.playing
            : PlayButtonState.paused,
      );
    }
    _notifyPlayerChanged();
  }

  int _nextQueueIndexForHeos() {
    if (currentQueue.isEmpty) return currentSongIndex.value;
    final currentIndex = currentSongIndex.value;
    if (currentIndex < currentQueue.length - 1) return currentIndex + 1;
    return isQueueLoopModeEnabled.value ? 0 : currentIndex;
  }

  int _previousQueueIndexForHeos() {
    if (currentQueue.isEmpty) return currentSongIndex.value;
    final currentIndex = currentSongIndex.value;
    if (currentIndex > 0) return currentIndex - 1;
    return isQueueLoopModeEnabled.value
        ? currentQueue.length - 1
        : currentIndex;
  }

  Future<void> startRadio(MediaItem? mediaItem, {String? playlistId}) async {
    radioInitiatorItem = mediaItem ?? playlistId;
    await pushSongToQueue(mediaItem, playlistId: playlistId, radio: true);
  }

  /// How many times a tap's queue expansion is attempted before giving up.
  static const _queueExpansionAttempts = 5;

  /// Whether a failed watch-queue lookup could plausibly succeed if tried again.
  ///
  /// Only the ones that never reached a usable response: a request that did not
  /// complete. Everything else means the document arrived and the parser choked
  /// on it, which no amount of retrying changes.
  static bool _isTransientLookupFailure(Object error) =>
      error is DioException ||
      error is SocketException ||
      error is TimeoutException;

  /// Fetches the watch playlist that turns a single tap into a real queue,
  /// retrying with backoff instead of surrendering on the first failure.
  ///
  /// This is one network request against an endpoint returning a large,
  /// frequently changing document, so it fails often enough to matter. It used
  /// to be issued exactly once with no error handling at all: a blip left
  /// `setSourceNPlay`'s placeholder single-song queue in place, the tapped song
  /// played normally, and nothing anywhere said the queue had not filled.
  ///
  /// Returns null when every attempt failed or a newer selection superseded
  /// this one — a retry loop must never outlive the tap that started it, or it
  /// would eventually overwrite a queue the user has since chosen.
  Future<Map<String, dynamic>?> _fetchWatchQueue({
    required String videoId,
    required String? playlistId,
    required bool radio,
    required int selectionGeneration,
  }) async {
    var backoff = const Duration(seconds: 1);
    for (var attempt = 1; attempt <= _queueExpansionAttempts; attempt++) {
      if (_disposed || selectionGeneration != _playNowSelectionGeneration) {
        return null;
      }
      try {
        return await _musicServices.getWatchPlaylist(
          videoId: videoId,
          radio: radio,
          playlistId: playlistId,
        );
      } catch (error, stackTrace) {
        // A response we already received and could not parse will parse exactly
        // the same way on every retry. Backing off five times over fifteen
        // seconds only makes the user watch a progress indicator promise
        // something that is never coming.
        final retryable = _isTransientLookupFailure(error);
        printERROR(
          'watch queue lookup failed for $videoId '
          '${retryable ? '(attempt $attempt of $_queueExpansionAttempts)' : '(not retryable)'}'
          ': $error',
          tag: LogTags.player,
        );
        if (!retryable || attempt == _queueExpansionAttempts) {
          printERROR(stackTrace, tag: LogTags.player);
          return null;
        }
        await Future<void>.delayed(backoff);
        backoff *= 2;
      }
    }
    return null;
  }

  Future<void> _addRadioContinuation(dynamic item) async {
    if (_isSessionGuest) return;
    final isSong = item.runtimeType.toString() == "MediaItem";
    final content = await _musicServices.getWatchPlaylist(
      videoId: isSong ? item.id : "",
      radio: true,
      limit: 24,
      playlistId: isSong ? null : item,
      additionalParamsNext: radioContinuationParam,
    );
    radioContinuationParam = content['additionalParamsForNext'];
    await enqueueSongList(List<MediaItem>.from(content['tracks']));
  }

  ///enqueueSong   append a song to current queue
  ///if current queue is empty, push the song into Queue and play that song
  Future<void> enqueueSong(MediaItem mediaItem) async {
    if (_routeToHost(SessionCommand.enqueue(sessionSafeSongJson(mediaItem)))) {
      return;
    }
    if (currentQueue.isEmpty) {
      await playPlayListSong([mediaItem], 0);
      return;
    }
    //check if song is available in queue and if not add it to queue
    if (!currentQueue.contains(mediaItem)) {
      await _playbackCommands.addQueueItem(mediaItem);
    }
  }

  ///enqueueSongList method add song List to current queue
  Future<void> enqueueSongList(List<MediaItem> mediaItems) async {
    if (_isSessionGuest) {
      for (final chunk in chunkList(mediaItems, 50)) {
        _routeToHost(
          SessionCommand.enqueueList(chunk.map(sessionSafeSongJson).toList()),
        );
      }
      return;
    }
    if (currentQueue.isEmpty) {
      await playPlayListSong(mediaItems, 0);
      return;
    }
    final listToEnqueue = <MediaItem>[];
    for (MediaItem item in mediaItems) {
      if (!currentQueue.contains(item)) {
        listToEnqueue.add(item);
      }
    }
    await _playbackCommands.addQueueItems(listToEnqueue);
  }

  Future<void> _playViaAndroidAuto(String songId, String libraryId) async {
    final songList = switch (libraryId) {
      BoxNames.songDownloads => await _libraryRepository.getDownloadedSongs(),
      BoxNames.songsCache => await _libraryRepository.getCachedSongs(),
      BoxNames.libFav => await _libraryRepository.getFavoriteSongs(),
      BoxNames.libFavNotDownloaded =>
        await _libraryRepository.getFavoriteNotDownloadedSongs(),
      BoxNames.libImportDuplicates =>
        await _libraryRepository.getImportDuplicateSongs(),
      BoxNames.libImportReview =>
        await _libraryRepository.getImportReviewSongs(),
      BoxNames.libRP => await _libraryRepository.getRecentlyPlayedSongs(),
      _ => <MediaItem>[],
    };
    final songIndex = songList.indexWhere((song) => song.id == songId);
    await playPlayListSong(songList, songIndex < 0 ? 0 : songIndex);
  }

  Future<void> playNext(MediaItem song) async {
    if (_routeToHost(SessionCommand.playNextSong(sessionSafeSongJson(song)))) {
      return;
    }
    if (currentQueue.isEmpty) {
      await enqueueSong(song);
      return;
    }
    int index = -1;
    for (int i = 0; i < currentQueue.length; i++) {
      if (song.id == currentQueue[i].id) {
        index = i;
        break;
      }
    }
    final currentIndex = currentSongIndex.value;
    if (index == currentIndex) {
      return;
    }
    if (index != -1) {
      if (currentQueue.length == 1 ||
          (currentQueue.length == 2 && index == 1)) {
        return;
      }
      await onReorder(index, currentSongIndex.value + 1);
    } else {
      //Will add song just below the current song
      (currentIndex == currentQueue.length - 1)
          ? await enqueueSong(song)
          : await _playbackCommands.addPlayNextItem(
              song,
              remoteQueue: currentQueue,
              currentVideoId: currentSong.value?.id,
            );
    }
  }

  Future<void> _playerPanelCheck({bool restoreSession = false}) async {
    final appContext = AppNavigator.context;
    final screenSize = appContext == null
        ? Size.zero
        : MediaQuery.of(appContext).size;
    final isWideScreen = screenSize.width > 800;
    final autoOpenPlayer = _settingsRepository.getAutoOpenPlayer();
    if (initFlagForPlayer || playerPanelMinHeight.value == 0) {
      final bottomNavVisible =
          _settingsController.isBottomNavBarEnabled.value &&
          getCurrentRouteName() == '/homeScreen' &&
          !playerPanelOpen.value;
      playerPanelMinHeight.value = appContext == null
          ? collapsedMiniPlayerHeightForInset(
              bottomInset: 0,
              isWideScreen: isWideScreen,
              bottomNavVisible: bottomNavVisible,
            )
          : collapsedMiniPlayerHeight(
              appContext,
              isWideScreen: isWideScreen,
              bottomNavVisible: bottomNavVisible,
            );
      initFlagForPlayer = false;
      // Publish the new min height *before* auto-opening the panel so the
      // panel does not animate open from a zero-height mini player.
      _notifyPlayerChanged();
    }

    if ((!isWideScreen && autoOpenPlayer && playerPanelController.isAttached) &&
        !restoreSession) {
      await playerPanelController.open();
    }
  }

  Future<void> removeFromQueue(MediaItem song) async {
    await _playbackCommands.removeQueueItem(song);
  }

  Future<void> clearQueue() async {
    await _playbackCommands.clearQueue();
  }

  Future<void> shuffleQueue() async {
    await _playbackCommands.shuffleQueue();
  }

  Future<void> toggleShuffleMode() async {
    if (_routeToHost(SessionCommand.toggleShuffle())) return;
    final shuffleModeEnabled = isShuffleModeEnabled.value;
    final nextEnabled = await _playbackCommands.toggleShuffle(
      enabled: shuffleModeEnabled,
    );
    isShuffleModeEnabled.value = nextEnabled;
    // restrict queue loop mode when shuffle mode is enabled
    if (isShuffleModeEnabled.value && !isQueueLoopModeEnabled.value) {
      isQueueLoopModeEnabled.value = true;
    } else if (!isShuffleModeEnabled.value) {
      isQueueLoopModeEnabled.value = _settingsRepository
          .getQueueLoopModeEnabled();
    }
  }

  Future<void> onReorder(int oldIndex, int newIndex) async {
    await _playbackCommands.reorderQueue(
      oldIndex: oldIndex,
      newIndex: newIndex,
      remoteQueue: currentQueue,
      currentVideoId: currentSong.value?.id,
    );
  }

  Future<void> onDisplayReorder(
    int oldDisplayIndex,
    int newDisplayIndex,
  ) async {
    final reorderedQueue = realQueueAfterDisplayReorder(
      queue: currentQueue,
      currentIndex: currentSongIndex.value,
      oldDisplayIndex: oldDisplayIndex,
      newDisplayIndex: newDisplayIndex,
    );
    await _playbackCommands.updateQueue(reorderedQueue);
  }

  void onReorderStart(int index) {
    isQueueReorderingInProcess.value = true;
  }

  void onReorderEnd(int index) {
    isQueueReorderingInProcess.value = false;
  }

  /// Returns true and forwards the intent to the host when this device is a
  /// guest in a Listen Together session, so callers can short-circuit local
  /// execution.
  bool get _isSessionGuest => listenTogetherGate?.isGuest ?? false;

  bool _routeToHost(SessionCommand command) {
    final gate = listenTogetherGate;
    if (gate != null && gate.isGuest) {
      gate.sendCommand(command);
      return true;
    }
    return false;
  }

  void _showSessionSnackbar(String message) {
    final context = AppNavigator.context;
    if (context == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      snackbar(
        context,
        message,
        size: SanckBarSize.BIG,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showAddedToSharedQueueSnackbar() {
    final context = AppNavigator.context;
    if (context == null) return;
    _showSessionSnackbar(context.l10n.addedToSharedQueue);
  }

  void _showSessionUnavailableSnackbar() {
    final context = AppNavigator.context;
    if (context == null) return;
    _showSessionSnackbar(context.l10n.notAvailableInSession);
  }

  Future<void> play() async {
    if (_routeToHost(SessionCommand.play())) return;
    if (heosCastController.isConnected) {
      if (heosCastController.isPlaying) return;
      final song = currentSong.value;
      if (song == null) return;
      if (heosCastController.status == HeosCastStatus.connected ||
          heosCastController.status == HeosCastStatus.error) {
        await heosCastController.cast(song);
        _markHeosPlaybackStarted(song);
        return;
      }
      await heosCastController.play();
      _setButtonState(PlayButtonState.playing);
      return;
    }
    await _playbackCommands.play();
  }

  void requestPlay() {
    _runPlaybackCommand(() => play());
  }

  Future<void> pause() async {
    if (_routeToHost(SessionCommand.pause())) return;
    if (heosCastController.isConnected) {
      await heosCastController.pause();
      _setButtonState(PlayButtonState.paused);
      return;
    }
    _clearPendingSourceStart();
    await _playbackCommands.pause();
  }

  void requestPause() {
    _runPlaybackCommand(() => pause());
  }

  Future<void> playPause() async {
    if (initFlagForPlayer) return;
    if (_routeToHost(SessionCommand.playPause())) return;
    await _playbackCommands.playPause(
      isPlaying: _audioHandler.playbackState.value.playing,
    );
    // for gesture player
    if (_settingsController.playerUi.value == 1) {
      gesturePlayerVisibleState.value =
          _audioHandler.playbackState.value.playing ? 0 : 1;
      gesturePlayerStateAnimationController?.reset();
      await gesturePlayerStateAnimationController?.forward();
    }
  }

  void requestPlayPause() {
    _runPlaybackCommand(() => playPause());
  }

  Future<void> prev() async {
    if (_routeToHost(SessionCommand.prev())) return;
    if (heosCastController.isConnected) {
      await _castQueueIndex(_previousQueueIndexForHeos());
      return;
    }
    int? remoteTransition;
    PreviousTrackIntent? remoteIntent;
    String? desiredVideoId;
    if (_cloudRemoteStateActive) {
      final optimisticSeekAt = _optimisticSeekIssuedAt;
      final decisionPosition =
          optimisticSeekAt != null &&
              DateTime.now().difference(optimisticSeekAt) <
                  _optimisticSeekConfirmWindow
          ? _optimisticSeekPosition
          : progressBarStatus.value.current;
      remoteIntent = previousTrackIntentFor(decisionPosition);
      final currentIndex = currentSongIndex.value;
      final shouldSelectPrevious =
          remoteIntent == PreviousTrackIntent.selectPrevious &&
          currentQueue.length > 1 &&
          currentIndex >= 0 &&
          currentIndex < currentQueue.length;
      if (shouldSelectPrevious) {
        final previousIndex = currentIndex > 0
            ? currentIndex - 1
            : isQueueLoopModeEnabled.value
            ? currentQueue.length - 1
            : currentIndex;
        if (previousIndex != currentIndex) {
          desiredVideoId = currentQueue[previousIndex].id;
          remoteTransition = beginRemoteSongTransition(
            currentQueue,
            previousIndex,
          );
        } else {
          _applyOptimisticRemoteSeek(Duration.zero);
          _retargetPendingSourceStart(Duration.zero);
        }
      } else {
        _applyOptimisticRemoteSeek(Duration.zero);
        _retargetPendingSourceStart(Duration.zero);
      }
    } else if (shouldRestartCurrentTrack(progressBarStatus.value.current)) {
      // Locally the handler restarts the current track by seeking to zero, so
      // a source still waiting on a resumed (non-zero) start must be retargeted
      // for the same reason as in [seek].
      _retargetPendingSourceStart(Duration.zero);
    }
    try {
      await _playbackCommands.previous(
        remoteIntent: remoteIntent,
        desiredVideoId: desiredVideoId,
      );
    } catch (_) {
      failRemoteSongTransition(remoteTransition);
      rethrow;
    }
  }

  void requestPrev() {
    _runPlaybackCommand(() => prev());
  }

  Future<void> next() async {
    if (_routeToHost(SessionCommand.next())) return;
    if (heosCastController.isConnected) {
      await _castQueueIndex(_nextQueueIndexForHeos());
      return;
    }
    int? remoteTransition;
    String? desiredVideoId;
    if (_cloudRemoteStateActive && currentQueue.isNotEmpty) {
      final currentIndex = currentSongIndex.value;
      if (currentIndex >= 0 && currentIndex < currentQueue.length) {
        final nextIndex = currentIndex + 1 < currentQueue.length
            ? currentIndex + 1
            : isQueueLoopModeEnabled.value
            ? 0
            : currentIndex;
        if (nextIndex == currentIndex) return;
        desiredVideoId = currentQueue[nextIndex].id;
        remoteTransition = beginRemoteSongTransition(currentQueue, nextIndex);
      }
    }
    try {
      await _playbackCommands.next(desiredVideoId: desiredVideoId);
    } catch (_) {
      failRemoteSongTransition(remoteTransition);
      rethrow;
    }
  }

  void requestNext() {
    _runPlaybackCommand(() => next());
  }

  Future<void> seek(Duration position) async {
    if (_routeToHost(SessionCommand.seek(position))) return;
    if (_cloudRemoteStateActive) _applyOptimisticRemoteSeek(position);
    _retargetPendingSourceStart(position);
    await _playbackCommands.seek(position);
  }

  void requestSeek(Duration position) {
    _runPlaybackCommand(() => seek(position));
  }

  Future<void> seekByIndex(int index) async {
    if (listenTogetherGate?.isPartyModeGuest ?? false) {
      _showSessionUnavailableSnackbar();
      return;
    }
    if (_routeToHost(SessionCommand.playByIndex(index))) return;
    await _playQueueIndex(index);
  }

  void requestSeekByIndex(int index) {
    _runPlaybackCommand(() => seekByIndex(index));
  }

  void _runPlaybackCommand(Future<void> Function() command) {
    final future = command();
    _playbackCommand = future;
    unawaited(
      future
          .catchError((Object error, StackTrace stackTrace) {
            printERROR(error, tag: LogTags.player);
            printERROR(stackTrace, tag: LogTags.player);
          })
          .whenComplete(() {
            if (identical(_playbackCommand, future)) {
              _playbackCommand = null;
            }
          }),
    );
  }

  Future<void> toggleSkipSilence(bool enable) async {
    await _playbackCommands.toggleSkipSilence(enable);
  }

  Future<void> toggleLoudnessNormalization(bool enable) async {
    await _playbackCommands.toggleLoudnessNormalization(enable);
  }

  Future<void> toggleLoopMode() async {
    if (_routeToHost(SessionCommand.toggleLoop())) return;
    isLoopModeEnabled.value = await _playbackCommands.toggleLoop(
      enabled: isLoopModeEnabled.value,
    );
  }

  Future<void> toggleQueueLoopMode({bool showMessage = true}) async {
    if (isShuffleModeEnabled.value && isQueueLoopModeEnabled.value) {
      if (!showMessage) return;
      final context = AppNavigator.context;
      if (context == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(
          context,
          context.l10n.queueLoopNotDisMsg1,
          size: SanckBarSize.BIG,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (isRadioModeOn && !isQueueLoopModeEnabled.value) {
      if (!showMessage) return;
      final context = AppNavigator.context;
      if (context == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(
          context,
          context.l10n.queueLoopNotDisMsg2,
          size: SanckBarSize.BIG,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    isQueueLoopModeEnabled.value = !isQueueLoopModeEnabled.value;
    await _playbackCommands.setQueueLoopMode(isQueueLoopModeEnabled.value);
  }

  Future<void> setVolume(int value) async {
    final normalizedValue = value.clamp(0, 100);
    if (heosCastController.isConnected) {
      await heosCastController.setVolume(normalizedValue);
      volume.value = normalizedValue;
      await _settingsRepository.setVolume(normalizedValue);
      return;
    }
    // Keep the slider and percentage responsive while the platform call and
    // persisted preference complete in the background.
    volume.value = normalizedValue;
    await _playbackCommands.setVolume(normalizedValue);
    await _settingsRepository.setVolume(normalizedValue);
  }

  Future<void> mute() async {
    int? vol;
    if (volume.value != 0) {
      vol = 0;
    } else {
      vol = _settingsRepository.getVolume(defaultValue: 10);
      if (vol == 0) {
        vol = 10;
        await _settingsRepository.setVolume(vol);
      }
    }
    if (heosCastController.isConnected) {
      await heosCastController.setVolume(vol);
    } else {
      await _playbackCommands.setVolume(vol);
    }
    volume.value = vol;
  }

  Future<void> _checkFavFor(MediaItem song) async {
    final isFavorite = await _libraryRepository.isFavorite(song.id);
    if (currentSong.value?.id == song.id) {
      isCurrentSongFav.value = isFavorite;
    }
  }

  /// Re-checks the currently playing song's favorite status against Hive.
  ///
  /// `isCurrentSongFav` otherwise only ever updates on a song change or a
  /// local toggle — a favorite pulled in by cloud sync from another device
  /// left the heart icon showing whatever it showed before, even long after
  /// the pull actually landed. `CloudSyncCoordinator` calls this whenever a
  /// sync touches the favorites box.
  Future<void> refreshFavoriteStatus() async {
    final song = currentSong.value;
    if (song != null) await _checkFavFor(song);
  }

  Future<void> toggleFavourite() async {
    final currMediaItem = currentSong.value!;
    await _libraryRepository.setFavorite(
      currMediaItem,
      !isCurrentSongFav.value,
    );
    try {
      final playlistController = PlaylistScreenControllerRegistry.maybeOf(
        const Key(BoxNames.libFav).hashCode.toString(),
      );
      if (playlistController != null) {
        !isCurrentSongFav.value
            ? await playlistController.addNRemoveItemsInList(
                currMediaItem,
                action: 'add',
                index: 0,
              )
            : await playlistController.addNRemoveItemsInList(
                currMediaItem,
                action: 'remove',
              );
      }

      // ignore: empty_catches
    } catch (e) {}
    try {
      final likedNotDownloadedController =
          PlaylistScreenControllerRegistry.maybeOf(
            const Key(BoxNames.libFavNotDownloaded).hashCode.toString(),
          );
      if (likedNotDownloadedController != null) {
        if (!isCurrentSongFav.value &&
            !await _libraryRepository.isDownloaded(currMediaItem.id)) {
          await likedNotDownloadedController.addNRemoveItemsInList(
            currMediaItem,
            action: 'add',
            index: 0,
          );
        } else {
          await likedNotDownloadedController.addNRemoveItemsInList(
            currMediaItem,
            action: 'remove',
          );
        }
      }
      // ignore: empty_catches
    } catch (e) {}
    isCurrentSongFav.value = !isCurrentSongFav.value;
    // Favorites/liked built-in tiles derive artwork from their first song.
    unawaited(
      LibraryPlaylistsControllerRegistry.current
              ?.refreshInitialPlaylistThumbs() ??
          Future.value(),
    );
    if (_settingsController.autoDownloadFavoriteSongEnabled.value &&
        isCurrentSongFav.value) {
      await _downloader.download(currMediaItem);
    }
  }

  // ignore: prefer_typing_uninitialized_variables
  var recentItem;

  /// This function is used to add a mediaItem/Song to Recently played playlist
  Future<void> _addToRP(MediaItem mediaItem) async {
    if (recentItem != mediaItem) {
      final before = await _libraryRepository.getRecentlyPlayedSongs();
      final removedSongId = before.length >= 30 ? before.first.id : null;
      await _libraryRepository.addRecentlyPlayedSong(mediaItem);
      try {
        final playlistController = PlaylistScreenControllerRegistry.maybeOf(
          const Key(BoxNames.libRP).hashCode.toString(),
        );
        if (playlistController != null) {
          if (removedSongId != null) {
            playlistController.songList.removeWhere(
              (element) => element.id == removedSongId,
            );
          }
          // removes current duplicate item from list
          playlistController.songList.removeWhere(
            (element) => element.id == mediaItem.id,
          );
          // adds current item to list
          await playlistController.addNRemoveItemsInList(
            mediaItem,
            action: 'add',
            index: 0,
          );
        }

        // ignore: empty_catches
      } catch (e) {}
      // Recently-played built-in tile derives artwork from its newest song.
      unawaited(
        LibraryPlaylistsControllerRegistry.current
                ?.refreshInitialPlaylistThumbs() ??
            Future.value(),
      );
    }
    recentItem = mediaItem;
  }

  Future<void> showLyrics() async {
    showLyricsFlag.value = !showLyricsFlag.value;
    notifyListeners();
    if ((lyrics["synced"].isEmpty && lyrics['plainLyrics'].isEmpty) &&
        showLyricsFlag.value) {
      final song = currentSong.value;
      if (song == null) return;
      final songId = song.id;
      final generation = ++_lyricsLoadGeneration;
      isLyricsLoading.value = true;
      notifyListeners();
      try {
        final Map<String, dynamic>? lyricsR =
            await SyncedLyricsService.getSyncedLyrics(
              song,
              progressBarStatus.value.total.inSeconds,
              _lyricsRepository,
            );
        if (!_isCurrentLyricsRequest(songId, generation)) return;
        if (lyricsR != null) {
          lyrics.value = lyricsR;
          isLyricsLoading.value = false;
          notifyListeners();
          return;
        }
        final related = await _musicServices.getWatchPlaylist(
          videoId: songId,
          onlyRelated: true,
        );
        if (!_isCurrentLyricsRequest(songId, generation)) return;
        final relatedLyricsId = related['lyrics'];
        if (relatedLyricsId != null) {
          final lyrics_ = await _musicServices.getLyrics(relatedLyricsId);
          if (!_isCurrentLyricsRequest(songId, generation)) return;
          lyrics.value = {"synced": "", "plainLyrics": lyrics_};
        } else {
          lyrics.value = {"synced": "", "plainLyrics": "NA"};
        }
        notifyListeners();
      } catch (e) {
        if (!_isCurrentLyricsRequest(songId, generation)) return;
        lyrics.value = {"synced": "", "plainLyrics": "NA"};
        notifyListeners();
      } finally {
        if (_isCurrentLyricsRequest(songId, generation)) {
          isLyricsLoading.value = false;
          notifyListeners();
        }
      }
    }
  }

  Future<void> changeLyricsMode(int? val) async {
    await _settingsRepository.setLyricsMode(val ?? 0);
    lyricsMode.value = val ?? 0;
    notifyListeners();
  }

  void updateSyncedLyricsController() {
    final syncedLyrics = lyrics['synced']?.toString() ?? "";
    if (syncedLyrics.isEmpty || syncedLyrics == "NA") return;
    if (_loadedSyncedLyrics != syncedLyrics) {
      lyricController.loadLyric(syncedLyrics);
      _loadedSyncedLyrics = syncedLyrics;
    }
    lyricController.setProgress(progressBarStatus.value.current);
  }

  void _clearLyricsForSongChange() {
    _lyricsLoadGeneration++;
    _loadedSyncedLyrics = null;
    lyrics.value = {"synced": "", "plainLyrics": ""};
    showLyricsFlag.value = false;
    isLyricsLoading.value = false;
    notifyListeners();
  }

  bool _isCurrentLyricsRequest(String songId, int generation) {
    return generation == _lyricsLoadGeneration &&
        currentSong.value?.id == songId;
  }

  void sleepEndOfSong() {
    isSleepTimerActive.value = true;
    isSleepEndOfSongActive.value = true;
    notifyListeners();
  }

  void startSleepTimer(int minutes) {
    timerDuration = minutes * 60;
    isSleepTimerActive.value = true;
    notifyListeners();
    if ((sleepTimer != null && !sleepTimer!.isActive) || sleepTimer == null) {
      sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (timer.tick == timerDuration) {
          sleepTimer?.cancel();
          requestPause();
          isSleepTimerActive.value = false;
          timerDuration = 0;
          timerDurationLeft.value = 0;
          notifyListeners();
        } else {
          timerDurationLeft.value = timerDuration - timer.tick;
          notifyListeners();
        }
      });
    }
  }

  void addFiveMinutes() {
    timerDuration += 300;
    notifyListeners();
  }

  void cancelSleepTimer() {
    if (isSleepEndOfSongActive.value) {
      isSleepEndOfSongActive.value = false;
    }
    sleepTimer?.cancel();
    isSleepTimerActive.value = false;
    timerDuration = 0;
    timerDurationLeft.value = 0;
    notifyListeners();
  }

  Future<void> openEqualizer() async {
    await _audioHandler.customAction("openEqualizer");
  }

  /// Called from audio handler in case audio is not playable
  /// or returned streamInfo null due to network error
  void notifyPlayError(String message) {
    final context = AppNavigator.context;
    if (context == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      snackbar(context, switch (message) {
        "networkError" => context.l10n.networkError,
        "resolverPlaybackFailed" => context.l10n.resolverPlaybackFailed,
        _ => message,
      }, size: SanckBarSize.MEDIUM),
    );
  }

  Map<String, dynamic> playbackDebugSnapshot() {
    final playback = _audioHandler.playbackState.value;
    final handlerMediaItem = _audioHandler.mediaItem.value;
    final handlerQueue = _audioHandler.queue.value;
    final progress = progressBarStatus.value;
    final current = currentSong.value;
    return {
      // Which role this device believes it has. The first handoff failure could
      // not be diagnosed from a dump because nothing recorded this, and the
      // roles had to be inferred from whether the controller disagreed with its
      // own audio handler.
      'cloudPlayback': {
        'isMirroringRemotePlayback': _cloudRemoteStateActive,
        'cloudSocketStatus': _cloudSocketStatus.name,
        'currentSongResolving': _currentSongResolving,
        'queueResolution': _queueResolution == null
            ? null
            : {'resolved': _queueResolution!.$1, 'total': _queueResolution!.$2},
        'remoteAnchorPositionMs': _remoteAnchor.position.inMilliseconds,
        'remoteAnchorAgeMs': DateTime.now()
            .difference(_remoteAnchor.anchoredAt)
            .inMilliseconds,
        'remoteAnchorStale': _remoteAnchor.isStale(DateTime.now()),
        'remoteProgressTicking': _remoteProgressTicker != null,
        ...?cloudReceiverDiagnostics?.call(),
      },
      'playerController': {
        'buttonState': buttonState.value.name,
        'currentSongIndex': currentSongIndex.value,
        'currentSong': _mediaItemDebug(current),
        'currentQueueLength': currentQueue.length,
        'displayQueueLength': displayQueue.length,
        'isShuffleModeEnabled': isShuffleModeEnabled.value,
        'isLoopModeEnabled': isLoopModeEnabled.value,
        'isQueueLoopModeEnabled': isQueueLoopModeEnabled.value,
        'isCurrentSongBuffered': isCurrentSongBuffered.value,
        'isRadioModeOn': isRadioModeOn,
        'isSleepTimerActive': isSleepTimerActive.value,
        'isSleepEndOfSongActive': isSleepEndOfSongActive.value,
        'timerDuration': timerDuration,
        'timerDurationLeft': timerDurationLeft.value,
        'progressCurrentMs': progress.current.inMilliseconds,
        'progressBufferedMs': progress.buffered.inMilliseconds,
        'progressTotalMs': progress.total.inMilliseconds,
        'pendingPlaybackStartSongId': _pendingPlaybackStartSongId,
        'pendingSourceTransitionObserved': _pendingSourceTransitionObserved,
        'isWaitingForCurrentSourceStart': _isWaitingForCurrentSourceStart,
        'sourceStartProgressWindowMs':
            _sourceStartProgressWindow.inMilliseconds,
        // What the start conditions are measured against. Without these a
        // stuck spinner is indistinguishable from a position stream that
        // never ticked.
        'pendingPlaybackStartPositionMs':
            _pendingPlaybackStartPosition.inMilliseconds,
        'expectedSourceStartPositionMs':
            _expectedSourceStartPosition?.inMilliseconds,
        'pendingSourceOutgoingPositionMs':
            _pendingSourceOutgoingPosition.inMilliseconds,
        'sourceStartTicksSeen': _sourceStartTicksSeen,
        'sourceStartLastRejectedPositionMs':
            _sourceStartLastRejectedPosition?.inMilliseconds,
        'playerPanelMinHeight': playerPanelMinHeight.value,
        'playerPanelTopVisible': playerPanelTopVisible.value,
        'isPanelGTHOpened': playerPanelOpen.value,
        'lyricsMode': lyricsMode.value,
        'showLyricsFlag': showLyricsFlag.value,
        'isLyricsLoading': isLyricsLoading.value,
      },
      'audioHandler': {
        'mediaItem': _mediaItemDebug(handlerMediaItem),
        'queueLength': handlerQueue.length,
        'queueIndex': playback.queueIndex,
        'playing': playback.playing,
        'processingState': playback.processingState.name,
        'repeatMode': playback.repeatMode.name,
        'shuffleMode': playback.shuffleMode.name,
        'updatePositionMs': playback.updatePosition.inMilliseconds,
        'bufferedPositionMs': playback.bufferedPosition.inMilliseconds,
        'speed': playback.speed,
        'errorCode': playback.errorCode,
        'errorMessage': playback.errorMessage,
      },
      'remotePlaybackModes': {
        'shuffle': isShuffleModeEnabled.value,
        'repeat': isLoopModeEnabled.value,
        'queueLoop': isQueueLoopModeEnabled.value,
      },
    };
  }

  Future<Map<String, dynamic>> detailedPlaybackDebugSnapshot() async {
    final snapshot = playbackDebugSnapshot();
    try {
      final handlerSnapshot = await _audioHandler.customAction(
        'playbackDebugSnapshot',
      );
      if (handlerSnapshot is Map) {
        snapshot['audioHandlerInternal'] = Map<String, dynamic>.from(
          handlerSnapshot,
        );
      }
    } catch (error) {
      snapshot['audioHandlerInternalError'] = error.toString();
    }
    return snapshot;
  }

  Map<String, dynamic>? _mediaItemDebug(MediaItem? item) {
    if (item == null) return null;
    return {
      'id': item.id,
      'title': item.title,
      'artist': item.artist,
      'album': item.album,
      'durationMs': item.duration?.inMilliseconds,
      'artUri': item.artUri?.toString(),
      'extras': _extrasDebug(item.extras),
    };
  }

  Map<String, dynamic>? _extrasDebug(Map<String, dynamic>? extras) {
    if (extras == null) return null;
    return {for (final entry in extras.entries) entry.key: _debugValue(entry)};
  }

  Object? _debugValue(MapEntry<String, dynamic> entry) {
    final key = entry.key.toLowerCase();
    final value = entry.value;
    if (key.contains('url') ||
        key.contains('token') ||
        key.contains('cookie')) {
      return _redactedUrlDebug(value);
    }
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is Uri) return value.toString();
    if (value is Map) return {'type': 'Map', 'keys': value.keys.toList()};
    if (value is Iterable) return {'type': 'Iterable', 'length': value.length};
    return value.toString();
  }

  Map<String, dynamic>? _redactedUrlDebug(Object? value) {
    if (value == null) return null;
    final url = value.toString();
    final uri = Uri.tryParse(url);
    return {
      'isEmpty': url.isEmpty,
      'scheme': uri?.scheme,
      'host': uri?.host,
      'pathLength': uri?.path.length,
      'queryParameterCount': uri?.queryParameters.length,
    };
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_audioHandler.customAction('dispose'));
    for (final subscription in _observableSubscriptions) {
      unawaited(subscription.cancel());
    }
    _observableSubscriptions.clear();
    unawaited(keyboardSubscription?.cancel());
    _stopRemoteProgressTicker();
    scrollController.dispose();
    lyricController.dispose();
    gesturePlayerStateAnimationController?.dispose();
    sleepTimer?.cancel();
    _cancelBufferingGrace();
    if (RuntimePlatform.isWindows) {
      _windowsAudioService?.dispose();
      _windowsAudioService = null;
    }
    final heosListener = _heosListener;
    if (heosListener != null) {
      heosCastController.removeListener(heosListener);
      _heosListener = null;
    }
    // ensure wakelock disabled when player controller disposed
    try {
      _setWakelock(false);
      _setPlaybackWakeLock(false);
    } catch (e) {
      printERROR(e, tag: LogTags.player);
    }
    super.dispose();
  }
}

/// The single app-wide `PlayerController`, reachable without a Riverpod
/// dependency edge — mirrors `LibrarySongsControllerRegistry` and exists for
/// the same reason: `CloudSyncCoordinator` needs to reach a live controller
/// from a background sync, and `ref.watch`ing it there would force the whole
/// audio subsystem to initialize the moment sync starts, which can be well
/// before anything is otherwise ready for it.
class PlayerControllerRegistry {
  PlayerControllerRegistry._();

  static PlayerController? _controller;

  /// Never a disposed controller: this is static, so without the check it
  /// keeps handing out the last one registered long after the app that owned
  /// it is gone.
  static PlayerController? get current =>
      _controller?._disposed == true ? null : _controller;

  static void register(PlayerController controller) {
    _controller = controller;
  }
}

enum PlayButtonState { paused, playing, loading }

class _RemoteSongTransitionSnapshot {
  const _RemoteSongTransitionSnapshot({
    required this.queue,
    required this.index,
    required this.song,
    required this.progress,
    required this.buttonState,
    required this.isFavorite,
    required this.remoteAnchor,
    required this.wasProgressTicking,
  });

  final List<MediaItem> queue;
  final int index;
  final MediaItem? song;
  final ProgressBarState progress;
  final PlayButtonState buttonState;
  final bool isFavorite;
  final RemoteProgressAnchor remoteAnchor;
  final bool wasProgressTicking;
}
