import 'dart:async';

import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';

class MediaKitPlayer extends AudioPlayerPlatform {
  late final Player _player;
  late final List<StreamSubscription<dynamic>> _streamSubscriptions;

  final _readyCompleter = Completer<void>();
  static final _logger = Logger('MediaKitPlayer');
  final _eventController = StreamController<PlaybackEventMessage>.broadcast();
  final _dataController = StreamController<PlayerDataMessage>.broadcast();

  ProcessingStateMessage _processingState = ProcessingStateMessage.idle;
  Duration _bufferedPosition = Duration.zero;
  Duration _position = Duration.zero;
  int _currentIndex = 0;
  final List<AudioSourceMessage> _sources = [];
  bool _audioReady = false;
  bool _sourceLoading = false;
  Completer<void>? _sourceReadyCompleter;
  Duration? _pendingSeek;

  /// Bumped by every [_openSources]. A load that loses the race must not act
  /// on its own completion.
  int _loadGeneration = 0;

  MediaKitPlayer(super.id) {
    _player = Player(
      configuration: PlayerConfiguration(
        protocolWhitelist: JustAudioMediaKit.protocolWhitelist,
        title: JustAudioMediaKit.title,
        bufferSize: JustAudioMediaKit.bufferSize,
        logLevel: JustAudioMediaKit.mpvLogLevel,
        ready: () => _readyCompleter.complete(),
      ),
    );

    _streamSubscriptions = [
      _player.stream.duration.listen((duration) {
        if (!_sourceLoading) {
          _processingState = ProcessingStateMessage.ready;
        }
        _updatePlaybackEvent(duration: duration);
      }),
      _player.stream.position.listen((position) {
        _position = position;
        _updatePlaybackEvent();
      }),
      _player.stream.buffering.listen((isBuffering) {
        if (!_sourceLoading) {
          _processingState = isBuffering
              ? ProcessingStateMessage.buffering
              : ProcessingStateMessage.ready;
        }
        _updatePlaybackEvent();
      }),
      _player.stream.buffer.listen((buffer) {
        _bufferedPosition = buffer;
        _updatePlaybackEvent();
      }),
      _player.stream.playing.listen((playing) {
        if (!_sourceLoading) {
          _processingState = ProcessingStateMessage.ready;
        }
        _dataController.add(PlayerDataMessage(playing: playing));
        _updatePlaybackEvent();
      }),
      _player.stream.volume.listen((volume) {
        _dataController.add(PlayerDataMessage(volume: volume / 100.0));
      }),
      _player.stream.completed.listen((completed) {
        _processingState = completed
            ? ProcessingStateMessage.completed
            : ProcessingStateMessage.ready;
        _updatePlaybackEvent();
      }),
      _player.stream.error.listen((error) {
        _sourceLoading = false;
        _processingState = ProcessingStateMessage.idle;
        _eventController.addError(error);
        _diagnostic('error', error);
      }),
      _player.stream.playlist.listen((playlist) {
        _currentIndex = playlist.index;
        _updatePlaybackEvent();
      }),
      _player.stream.pitch.listen((pitch) {
        _dataController.add(PlayerDataMessage(pitch: pitch));
      }),
      _player.stream.rate.listen((rate) {
        _dataController.add(PlayerDataMessage(speed: rate));
      }),
      _player.stream.audioDevice.listen((device) {
        _diagnostic(
          'audio-device',
          '${device.name} (${device.description})',
        );
      }),
      _player.stream.audioDevices.listen((devices) {
        _diagnostic(
          'audio-devices',
          devices
              .map((device) => '${device.name} (${device.description})')
              .join(', '),
        );
      }),
      _player.stream.audioParams.listen((params) {
        _audioReady = true;
        _sourceLoading = false;
        _processingState = ProcessingStateMessage.ready;
        final sourceReadyCompleter = _sourceReadyCompleter;
        if (sourceReadyCompleter != null && !sourceReadyCompleter.isCompleted) {
          sourceReadyCompleter.complete();
        }
        _diagnostic('audio-params', params.toString());
        _updatePlaybackEvent();
        final pendingSeek = _pendingSeek;
        if (pendingSeek != null) {
          _pendingSeek = null;
          unawaited(_applySeek(pendingSeek));
        }
      }),
      _player.stream.log.listen((event) {
        if (event.level == 'error' || event.level == 'warn') {
          _diagnostic('mpv-${event.level}', '${event.prefix}: ${event.text}');
        }
      }),
    ];
  }

