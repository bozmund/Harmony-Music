import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:hive/hive.dart';

import '../../domain/repositories/playlist_repository.dart';
import '../../services/cloud/cloud_sync_event.dart';
import '../../services/constant.dart';

class CloudSyncRepository {
  CloudSyncRepository(this._playlists);

  final PlaylistRepository _playlists;

  Box get _outbox => Hive.box(BoxNames.cloudSyncOutbox);
  Box get _state => Hive.box(BoxNames.cloudSyncState);
  Box get _prefs => Hive.box(BoxNames.appPrefs);

  /// Boxes that belong to the account rather than to this installation.
  ///
  /// Deliberately absent, because they describe *this device* and mean nothing
  /// (or the wrong thing) elsewhere:
  /// - [BoxNames.songDownloads] — downloads are per device. Syncing the record
  ///   without the audio made other devices report songs as downloaded that
  ///   they had no file for, and blocked re-downloading them.
  /// - [BoxNames.libFavNotDownloaded] — a view derived from local downloads.
  /// - [BoxNames.prevSessionData] — the queue this device resumes to; cross
  ///   device continuity is the playback session's job.
  /// - [BoxNames.libImportDuplicates] / [BoxNames.libImportReview] — the review
  ///   queue of an import running on one device. The playlists it produces do
  ///   sync; the workflow state does not.
  /// - [BoxNames.lyrics] — a refetchable cache.
  static const _staticBoxes = <String>[
    BoxNames.libFav,
    BoxNames.libRP,
    BoxNames.libraryPlaylists,
    BoxNames.libraryAlbums,
    BoxNames.libraryArtists,
    BoxNames.librarySearches,
    BoxNames.blacklistedPlaylist,
    BoxNames.searchQuery,
    BoxNames.appPrefs,
  ];

  /// Wire domain per synced box. The server stores each domain in its own
  /// tables, so this is what keeps a theme colour out of the songs table.
  /// A per-playlist song box is named after its playlist id and so falls
  /// through to [_playlistSongsDomain].
  static const _domainByBox = <String, String>{
    BoxNames.appPrefs: 'settings',
    BoxNames.libFav: 'favourites',
    BoxNames.libRP: 'recentlyPlayed',
    BoxNames.libraryPlaylists: 'playlists',
    BoxNames.libraryAlbums: 'albums',
    BoxNames.libraryArtists: 'artists',
    BoxNames.librarySearches: 'savedSearches',
    BoxNames.searchQuery: 'searchHistory',
    BoxNames.blacklistedPlaylist: 'blacklistedPlaylists',
  };

  static const _playlistSongsDomain = 'playlistSongs';

  /// Bumped when the server's storage layout changes in a way that requires a
  /// full re-upload. [_resetForSchemaChange] then clears the local fingerprints
  /// and checkpoint once, so this device re-sends everything it has.
  static const _syncSchemaVersion = 2;

  static String domainForBox(String boxName) =>
      _domainByBox[boxName] ?? _playlistSongsDomain;

  /// Boxes holding the songs of a saved playlist or album.
  ///
  /// Each is named after its container's id, so they cannot be listed
  /// statically. Albums matter as much as playlists here and were missing:
  /// saving an album synced its entry in [BoxNames.libraryAlbums] but never its
  /// contents, so another device showed the album and opened it empty.
  ///
  /// Album ids come from the album box's own keys, which `saveAlbum` writes as
  /// the browse id — no extra repository dependency needed.
  Future<Set<String>> _songContainerBoxes() async {
    final albums = Hive.isBoxOpen(BoxNames.libraryAlbums)
        ? Hive.box(BoxNames.libraryAlbums)
        : await Hive.openBox(BoxNames.libraryAlbums);
    return {
      for (final playlist in await _playlists.getPlaylists())
        playlist.playlistId,
      for (final key in albums.keys) key.toString(),
    };
  }

