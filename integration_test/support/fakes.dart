import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:harmonymusic/domain/repositories/download_repository.dart';
import 'package:harmonymusic/domain/repositories/lyrics_repository.dart';
import 'package:harmonymusic/domain/repositories/settings_repository.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/app_contracts.dart';
import 'package:harmonymusic/services/downloader.dart';
import 'package:harmonymusic/services/resolver/resolver_client.dart';
import 'package:harmonymusic/utils/helper.dart';

MediaItem testSong({
  String id = 'song-1',
  String title = 'Fixture Song',
  String artist = 'Fixture Artist',
}) {
  return MediaItem(
    id: id,
    title: title,
    artist: artist,
    duration: const Duration(minutes: 3),
    artUri: Uri.parse('https://example.test/$id.png'),
    extras: const {'isLive': false},
  );
}

class FakeLyricsRepository implements LyricsRepository {
  FakeLyricsRepository({this.lyrics, this.completeReadsAutomatically = true});

  dynamic lyrics;
  bool completeReadsAutomatically;
  int getCallCount = 0;
  int saveCallCount = 0;
  Completer<dynamic>? _pendingRead;

  @override
  Future<dynamic> getLyrics(String key) {
    getCallCount++;
    if (completeReadsAutomatically) return Future<dynamic>.value(lyrics);
    _pendingRead ??= Completer<dynamic>();
    return _pendingRead!.future;
  }

  void completePendingRead([dynamic result]) {
    final pendingRead = _pendingRead;
    if (pendingRead == null || pendingRead.isCompleted) return;
    pendingRead.complete(result ?? lyrics);
  }

  @override
  Future<void> saveLyrics(String key, dynamic lyrics) async {
    saveCallCount++;
    this.lyrics = lyrics;
  }
}

class FakeMusicService implements MusicServiceContract {
  String languageCode = 'en';

  final songOne = testSong();
  final songTwo = testSong(
    id: 'song-2',
    title: 'Fixture Song Two',
    artist: 'Fixture Artist',
  );

  @override
  set hlCode(String code) {
    languageCode = code;
  }