  Future<void> initializeAudioOutput() async {
    await _readyCompleter.future;
    final platform = _player.platform;
    if (platform is NativePlayer) {
      // The bundled audio-only libmpv cannot create its default disk cache on
      // some Windows installations. Keep startup buffering in memory so a
      // failed cache file does not interrupt the first decoded frames.
      await platform.setProperty('cache-on-disk', 'no');
    }
    await _player.setAudioDevice(AudioDevice.auto());
    _diagnostic('audio-output', 'initialized with automatic device selection');
  }

  void _diagnostic(String category, Object message) {
    final text = message.toString().trim();
    _logger.fine('$category: $text');
    JustAudioMediaKit.diagnosticCallback?.call(category, text);
  }

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      _eventController.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream =>
      _dataController.stream;

  void _updatePlaybackEvent(
      {Duration? duration, IcyMetadataMessage? icyMetadata}) {
    _eventController.add(
      PlaybackEventMessage(
        processingState: _processingState,
        updateTime: DateTime.now(),
        updatePosition: _position,
        bufferedPosition: _bufferedPosition,
        duration: duration,
        icyMetadata: icyMetadata,
        currentIndex: _currentIndex,
        androidAudioSessionId: null,
      ),
    );
  }

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    _currentIndex = request.initialIndex ?? 0;
    _bufferedPosition = Duration.zero;
    _position = Duration.zero;
    _sources
      ..clear()
      ..addAll(_flattenSources(request.audioSourceMessage));
    if (_sources.isEmpty) {
      await _player.pause();
      return LoadResponse(duration: null);
    }

