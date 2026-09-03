import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where cached song audio lives.
///
/// Application support, not the temporary directory. The Cache Songs setting
/// promises "future/offline playback" and the Songs library lists these files
/// directly, so putting them somewhere the OS may reclaim — Storage Sense on
/// Windows, cache reclamation on Android — silently removed songs the user
/// could see, and left Hive entries pointing at files that were gone.
///
/// Same durable root the downloader already writes to.
Future<Directory> songCacheDirectory() async {
  final directory = Directory(
    '${(await getApplicationSupportDirectory()).path}/cachedSongs',
  );
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }
  return directory;
}

/// The pre-move location, consulted only so what is already cached can be
/// carried across once.
Future<Directory> legacySongCacheDirectory() async =>
    Directory('${(await getTemporaryDirectory()).path}/cachedSongs');

/// Moves anything already cached into the durable directory, returning how many
/// files moved.
///
/// Without this the move would empty the Songs list on first launch — the exact
/// failure it exists to prevent. Idempotent: a second run finds nothing to do.
/// [from] and [to] exist so tests can drive real directories without a
/// path_provider plugin binding.
Future<int> migrateLegacySongCache({Directory? from, Directory? to}) async {
  final legacy = from ?? await legacySongCacheDirectory();
  if (!legacy.existsSync()) return 0;

  final destination = to ?? await songCacheDirectory();
  if (!destination.existsSync()) destination.createSync(recursive: true);
  if (legacy.path == destination.path) return 0;

  var moved = 0;
  for (final entity in legacy.listSync()) {
    if (entity is! File) continue;
    final target = '${destination.path}/${entity.uri.pathSegments.last}';
    // An existing target means this ran before and was interrupted. The
    // destination copy is the one in use, so drop the leftover rather than
    // overwriting a file the player may already hold open.
    if (File(target).existsSync()) {
      _delete(entity);
      continue;
    }
    try {
      entity.renameSync(target);
      moved++;
    } on FileSystemException {
      // Rename fails across volumes; temp and app-support usually share one,
      // but a redirected %TEMP% does not.
      try {
        entity.copySync(target);
        _delete(entity);
        moved++;
      } on FileSystemException {
        // Leave it behind rather than failing startup over one cached song.
      }
    }
  }

  // Only once it is empty: a directory that still holds files we could not move
  // must stay, or those files are lost with it.
  try {
    if (legacy.listSync().isEmpty) legacy.deleteSync();
  } on FileSystemException {
    // Nothing depends on the old directory going away.
  }
  return moved;
}

void _delete(File file) {
  try {
    file.deleteSync();
  } on FileSystemException {
    // Best effort.
  }
}
