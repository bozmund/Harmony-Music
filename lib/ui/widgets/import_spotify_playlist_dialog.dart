import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import '/services/app_platform_service.dart';
import '/services/file_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

import '../../app/providers/controller_providers.dart';
import '../screens/Library/library_controller.dart';
import 'common_dialog_widget.dart';

class ImportSpotifyPlaylistDialogController extends ChangeNotifier {
  ImportSpotifyPlaylistDialogController(this._libraryPlaylistsController);

  static const spotifyDataPageUrl = 'https://www.spotify.com/account/privacy/';

  final LibraryPlaylistsController _libraryPlaylistsController;
  var isReading = false;
  var isImporting = false;
  final status = _TextState(
    "Select a Spotify data export ZIP, Playlist JSON, or library JSON",
  );
  String? error;
  final detectedPlaylists = <SpotifyImportPlaylist>[];
  final selectedIndexes = <int>{};
  SpotifyPlaylistImportResult? result;
  var unsupportedItemCount = 0;

  Future<void> pickExport() async {
    if (isReading || isImporting) return;

    error = null;
    result = null;
    detectedPlaylists.clear();
    selectedIndexes.clear();
    unsupportedItemCount = 0;
    isReading = true;
    status.value = "Reading export";
    notifyListeners();

    try {
      final picked = await FilePickerService.openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Spotify export',
            extensions: ['zip', 'json'],
          ),
        ],
        confirmButtonText: "Import Spotify export",
      );

      if (picked == null) {
        status.value =
            "Select a Spotify data export ZIP, Playlist JSON, or library JSON";
        notifyListeners();
        return;
      }

      status.value = "Parsing Spotify data";
      notifyListeners();
      final parsed = await _parseSpotifyExport(File(picked.path));
      if (parsed.playlists.isEmpty) {
        throw const SpotifyPlaylistImportException(
          "No playlists or library songs found",
        );
      }

      detectedPlaylists
        ..clear()
        ..addAll(parsed.playlists);
      selectedIndexes
        ..clear()
        ..addAll(List.generate(parsed.playlists.length, (index) => index));
      unsupportedItemCount = parsed.unsupportedItemCount;
      status.value = "Choose playlists to import";
    } on SpotifyPlaylistImportException catch (e) {
      error = e.message;
      status.value = "Import failed";
    } catch (e) {
      error = "Invalid Spotify export file";
      status.value = "Import failed";
    } finally {
      isReading = false;
      notifyListeners();
    }
  }

  Future<void> importSelectedPlaylists() async {
    if (isReading || isImporting) return;

    final selected = selectedIndexes
        .where((index) => index >= 0 && index < detectedPlaylists.length)
        .map((index) => detectedPlaylists[index])
        .toList();
    if (selected.isEmpty) {
      error = "No selected playlists";
      notifyListeners();
      return;
    }

    error = null;
    result = null;
    isImporting = true;
    notifyListeners();

    try {
      result = await _libraryPlaylistsController.importSpotifyPlaylists(
        selected,
        onStatus: (value) {
          status.value = value;
          notifyListeners();
        },
      );
      status.value = "Completed";
    } on SpotifyPlaylistImportException catch (e) {
      error = e.message;
      status.value = "Import failed";
    } catch (e) {
      error = "Network/search error during matching";
      status.value = "Import failed";
    } finally {
      isImporting = false;
      notifyListeners();
    }
  }

  void togglePlaylist(int index, bool selected) {
    final next = selectedIndexes.toSet();
    if (selected) {
      next.add(index);
    } else {
      next.remove(index);
    }
    selectedIndexes
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  Future<void> openSpotifyDataPage() async {
    await AppPlatformService.openUrl(spotifyDataPageUrl);
  }

  Future<_ParsedSpotifyExport> _parseSpotifyExport(File file) async {
    final extension = path.extension(file.path).toLowerCase();
    if (extension == '.json') {
      return _parseSpotifyPlaylistJson(await file.readAsString());
    }
    if (extension == '.zip') {
      final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
      final playlists = <SpotifyImportPlaylist>[];
      var unsupportedItems = 0;

      for (final archiveFile in archive.files) {
        final fileName = archiveFile.name
            .split(RegExp(r'[\\/]'))
            .last
            .toLowerCase();
        if (!archiveFile.isFile || !fileName.endsWith('.json')) {
          continue;
        }

        final jsonString = _tryDecodeSpotifyArchiveJson(archiveFile);
        if (jsonString == null) {
          continue;
        }

        final parsed = _tryParseSpotifyJson(jsonString);
        if (parsed == null) {
          continue;
        }
        playlists.addAll(parsed.playlists);
        unsupportedItems += parsed.unsupportedItemCount;
      }

      return _ParsedSpotifyExport(
        playlists: playlists,
        unsupportedItemCount: unsupportedItems,
      );
    }

    throw const SpotifyPlaylistImportException("Invalid Spotify export file");
  }

  _ParsedSpotifyExport _parseSpotifyPlaylistJson(String jsonString) {
    return _parseSpotifyJson(jsonString);
  }

  String? _tryDecodeSpotifyArchiveJson(ArchiveFile archiveFile) {
    try {
      return utf8.decode((archiveFile.content as List).cast<int>());
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  _ParsedSpotifyExport? _tryParseSpotifyJson(String jsonString) {
    try {
      return _parseSpotifyJson(jsonString, strict: false);
    } on FormatException {
      return null;
    } on SpotifyPlaylistImportException {
      return null;
    } on TypeError {
      return null;
    }
  }

  _ParsedSpotifyExport _parseSpotifyJson(
    String jsonString, {
    bool strict = true,
  }) {
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map) {
      throw const SpotifyPlaylistImportException("Invalid Spotify export file");
    }

    final playlists = <SpotifyImportPlaylist>[];
    var unsupportedItems = 0;

    if (decoded['playlists'] is List) {
      for (final playlistJson in decoded['playlists']) {
        if (playlistJson is! Map) continue;

        final name = playlistJson['name'];
        final items = playlistJson['items'];
        if (name is! String || name.trim().isEmpty || items is! List) continue;

        final tracks = <SpotifyImportTrack>[];
        for (final item in items) {
          final track = item is Map
              ? _parseSpotifyTrackMap(
                  item['track'] is Map ? item['track'] : item,
                )
              : null;
          if (track == null) {
            unsupportedItems++;
            continue;
          }

          tracks.add(track);
        }

        if (tracks.isNotEmpty) {
          playlists.add(
            SpotifyImportPlaylist(
              name: name.trim(),
              description: playlistJson['description'] is String
                  ? (playlistJson['description'] as String).trim()
                  : null,
              tracks: tracks,
            ),
          );
        }
      }
    }

    final libraryTracks = _parseSpotifyLibraryTracks(decoded);
    unsupportedItems += libraryTracks.unsupportedItemCount;
    if (libraryTracks.tracks.isNotEmpty) {
      playlists.add(
        SpotifyImportPlaylist(
          name: "Spotify Liked Songs",
          description: "Imported Spotify saved library songs",
          tracks: libraryTracks.tracks,
        ),
      );
    }

    if (strict && playlists.isEmpty) {
      throw const SpotifyPlaylistImportException("Invalid Spotify export file");
    }

    return _ParsedSpotifyExport(
      playlists: playlists,
      unsupportedItemCount: unsupportedItems,
    );
  }

  _ParsedSpotifyLibraryTracks _parseSpotifyLibraryTracks(Map decoded) {
    final rawTracks = decoded['tracks'];
    if (rawTracks is! List) {
      return const _ParsedSpotifyLibraryTracks(
        tracks: [],
        unsupportedItemCount: 0,
      );
    }

    final tracks = <SpotifyImportTrack>[];
    var unsupportedItems = 0;
    for (final item in rawTracks) {
      final track = item is Map
          ? _parseSpotifyTrackMap(item['track'] is Map ? item['track'] : item)
          : null;
      if (track == null) {
        unsupportedItems++;
        continue;
      }
      tracks.add(track);
    }

    return _ParsedSpotifyLibraryTracks(
      tracks: tracks,
      unsupportedItemCount: unsupportedItems,
    );
  }

  SpotifyImportTrack? _parseSpotifyTrackMap(Map track) {
    final trackName = _spotifyString(
      track['trackName'] ?? track['track'] ?? track['name'] ?? track['title'],
    );
    final artistName = _spotifyString(
      track['artistName'] ?? track['artist'] ?? track['artists'],
    );
    if (trackName == null || artistName == null) return null;

    return SpotifyImportTrack(
      trackName: trackName,
      artistName: artistName,
      albumName: _spotifyString(track['albumName'] ?? track['album']),
      trackUri: _spotifyString(track['trackUri'] ?? track['uri']),
    );
  }

  String? _spotifyString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    if (value is List) {
      final parts = value
          .map(_spotifyString)
          .whereType<String>()
          .where((part) => part.isNotEmpty)
          .toList();
      if (parts.isNotEmpty) return parts.join(", ");
    }
    return null;
  }
}