    _currentIndex = _currentIndex.clamp(0, _sources.length - 1);
    await _openSources(index: _currentIndex, play: false);
    final generation = _loadGeneration;
    await _waitForDecodedAudio();
    // A newer load owns the player now. Recording this one's initial position
    // would hand the newer source the older one's start point.
    if (generation != _loadGeneration) return LoadResponse(duration: null);
    if (request.initialPosition != null) {
      _position = request.initialPosition!;
      if (_position > Duration.zero) _pendingSeek = _position;
    }
    final duration = _player.state.duration;
    return LoadResponse(duration: duration == Duration.zero ? null : duration);
  }

  Iterable<AudioSourceMessage> _flattenSources(
      AudioSourceMessage source) sync* {
    if (source is UriAudioSourceMessage) {
      yield source;
    } else if (source is ConcatenatingAudioSourceMessage) {
      for (final child in source.children) {
        yield* _flattenSources(child);
      }
    } else if (source is ClippingAudioSourceMessage) {
      yield source.child;
    } else if (source is LoopingAudioSourceMessage) {
      for (var i = 0; i < source.count; i++) {
        yield* _flattenSources(source.child);
      }
    } else {
      throw UnsupportedError('${source.runtimeType} is not supported');
    }
  }

  Future<void> _openSources({required int index, required bool play}) async {
    final media = _sources.map(_convertAudioSource).toList(growable: false);
    // Release whoever is waiting on the load being replaced. Dropping the
    // completer instead left that waiter parked until its 15s timeout, and it
    // then resumed as though it were current - seeking a track that had been
    // playing for twelve seconds back to zero. Three handoffs of the same song
    // arriving within 2.5s is enough to produce exactly that.
    final superseded = _sourceReadyCompleter;
    if (superseded != null && !superseded.isCompleted) superseded.complete();
    _loadGeneration++;
    _audioReady = false;
    _sourceLoading = true;
    _sourceReadyCompleter = Completer<void>();
    _pendingSeek = null;
    _processingState = ProcessingStateMessage.loading;
    _updatePlaybackEvent();
    await _player.open(Playlist(media, index: index), play: play);
    _diagnostic(
      'source-load',
      'loaded ${media.length} source(s) at index $index play=$play',
    );
  }

  Future<void> _waitForDecodedAudio() async {
    final sourceReadyCompleter = _sourceReadyCompleter;
    if (_audioReady || sourceReadyCompleter == null) return;
    try {
      await sourceReadyCompleter.future.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      _diagnostic(
        'audio-ready-timeout',
        'decoded audio was not reported within 15 seconds',
      );
    }
  }

  Media _convertAudioSource(AudioSourceMessage audioSource) {
    if (audioSource is! UriAudioSourceMessage) {
      throw UnsupportedError('${audioSource.runtimeType} is not supported');
    }
    final isWindowsPath = RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(audioSource.uri);
    final uri = Uri.parse(audioSource.uri);
    final normalized = !isWindowsPath && uri.hasScheme
        ? uri.toString()
        : Uri.file(audioSource.uri, windows: isWindowsPath).toString();
    return Media(normalized, httpHeaders: audioSource.headers);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    await _player.play();
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    await _player.pause();
    return PauseResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    final volume = request.volume.clamp(0.0, 1.0);
    await _player.setVolume(volume * 100.0);
    _diagnostic('volume', '${(volume * 100).round()}%');
    return SetVolumeResponse();
  }

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async {
    await _player.setRate(request.speed);
    return SetSpeedResponse();
  }

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async {
    await _player.setPitch(request.pitch);
    return SetPitchResponse();
  }

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async {
    await _player.setPlaylistMode(const {
      LoopModeMessage.off: PlaylistMode.none,
      LoopModeMessage.one: PlaylistMode.single,
      LoopModeMessage.all: PlaylistMode.loop,
    }[request.loopMode]!);
    return SetLoopModeResponse();
  }

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async {
    await _player.setShuffle(request.shuffleMode == ShuffleModeMessage.all);
    return SetShuffleModeResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    if (request.index != null) await _player.jump(request.index!);
    if (request.position != null) {
      _position = request.position!;
      if (_audioReady) {
        // Zero is a real seek too. Treating it only as a reported-position
        // reset left mpv playing from the old timestamp, so Previous appeared
        // to jump to 0:00 and then snapped back without restarting the audio.
        await _applySeek(_position);
      } else if (_position == Duration.zero) {
        // A source that has not decoded yet starts at zero naturally.
        _pendingSeek = null;
      } else {
        _pendingSeek = _position;
      }
    } else {
      _position = Duration.zero;
    }
    _updatePlaybackEvent();
    return SeekResponse();
  }

  Future<void> _applySeek(Duration position) async {
    await _player.seek(position);
    _diagnostic('seek', 'applied ${position.inMilliseconds}ms');
  }

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
    ConcatenatingInsertAllRequest request,
  ) async {
    if (request.children.isEmpty) return ConcatenatingInsertAllResponse();
    final wasEmpty = _sources.isEmpty;
    final inserted = request.children.expand(_flattenSources).toList();
    final insertionIndex = request.index.clamp(0, _sources.length);
    _sources.insertAll(insertionIndex, inserted);
    if (wasEmpty) {
      // just_audio calls load() immediately after populating a fresh
      // ConcatenatingAudioSource. Defer opening to load() so MediaKit does not
      // initialize the same stream twice at the beginning of every song.
      _currentIndex = insertionIndex;
      return ConcatenatingInsertAllResponse();
    }
    final targetIndex = _sources.length == inserted.length
        ? insertionIndex
        : _currentIndex.clamp(0, _sources.length - 1);
    await _openSources(index: targetIndex, play: _player.state.playing);
    return ConcatenatingInsertAllResponse();
  }

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
    ConcatenatingRemoveRangeRequest request,
  ) async {
    final start = request.startIndex.clamp(0, _sources.length);
    final end = request.endIndex.clamp(start, _sources.length);
    if (start == end) return ConcatenatingRemoveRangeResponse();
    final wasPlaying = _player.state.playing;
    _sources.removeRange(start, end);
    if (_sources.isEmpty) {
      // Keep the initialized Windows audio endpoint alive. The next open()
      // replaces the paused media without recreating the mixer session.
      await _player.pause();
      _currentIndex = 0;
    } else {
      _currentIndex = _currentIndex.clamp(0, _sources.length - 1);
      await _openSources(index: _currentIndex, play: wasPlaying);
    }
    return ConcatenatingRemoveRangeResponse();
  }

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(
    ConcatenatingMoveRequest request,
  ) async {
    if (request.currentIndex >= 0 &&
        request.currentIndex < _sources.length &&
        request.newIndex >= 0 &&
        request.newIndex < _sources.length) {
      final source = _sources.removeAt(request.currentIndex);
      _sources.insert(request.newIndex, source);
      await _player.move(request.currentIndex, request.newIndex);
    }
    return ConcatenatingMoveResponse();
  }

  Future<void> release() async {
    await _player.dispose();
    for (final subscription in _streamSubscriptions) {
      await subscription.cancel();
    }
    await _eventController.close();
    await _dataController.close();
  }
}