  static const _excludedPreferenceKeys = <String>{
    PrefKeys.downloadLocationPath,
    PrefKeys.exportLocationPath,
    PrefKeys.visitorId,
    PrefKeys.piped,
    PrefKeys.resolverDebugOverride,
    PrefKeys.resolverProductionOverride,
    PrefKeys.cloudDeviceId,
    PrefKeys.cloudCheckpoint,
    PrefKeys.cloudDeviceSequence,
    // Per-device sync bookkeeping. If this synced, one device's value would
    // land on another and suppress the re-upload the reset exists to force.
    PrefKeys.cloudSyncSchemaVersion,
    // Same reasoning: a device that has not yet purged its thin cached songs
    // must not be told it already did.
    PrefKeys.songCachePurgeVersion,
    // Which account owns this device's library. Syncing it would let one
    // device tell another it belongs to a different account than it does,
    // defeating the switch detection entirely.
    PrefKeys.cloudAccountSubject,
    // Songs filters describe this device's local files; two devices hold
    // different downloads, so one view must not be imposed on the other.
    PrefKeys.songsShowUnlikedDownloads,
    PrefKeys.songsIncludeCached,
    PrefKeys.unlikedDownloadNoticeDismissed,
    // Whether a device advertises what it is playing is that device's own
    // disclosure to make. Syncing it would let switching it on here switch it
    // on everywhere, opting other devices into broadcasting without anyone
    // agreeing to it there.
    PrefKeys.shareNowPlaying,
  };

  bool get enabled => _prefs.get(PrefKeys.cloudSyncEnabled) == true;
  bool get optInAnswered => _prefs.get(PrefKeys.cloudOptInAnswered) == true;

  /// Off by default: advertising what you are playing is a disclosure, so it
  /// is opted into rather than out of.
  bool get shareNowPlaying => _prefs.get(PrefKeys.shareNowPlaying) == true;

  Future<void> setShareNowPlaying(bool value) =>
      _prefs.put(PrefKeys.shareNowPlaying, value);
  String get deviceId {
    final current = _prefs.get(PrefKeys.cloudDeviceId)?.toString();
    if (current != null && current.isNotEmpty) return current;
    final generated = _uuid();
    unawaited(_prefs.put(PrefKeys.cloudDeviceId, generated));
    return generated;
  }

  int get checkpoint => _prefs.get(PrefKeys.cloudCheckpoint) as int? ?? 0;

  Future<void> setEnabled(bool value) async {
    await _prefs.put(PrefKeys.cloudOptInAnswered, true);
    await _prefs.put(PrefKeys.cloudSyncEnabled, value);
  }

  /// Drops locally cached sync bookkeeping once after the server's storage
  /// layout changes, so the next scan re-uploads the whole library instead of
  /// assuming the server still holds what the fingerprints say it does.
  ///
  /// [PrefKeys.cloudDeviceSequence] is deliberately left alone. The server
  /// remembers the highest sequence this device has ever sent, and that memory
  /// survives a storage wipe, so restarting the counter makes every event look
  /// like a replay of one already seen.
  Future<void> _resetForSchemaChange() async {
    final stored = _prefs.get(PrefKeys.cloudSyncSchemaVersion) as int? ?? 0;
    if (stored == _syncSchemaVersion) return;
    await _state.clear();
    await _outbox.clear();
    await _prefs.put(PrefKeys.cloudCheckpoint, 0);
    await _prefs.put(PrefKeys.cloudSyncSchemaVersion, _syncSchemaVersion);
  }

  /// Clears everything belonging to the account this device was signed into,
  /// so a different account starts from nothing.
  ///
  /// Deliberately keeps:
  /// - downloaded audio and the song cache, which are device-local; the Songs
  ///   filter decides what is visible, and switching back must not cost a
  ///   multi-gigabyte re-download
  /// - [PrefKeys.cloudDeviceId], because devices are scoped per account
  ///   server-side, so the same id under a new account is simply a new row
  /// - [BoxNames.appPrefs] as a whole, which holds that device identity and the
  ///   sync bookkeeping; the new account's settings arrive per key by syncing
  ///
  /// The checkpoint reset is not optional. `changes` is `revision > checkpoint`
  /// and the server's revision sequence is shared across accounts, so the old
  /// account's checkpoint sits arbitrarily far ahead of the new account's
  /// history — leaving it would filter that history out entirely.
  Future<void> forgetAccountLibrary() async {
    for (final boxName in {
      ..._syncedLibraryBoxes,
      ...await _songContainerBoxes(),
    }) {
      final box = Hive.isBoxOpen(boxName)
          ? Hive.box(boxName)
          : await Hive.openBox(boxName);
      await box.clear();
    }
    await _state.clear();
    await _outbox.clear();
    await _prefs.put(PrefKeys.cloudCheckpoint, 0);
  }