class _TextState {
  _TextState(this.value);

  String value;
}

class _ParsedSpotifyExport {
  const _ParsedSpotifyExport({
    required this.playlists,
    required this.unsupportedItemCount,
  });

  final List<SpotifyImportPlaylist> playlists;
  final int unsupportedItemCount;
}

class _ParsedSpotifyLibraryTracks {
  const _ParsedSpotifyLibraryTracks({
    required this.tracks,
    required this.unsupportedItemCount,
  });

  final List<SpotifyImportTrack> tracks;
  final int unsupportedItemCount;
}

class ImportSpotifyPlaylistDialog extends ConsumerStatefulWidget {
  const ImportSpotifyPlaylistDialog({super.key});

  @override
  ConsumerState<ImportSpotifyPlaylistDialog> createState() =>
      _ImportSpotifyPlaylistDialogState();
}

class _ImportSpotifyPlaylistDialogState
    extends ConsumerState<ImportSpotifyPlaylistDialog> {
  late final ImportSpotifyPlaylistDialogController controller;

  @override
  void initState() {
    super.initState();
    controller = ImportSpotifyPlaylistDialogController(
      ref.read(libraryPlaylistsControllerProvider),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Import Spotify export",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 14),
                Text(
                  "To import from Spotify, open Spotify's data/privacy page and "
                  "request your account data. Spotify will prepare a download "
                  "for you. When it is ready, download the ZIP file and choose "
                  "it here to import your liked songs and playlists at once.",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  "You can also choose a single Spotify Playlist JSON or Library "
                  "JSON file if you already extracted the ZIP.",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: controller.isReading || controller.isImporting
                        ? null
                        : controller.openSpotifyDataPage,
                    child: const Text("Open Spotify data page"),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  controller.status.value,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                if (controller.isReading || controller.isImporting) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 14),
                ],
                if (controller.detectedPlaylists.isNotEmpty &&
                    controller.result == null) ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: controller.detectedPlaylists.length,
                      itemBuilder: (context, index) {
                        final playlist = controller.detectedPlaylists[index];
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: controller.selectedIndexes.contains(index),
                          onChanged: controller.isImporting
                              ? null
                              : (value) => controller.togglePlaylist(
                                  index,
                                  value ?? false,
                                ),
                          title: Text(playlist.name),
                          subtitle: Text("${playlist.tracks.length} tracks"),
                        );
                      },
                    ),
                  ),
                  if (controller.unsupportedItemCount > 0)
                    Text(
                      "${controller.unsupportedItemCount} non-song items ignored",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 12),
                ],
                if (controller.error != null) ...[
                  Text(
                    controller.error!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (controller.result != null) ...[
                  Text(
                    "${controller.result!.playlistsImported} playlists imported\n"
                    "${controller.result!.importedSongCount} songs imported\n"
                    "${controller.result!.conflictAddedCount} conflicts added\n"
                    "${controller.result!.reviewAddedCount} weak matches added to review\n"
                    "${controller.result!.skippedTrackCount} tracks skipped"
                    "${controller.unsupportedItemCount > 0 ? "\n${controller.unsupportedItemCount} non-song items ignored" : ""}",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  alignment: WrapAlignment.end,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: controller.isReading || controller.isImporting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(
                        controller.result == null ? "Cancel" : "Close",
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: controller.isReading || controller.isImporting
                          ? null
                          : controller.pickExport,
                      child: Text(
                        controller.detectedPlaylists.isEmpty
                            ? "Choose file"
                            : "Choose another",
                      ),
                    ),
                    if (controller.detectedPlaylists.isNotEmpty &&
                        controller.result == null) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: controller.isImporting
                            ? null
                            : controller.importSelectedPlaylists,
                        child: const Text("Import"),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