  @override
  Future<dynamic> getHome({int limit = 4}) async {
    return [
      {
        'title': 'Quick picks',
        'contents': [songOne, songTwo],
      },
      {
        'title': 'Fixture albums',
        'contents': [
          Album(
            title: 'Fixture Album',
            browseId: 'album-1',
            thumbnailUrl: 'https://example.test/album.png',
            artists: const [],
            audioPlaylistId: 'playlist-1',
          ),
        ],
      },
      {
        'title': 'Fixture playlists',
        'contents': [
          Playlist(
            title: 'Fixture Playlist',
            playlistId: 'playlist-1',
            thumbnailUrl: Playlist.thumbPlaceholderUrl,
          ),
        ],
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> getCharts(
    String category, {
    String? countryCode,
  }) async {
    return [
      {
        'title': category == 'TMV' ? 'Top Music Videos' : 'Trending',
        'contents': [songOne, songTwo],
      },
    ];
  }

  @override
  dynamic getContentRelatedToSong(String videoId, String hlCode) async {
    return [
      {
        'title': 'Because of fixture',
        'contents': [songOne, songTwo],
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> getPlaylistOrAlbumSongs({
    String? playlistId,
    String? albumId,
    int limit = 3000,
    bool related = false,
    int suggestionsLimit = 0,
  }) async {
    return {
      'title': albumId == null ? 'Fixture Playlist' : 'Fixture Album',
      'description': 'Fixture description',
      'tracks': [songOne, songTwo],
      'thumbnails': [
        {'url': 'https://example.test/fixture.png'},
      ],
    };
  }

  @override
  Future<List> getSongWithId(String songId) async => [
    true,
    [songOne, songTwo],
  ];

  @override
  Future<MediaItem?> resolveSongMetadata(String songId) async =>
      songId == songTwo.id ? songTwo : songOne;

  @override
  Future<Map<String, dynamic>> getWatchPlaylist({
    String videoId = "",
    String? playlistId,
    int limit = 25,
    bool radio = false,
    bool shuffle = false,
    String? additionalParamsNext,
    bool onlyRelated = false,
  }) async {
    return {
      'tracks': [songOne, songTwo],
    };
  }

  @override
  dynamic getLyrics(String browseId) async => null;

  @override
  Future<List<String>> getSearchSuggestion(String queryStr) async {
    return ['fixture song', 'fixture artist'];
  }

  @override
  Future<Map<String, dynamic>> getSearchContinuation(
    Map additionalParamsNext, {
    int limit = 10,
  }) async {
    return {
      'Songs': [songOne],
    };
  }

  @override
  Future<Map<String, dynamic>> getArtist(String channelId) async {
    return {
      'name': 'Fixture Artist',
      'songs': [songOne, songTwo],
    };
  }

  @override
  Future<Map<String, dynamic>> getArtistRelatedContent(
    Map<String, dynamic> browseEndpoint,
    String category, {
    String additionalParams = "",
  }) async {
    return {
      'results': [songOne, songTwo],
    };
  }

  @override
  Future<Map<String, dynamic>> search(
    String query, {
    String? filter,
    String? scope,
    int limit = 30,
    bool ignoreSpelling = false,
    String? filterParams,
  }) async {
    if (query.toLowerCase().contains('nonsense')) return {};
    return {
      'Songs': [songOne],
      'Videos': [songTwo],
      'Albums': [
        Album(
          title: 'Fixture Album',
          browseId: 'album-1',
          thumbnailUrl: 'https://example.test/album.png',
          artists: const [],
          audioPlaylistId: 'playlist-1',
        ),
      ],
      'Artists': [],
    };
  }
}

class FakeUpdateService implements UpdateServiceContract {
  // No update by default: the home screen checks on every boot regardless of
  // channel, and a non-null result pops a real, tap-to-dismiss
  // `NewVersionDialog` over the whole screen. Left blocking, that dialog
  // silently swallows the next test's first tap on whatever it happens to
  // land on (the modal barrier absorbs the pointer event) rather than
  // failing the test that actually caused it — only [hasUpdate] tests that.
  const FakeUpdateService({
    this.hasUpdate = false,
    this.rollingSha = 'remote-sha',
  });

  final bool hasUpdate;
  final String rollingSha;

  @override
  Future<UpdateInfo?> checkNewVersion(
    String currentVersion, {
    UpdateChannel channel = UpdateChannel.stable,
  }) async {
    if (!hasUpdate || channel == UpdateChannel.stable) return null;
    return UpdateInfo(
      channel: UpdateChannel.rolling,
      version: 'main-latest',
      downloadUrl: 'https://example.test/harmonymusic-main-latest.apk',
      releaseUrl: 'https://example.test/releases/main-latest',
      sha: rollingSha,
    );
  }
}

class FakeAppPlatform implements AppPlatformContract {
  final openedUrls = <String>[];
  final installedApks = <String>[];
  final sharedTexts = <String>[];
  var restarted = false;
  var keepAwake = false;
  var playbackWakeLocked = false;

  @override
  Future<AppPlatformInfo> getAppInfo() async {
    return const AppPlatformInfo(
      appName: 'Harmony Music Test',
      packageName: 'com.anandnet.harmonymusic.test',
      version: '5.9.2',
      buildNumber: '28',
    );
  }

  @override
  Future<void> setKeepScreenAwake(bool enable) async {
    keepAwake = enable;
  }

  @override
  Future<void> setPlaybackWakeLock(bool enable) async {
    playbackWakeLocked = enable;
  }

  @override
  Future<void> shareText(String text) async {
    sharedTexts.add(text);
  }

  @override
  Future<void> openUrl(String url) async {
    openedUrls.add(url);
  }

  @override
  Future<void> installApk(String path) async {
    installedApks.add(path);
  }

  @override
  Future<void> restartApp({bool terminate = true}) async {
    restarted = true;
  }

  @override
  Future<SystemNavigationMode> getSystemNavigationMode() {
    // TODO: implement getSystemNavigationMode
    throw UnimplementedError();
  }
}

class FakeFilePicker implements FilePickerContract {
  FakeFilePicker({this.filePath, this.directoryPath});

  final String? filePath;
  final String? directoryPath;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    final path = filePath;
    return path == null ? null : XFile(path);
  }

  @override
  Future<String?> pickLargeFilePath({required List<String> extensions}) async {
    return filePath;
  }

  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    return directoryPath;
  }
}

class FakeAudioHandler extends BaseAudioHandler {
  FakeAudioHandler() {
    reset();
  }

  int playCallCount = 0;
  int pauseCallCount = 0;
  int nextCallCount = 0;
  int previousCallCount = 0;
  final seekPositions = <Duration>[];
  final playedIndices = <int>[];
  final customActionNames = <String>[];
  final shuffleModes = <AudioServiceShuffleMode>[];
  final repeatModes = <AudioServiceRepeatMode>[];
  bool completeSourceLoadsAutomatically = true;
  bool bufferSeeks = false;

  /// `AudioService.init` can only run once per test process (the plugin owns
  /// a single static handler), so every `bootTestApp` call in a file reuses
  /// the same instance rather than constructing a fresh one — this clears
  /// state a prior test in the same file left behind instead.
  void reset() {
    playCallCount = 0;
    pauseCallCount = 0;
    nextCallCount = 0;
    previousCallCount = 0;
    seekPositions.clear();
    playedIndices.clear();
    customActionNames.clear();
    shuffleModes.clear();
    repeatModes.clear();
    completeSourceLoadsAutomatically = true;
    bufferSeeks = false;
    playbackState.add(
      PlaybackState(
        controls: const [],
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    queue.add(const []);
    mediaItem.add(null);
  }

  @override
  Future<void> updateQueue(List<MediaItem> newQueue) async {
    queue.add(List<MediaItem>.from(newQueue));
    if (newQueue.isEmpty) {
      mediaItem.add(null);
      return;
    }
    final currentId = mediaItem.value?.id;
    final currentIndex = newQueue.indexWhere((item) => item.id == currentId);
    final index = currentIndex < 0 ? 0 : currentIndex;
    mediaItem.add(newQueue[index]);
    playbackState.add(playbackState.value.copyWith(queueIndex: index));
  }

  @override
  Future<void> play() async {
    playCallCount++;
    playbackState.add(
      playbackState.value.copyWith(
        playing: true,
        processingState: AudioProcessingState.ready,
      ),
    );
  }

  @override
  Future<void> pause() async {
    pauseCallCount++;
    playbackState.add(playbackState.value.copyWith(playing: false));
  }

  @override
  Future<void> seek(Duration position) async {
    seekPositions.add(position);
    playbackState.add(
      playbackState.value.copyWith(
        playing: true,
        processingState: bufferSeeks
            ? AudioProcessingState.buffering
            : AudioProcessingState.ready,
        updatePosition: position,
      ),
    );
  }

  @override
  Future<void> skipToNext() async {
    nextCallCount++;
    final currentQueue = queue.value;
    final currentIndex = currentQueue.indexWhere(
      (item) => item.id == mediaItem.value?.id,
    );
    if (currentIndex >= 0 && currentIndex + 1 < currentQueue.length) {
      await _selectQueueIndex(currentIndex + 1);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    previousCallCount++;
    final currentQueue = queue.value;
    final currentIndex = currentQueue.indexWhere(
      (item) => item.id == mediaItem.value?.id,
    );
    if (currentIndex > 0) {
      await _selectQueueIndex(currentIndex - 1);
    } else {
      await seek(Duration.zero);
    }
  }

  @override
  Future<void> addQueueItem(MediaItem item) async {
    await updateQueue([...queue.value, item]);
  }

  @override
  Future<void> addQueueItems(List<MediaItem> items) async {
    await updateQueue([...queue.value, ...items]);
  }

  @override
  Future<void> removeQueueItem(MediaItem item) async {
    await updateQueue(
      queue.value.where((queued) => queued.id != item.id).toList(),
    );
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    shuffleModes.add(shuffleMode);
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    repeatModes.add(repeatMode);
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    customActionNames.add(name);
    final item = extras?['mediaItem'];
    if (name == 'setSourceNPlay' && item is MediaItem) {
      queue.add([item]);
      await _selectQueueIndex(0);
    } else if (name == 'playByIndex') {
      final index = extras?['index'] as int? ?? 0;
      playedIndices.add(index);
      await _selectQueueIndex(index);
    } else if (item is MediaItem) {
      mediaItem.add(item);
      queue.add([item]);
    } else if (name == 'clearQueue') {
      queue.add(const []);
      mediaItem.add(null);
      playbackState.add(
        playbackState.value.copyWith(
          playing: false,
          processingState: AudioProcessingState.idle,
          queueIndex: null,
        ),
      );
    } else if (name == 'reorderQueue') {
      final oldIndex = extras?['oldIndex'] as int? ?? -1;
      var newIndex = extras?['newIndex'] as int? ?? -1;
      final reordered = List<MediaItem>.from(queue.value);
      if (oldIndex >= 0 &&
          oldIndex < reordered.length &&
          newIndex >= 0 &&
          newIndex <= reordered.length) {
        final item = reordered.removeAt(oldIndex);
        if (newIndex > oldIndex) newIndex--;
        reordered.insert(newIndex, item);
        queue.add(reordered);
      }
    }
    return null;
  }

  Future<void> _selectQueueIndex(int index) async {
    final currentQueue = queue.value;
    if (index < 0 || index >= currentQueue.length) return;
    playbackState.add(
      playbackState.value.copyWith(
        playing: true,
        processingState: AudioProcessingState.loading,
        queueIndex: index,
      ),
    );
    mediaItem.add(currentQueue[index]);
    if (!completeSourceLoadsAutomatically) return;
    await Future<void>.delayed(Duration.zero);
    completeCurrentLoad();
  }

  Future<void> finishCurrentTrackAndAdvance() async {
    final duration = mediaItem.value?.duration ?? Duration.zero;
    playbackState.add(
      playbackState.value.copyWith(
        playing: true,
        processingState: AudioProcessingState.completed,
        updatePosition: duration,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await skipToNext();
  }

  void reportCurrentLoadBuffering({
    Duration reportedPosition = const Duration(milliseconds: 500),
  }) {
    playbackState.add(
      playbackState.value.copyWith(
        playing: true,
        processingState: AudioProcessingState.buffering,
        updatePosition: reportedPosition,
      ),
    );
  }

  void completeCurrentLoad() {
    playbackState.add(
      playbackState.value.copyWith(
        playing: true,
        processingState: AudioProcessingState.ready,
      ),
    );
  }
}

/// `Downloader.download()` on the real class ends in a genuine network fetch
/// through `ResolverClient` — fine on a device, but in a test it means the
/// tapped button's `await downloader.download(song)` doesn't return until a
/// real (failing) request times out, and `pumpAndSettle` keeps pumping for
/// every progress notification along the way. What the unliked-download-dialog
/// scenarios actually check is which songs were *asked* to download, not
/// whether the audio arrived — that boundary already has its own coverage
/// elsewhere — so this fake records the call and returns immediately.
class FakeDownloader extends Downloader {
  FakeDownloader(
    DownloadRepository downloadRepository,
    SettingsRepository settingsRepository,
  ) : super(downloadRepository, settingsRepository, ResolverClient());

  final downloadedSongs = <MediaItem>[];

  @override
  Future<void> download(MediaItem? song, {List<MediaItem>? songList}) async {
    if (song != null) downloadedSongs.add(song);
    if (songList != null) downloadedSongs.addAll(songList);
  }
}

/// A user, without any real Auth0 traffic. Configurable so a test can flip
/// between "restoring an existing session", "a fresh interactive login" and
/// "the session lapsed" — the three states account-switch detection and
/// sign-out visibility distinguish.
class FakeAuthService implements AuthServiceContract {
  /// What [tryRestoreSession] returns. Set to null to simulate a lapsed
  /// session on a device that was previously signed in.
  UserProfile? restorableSession;

  /// What [login] returns. Defaults to [restorableSession] when unset, since
  /// signing in as the same person you were already restoring is the common
  /// case; set explicitly to simulate signing in as a *different* account.
  UserProfile? nextLogin;

  int loginCallCount = 0;
  int logoutCallCount = 0;
  bool? lastChooseAccount;

  @override
  bool isConfigured = true;

  @override
  bool isSupportedPlatform = true;

  @override
  bool get isAvailable => isConfigured && isSupportedPlatform;

  @override
  Future<UserProfile?> tryRestoreSession() async => restorableSession;

  @override
  Future<UserProfile> login({bool chooseAccount = false}) async {
    loginCallCount++;
    lastChooseAccount = chooseAccount;
    final profile = nextLogin ?? restorableSession;
    if (profile == null) {
      throw StateError(
        'FakeAuthService.login() called with no nextLogin/restorableSession set',
      );
    }
    restorableSession = profile;
    return profile;
  }

  @override
  Future<void> logout() async {
    logoutCallCount++;
    restorableSession = null;
  }

  @override
  Future<String?> accessToken({bool forceRefresh = false}) async =>
      restorableSession == null ? null : 'fake-access-token';

  final _sessionRevoked = StreamController<void>.broadcast();

  @override
  Stream<void> get onSessionRevoked => _sessionRevoked.stream;

  /// Kills the session the way an expired refresh token does mid-run: the
  /// stored credentials are gone and everyone watching is told, without the
  /// app having been relaunched.
  void expireSession() {
    restorableSession = null;
    _sessionRevoked.add(null);
  }

  void dispose() => unawaited(_sessionRevoked.close());
}

/// A `UserProfile` with only the fields tests actually assert on populated.
UserProfile testUserProfile({required String sub, String? email}) =>
    UserProfile(sub: sub, email: email ?? '$sub@example.test');

/// A `Dio` whose HTTP layer never leaves the process. Cloud sync's network
/// calls (`registerDevice`, `sync`, `pause`) go through this instead of the
/// real Resolver, so tests exercise the real `CloudSyncCoordinator` and
/// `CloudSyncRepository` — the local wipe/merge/filter logic under test —
/// without the outcome depending on a live server. Server-side behaviour for
/// these endpoints already has its own coverage in the Cloud test suite.
Dio fakeCloudDio() => Dio()..httpClientAdapter = _FakeCloudHttpClientAdapter();

class _FakeCloudHttpClientAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    Map<String, dynamic>? json;
    var statusCode = 204;
    if (path.endsWith('/devices/register')) {
      statusCode = 200;
      json = {'deviceId': options.data is Map ? options.data['deviceId'] : ''};
    } else if (path.endsWith('/v1/sync')) {
      statusCode = 200;
      json = const {
        'checkpoint': 0,
        'acceptedEventIds': <String>[],
        'changes': <dynamic>[],
      };
    } else if (path.endsWith('/sync/pause') ||
        path.endsWith('/playback/presence')) {
      statusCode = 204;
    } else {
      // Anything else this scenario didn't anticipate: succeed emptily rather
      // than fail the test on an unrelated background call (FCM token
      // registration, playback presence, ...).
      statusCode = 204;
    }
    final body = json == null ? <int>[] : utf8.encode(jsonEncode(json));
    return ResponseBody.fromBytes(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
