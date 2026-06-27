import 'package:audio_service/audio_service.dart';
import 'package:file_selector/file_selector.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/app_contracts.dart';
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

class FakeMusicService extends GetxService implements MusicServiceContract {
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

class FakeDownloader extends GetxService implements DownloaderContract {
  @override
  MediaItem? currentSong;
  final downloaded = <String>[];
  final cancelled = <String>[];

  @override
  Future<void> download(MediaItem? song, {List<MediaItem>? songList}) async {
    currentSong =
        song ?? (songList == null || songList.isEmpty ? null : songList.first);
    downloaded.addAll((songList ?? [?song]).map((e) => e.id));
  }

  @override
  Future<void> downloadPlaylist(String playlistId, List<MediaItem> songList) {
    downloaded.addAll(songList.map((e) => e.id));
    return Future.value();
  }

  @override
  void cancelSongDownload(MediaItem song) {
    cancelled.add(song.id);
  }
}

class FakeUpdateService implements UpdateServiceContract {
  const FakeUpdateService({this.rollingSha = 'remote-sha'});

  final String rollingSha;

  @override
  Future<UpdateInfo?> checkNewVersion(
    String currentVersion, {
    UpdateChannel channel = UpdateChannel.stable,
  }) async {
    if (channel == UpdateChannel.stable) return null;
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
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    return directoryPath;
  }
}

class FakeAudioHandler extends BaseAudioHandler {
  FakeAudioHandler() {
    playbackState.add(
      PlaybackState(
        controls: const [],
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    queue.add(const []);
  }

  @override
  Future<void> updateQueue(List<MediaItem> newQueue) async {
    queue.add(newQueue);
    if (newQueue.isNotEmpty) mediaItem.add(newQueue.first);
  }

  @override
  Future<void> play() async {
    playbackState.add(playbackState.value.copyWith(playing: true));
  }

  @override
  Future<void> pause() async {
    playbackState.add(playbackState.value.copyWith(playing: false));
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) {
    final item = extras?['mediaItem'];
    if (item is MediaItem) {
      mediaItem.add(item);
      queue.add([item]);
    }
    if (name == 'playByIndex') {
      final index = extras?['index'] as int? ?? 0;
      final currentQueue = queue.value;
      if (index >= 0 && index < currentQueue.length) {
        mediaItem.add(currentQueue[index]);
      }
    }
    return Future.value(null);
  }
}
