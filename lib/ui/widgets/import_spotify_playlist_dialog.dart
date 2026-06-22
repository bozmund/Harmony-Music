import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as path;

import '../screens/Library/library_controller.dart';
import 'common_dialog_widget.dart';

class ImportSpotifyPlaylistDialogController extends GetxController {
  final isReading = false.obs;
  final isImporting = false.obs;
  final status = "Select a Spotify data export ZIP or Playlist JSON".obs;
  final error = RxnString();
  final detectedPlaylists = <SpotifyImportPlaylist>[].obs;
  final selectedIndexes = <int>{}.obs;
  final result = Rxn<SpotifyPlaylistImportResult>();
  final unsupportedItemCount = 0.obs;

  Future<void> pickExport() async {
    if (isReading.value || isImporting.value) return;

    error.value = null;
    result.value = null;
    detectedPlaylists.clear();
    selectedIndexes.clear();
    unsupportedItemCount.value = 0;
    isReading.value = true;
    status.value = "Reading export";

    try {
      final picked = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Spotify export',
            extensions: ['zip', 'json'],
          ),
        ],
        confirmButtonText: "Import Spotify playlist export",
      );

      if (picked == null) {
        status.value = "Select a Spotify data export ZIP or Playlist JSON";
        return;
      }

      status.value = "Parsing playlists";
      final parsed = await _parseSpotifyExport(File(picked.path));
      if (parsed.playlists.isEmpty) {
        throw const SpotifyPlaylistImportException("No playlists found");
      }

      detectedPlaylists.value = parsed.playlists;
      selectedIndexes
        ..clear()
        ..addAll(List.generate(parsed.playlists.length, (index) => index));
      selectedIndexes.refresh();
      unsupportedItemCount.value = parsed.unsupportedItemCount;
      status.value = "Choose playlists to import";
    } on SpotifyPlaylistImportException catch (e) {
      error.value = e.message;
      status.value = "Import failed";
    } catch (e) {
      error.value = "Invalid Spotify export file";
      status.value = "Import failed";
    } finally {
      isReading.value = false;
    }
  }

  Future<void> importSelectedPlaylists() async {
    if (isReading.value || isImporting.value) return;

    final selected = selectedIndexes
        .where((index) => index >= 0 && index < detectedPlaylists.length)
        .map((index) => detectedPlaylists[index])
        .toList();
    if (selected.isEmpty) {
      error.value = "No selected playlists";
      return;
    }

    error.value = null;
    result.value = null;
    isImporting.value = true;

    try {
      result.value = await Get.find<LibraryPlaylistsController>()
          .importSpotifyPlaylists(
            selected,
            onStatus: (value) => status.value = value,
          );
      status.value = "Completed";
    } on SpotifyPlaylistImportException catch (e) {
      error.value = e.message;
      status.value = "Import failed";
    } catch (e) {
      error.value = "Network/search error during matching";
      status.value = "Import failed";
    } finally {
      isImporting.value = false;
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
    selectedIndexes.refresh();
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
        if (!archiveFile.isFile ||
            !fileName.startsWith('playlist') ||
            !fileName.endsWith('.json')) {
          continue;
        }

        final parsed = _parseSpotifyPlaylistJson(
          utf8.decode((archiveFile.content as List).cast<int>()),
        );
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
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map || decoded['playlists'] is! List) {
      throw const SpotifyPlaylistImportException("Invalid Spotify export file");
    }

    final playlists = <SpotifyImportPlaylist>[];
    var unsupportedItems = 0;

    for (final playlistJson in decoded['playlists']) {
      if (playlistJson is! Map) continue;

      final name = playlistJson['name'];
      final items = playlistJson['items'];
      if (name is! String || name.trim().isEmpty || items is! List) continue;

      final tracks = <SpotifyImportTrack>[];
      for (final item in items) {
        if (item is! Map || item['track'] is! Map) {
          unsupportedItems++;
          continue;
        }

        final track = item['track'] as Map;
        final trackName = track['trackName'];
        final artistName = track['artistName'];
        if (trackName is! String ||
            trackName.trim().isEmpty ||
            artistName is! String ||
            artistName.trim().isEmpty) {
          unsupportedItems++;
          continue;
        }

        tracks.add(
          SpotifyImportTrack(
            trackName: trackName.trim(),
            artistName: artistName.trim(),
            albumName: track['albumName'] is String
                ? (track['albumName'] as String).trim()
                : null,
            trackUri: track['trackUri'] is String
                ? (track['trackUri'] as String).trim()
                : null,
          ),
        );
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

    return _ParsedSpotifyExport(
      playlists: playlists,
      unsupportedItemCount: unsupportedItems,
    );
  }
}

class _ParsedSpotifyExport {
  const _ParsedSpotifyExport({
    required this.playlists,
    required this.unsupportedItemCount,
  });

  final List<SpotifyImportPlaylist> playlists;
  final int unsupportedItemCount;
}

class ImportSpotifyPlaylistDialog extends StatelessWidget {
  const ImportSpotifyPlaylistDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<ImportSpotifyPlaylistDialogController>()
        ? Get.find<ImportSpotifyPlaylistDialogController>()
        : Get.put(ImportSpotifyPlaylistDialogController());

    return CommonDialog(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Obx(
          () => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Import Spotify playlist export",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              Text(
                controller.status.value,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              if (controller.isReading.value ||
                  controller.isImporting.value) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 14),
              ],
              if (controller.detectedPlaylists.isNotEmpty &&
                  controller.result.value == null) ...[
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
                        onChanged: controller.isImporting.value
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
                if (controller.unsupportedItemCount.value > 0)
                  Text(
                    "${controller.unsupportedItemCount.value} non-song items ignored",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 12),
              ],
              if (controller.error.value != null) ...[
                Text(
                  controller.error.value!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (controller.result.value != null) ...[
                Text(
                  "${controller.result.value!.playlistsImported} playlists imported\n"
                  "${controller.result.value!.importedSongCount} songs imported\n"
                  "${controller.result.value!.conflictAddedCount} conflicts added\n"
                  "${controller.result.value!.reviewAddedCount} weak matches added to review\n"
                  "${controller.result.value!.skippedTrackCount} tracks skipped"
                  "${controller.unsupportedItemCount.value > 0 ? "\n${controller.unsupportedItemCount.value} non-song items ignored" : ""}",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
              ],
              Wrap(
                alignment: WrapAlignment.end,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed:
                        controller.isReading.value ||
                            controller.isImporting.value
                        ? null
                        : () => Get.back(),
                    child: Text(
                      controller.result.value == null ? "Cancel" : "Close",
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed:
                        controller.isReading.value ||
                            controller.isImporting.value
                        ? null
                        : controller.pickExport,
                    child: Text(
                      controller.detectedPlaylists.isEmpty
                          ? "Choose file"
                          : "Choose another",
                    ),
                  ),
                  if (controller.detectedPlaylists.isNotEmpty &&
                      controller.result.value == null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: controller.isImporting.value
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
    );
  }
}