  /// The synced boxes that hold library content, i.e. everything in
  /// [_staticBoxes] except [BoxNames.appPrefs], which is settings.
  static const _syncedLibraryBoxes = <String>[
    BoxNames.libFav,
    BoxNames.libRP,
    BoxNames.libraryPlaylists,
    BoxNames.libraryAlbums,
    BoxNames.libraryArtists,
    BoxNames.librarySearches,
    BoxNames.blacklistedPlaylist,
    BoxNames.searchQuery,
  ];

  /// Calls [onChange] whenever a synced box is written to locally.
  ///
  /// Without this nothing observes the library: liking a song wrote to Hive and
  /// stopped there, because a scan only ran at app start, and the change sat on
  /// the device until it was next launched. Watching the boxes catches every
  /// mutation path, including ones added later, instead of needing a sync call
  /// wired into each of them.
  ///
  /// Writes made by [applyRemote] are ignored — they came from the server, and
  /// re-uploading them would be pointless churn.
  Future<StreamSubscription<void>> watchLocalChanges(
    void Function() onChange,
  ) async {
    final boxes = <String>{..._staticBoxes, ...await _songContainerBoxes()};
    final controller = StreamController<void>.broadcast();
    final sources = <StreamSubscription<void>>[];
    for (final boxName in boxes) {
      final box = Hive.isBoxOpen(boxName)
          ? Hive.box(boxName)
          : await Hive.openBox(boxName);
      sources.add(
        box.watch().listen((_) {
          if (_applyingRemote) return;
          controller.add(null);
        }),
      );
    }
    final subscription = controller.stream.listen((_) => onChange());
    subscription.onDone(() {
      for (final source in sources) {
        unawaited(source.cancel());
      }
      unawaited(controller.close());
    });
    return subscription;
  }

  bool _applyingRemote = false;

  Future<List<CloudSyncEvent>> scan() async {
    await _resetForSchemaChange();
    final currentEntities = <String>{};
    final boxes = <String>{..._staticBoxes, ...await _songContainerBoxes()};

    for (final boxName in boxes) {
      final box = Hive.isBoxOpen(boxName)
          ? Hive.box(boxName)
          : await Hive.openBox(boxName);
      for (final key in box.keys) {
        if (boxName == BoxNames.appPrefs &&
            _excludedPreferenceKeys.contains(key.toString())) {
          continue;
        }
        final encodedKey = base64UrlEncode(utf8.encode(jsonEncode(key)));
        final entityId = '$boxName:$encodedKey';
        currentEntities.add(entityId);
        final sanitized = _sanitize(box.get(key));
        final fingerprint = stableFingerprint(canonicalJson(sanitized));
        if (_state.get('fingerprint:$entityId') == fingerprint) continue;
        await _enqueue(entityId, 'upsert', sanitized, domainForBox(boxName));
        await _state.put('fingerprint:$entityId', fingerprint);
      }
    }

    final known = _state.keys
        .map((key) => key.toString())
        .where((key) => key.startsWith('fingerprint:'))
        .map((key) => key.substring('fingerprint:'.length))
        .toList();
    for (final entityId in known) {
      if (currentEntities.contains(entityId)) continue;
      final separator = entityId.indexOf(':');
      final boxName = separator <= 0
          ? entityId
          : entityId.substring(0, separator);
      await _enqueue(
        entityId,
        'delete',
        const <String, Object?>{},
        domainForBox(boxName),
      );
      await _state.delete('fingerprint:$entityId');
    }
    return pending();
  }

  List<CloudSyncEvent> pending() =>
      _outbox.values.map(CloudSyncEvent.fromJson).toList()..sort(
        (left, right) => left.deviceSequence.compareTo(right.deviceSequence),
      );

  Future<void> acknowledge(
    Iterable<String> eventIds,
    int nextCheckpoint,
  ) async {
    final accepted = eventIds.toSet();
    for (final key in _outbox.keys.toList()) {
      final value = _outbox.get(key);
      if (value is Map && accepted.contains(value['eventId'])) {
        await _outbox.delete(key);
      }
    }
    await _prefs.put(PrefKeys.cloudCheckpoint, nextCheckpoint);
  }

  /// Writes remote changes into their boxes and reports which boxes changed,
  /// so callers can refresh whatever is on screen. Without that the data lands
  /// silently: an album added on another device sits in Hive while the Albums
  /// tab keeps showing the list it read when it was opened.
  Future<Set<String>> applyRemote(List<dynamic> changes) async {
    _applyingRemote = true;
    try {
      return await _applyRemote(changes);
    } finally {
      _applyingRemote = false;
    }
  }

  Future<Set<String>> _applyRemote(List<dynamic> changes) async {
    final touched = <String>{};
    // Resolved once rather than per change, but re-read on a miss: a batch
    // carries a new playlist or album before the songs that belong to it, and
    // those songs would otherwise be rejected as an unknown box.
    var containers = await _songContainerBoxes();
    for (final raw in changes) {
      final change = Map<String, dynamic>.from(raw as Map);
      final entityId = change['entityId'] as String;
      final separator = entityId.indexOf(':');
      if (separator <= 0) continue;
      final boxName = entityId.substring(0, separator);
      dynamic key;
      try {
        key = jsonDecode(
          utf8.decode(base64Url.decode(entityId.substring(separator + 1))),
        );
      } on FormatException {
        continue;
      }
      if (!_staticBoxes.contains(boxName) && !containers.contains(boxName)) {
        containers = await _songContainerBoxes();
        if (!containers.contains(boxName)) continue;
      }
      if (boxName == BoxNames.appPrefs &&
          _excludedPreferenceKeys.contains(key)) {
        continue;
      }
      final box = Hive.isBoxOpen(boxName)
          ? Hive.box(boxName)
          : await Hive.openBox(boxName);
      if (change['operation'] == 'delete') {
        await box.delete(key);
        await _state.delete('fingerprint:$entityId');
      } else {
        final payload = change['payload'];
        await box.put(key, payload);
        await _state.put(
          'fingerprint:$entityId',
          stableFingerprint(canonicalJson(payload)),
        );
      }
      touched.add(boxName);
    }
    return touched;
  }

  Future<void> _enqueue(
    String entityId,
    String operation,
    Object? payload,
    String domain,
  ) async {
    final sequence =
        (_prefs.get(PrefKeys.cloudDeviceSequence) as int? ?? 0) + 1;
    await _prefs.put(PrefKeys.cloudDeviceSequence, sequence);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final event = CloudSyncEvent(
      eventId: _uuid(),
      deviceSequence: sequence,
      hlcPhysicalMs: now,
      hlcLogical: 0,
      entityType: domain,
      entityId: entityId,
      operation: operation,
      payload: payload,
    );
    await _outbox.put(sequence, event.toJson());
  }

  Object? _sanitize(Object? value, {bool artworkContext = false}) {
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final normalizedKey = key.toLowerCase().replaceAll('_', '');
        final isArtworkUrl = artworkContext && normalizedKey == 'url';
        if (_excludedPayloadKeys.contains(normalizedKey) && !isArtworkUrl) {
          continue;
        }
        final childArtworkContext =
            normalizedKey == 'thumbnails' ||
            normalizedKey == 'thumbnail' ||
            normalizedKey == 'artwork' ||
            normalizedKey == 'arturi' ||
            normalizedKey == 'image';
        result[key] = _sanitize(
          entry.value,
          artworkContext: artworkContext || childArtworkContext,
        );
      }
      // Real artwork URLs now survive the round trip, so an entry without any
      // is genuinely artwork-less. MediaItemBuilder.fromJson already derives
      // the id-based fallback at read time; synthesizing it into the payload
      // is what pushed letterboxed covers into every synced library.
      return result;
    }
    if (value is Iterable) {
      return value
          .map((item) => _sanitize(item, artworkContext: artworkContext))
          .toList();
    }
    return value;
  }

  static const _excludedPayloadKeys = <String>{
    'url',
    'streaminfo',
    'visitorid',
    'filepath',
    'localpath',
    'downloadpath',
    'accesstoken',
    'refreshtoken',
    'clientsecret',
    'password',
    'authorization',
  };

  String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
