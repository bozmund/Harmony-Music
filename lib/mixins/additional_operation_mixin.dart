import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/material.dart';
import 'package:harmonymusic/base_class/playlist_album_screen_con_base.dart';

import '../app/navigation/app_navigator.dart';
import '../ui/widgets/add_to_playlist.dart';
import '../ui/widgets/sort_widget.dart';
import '../utils/helper.dart';
import '../utils/observable_state.dart';

mixin AdditionalOperationMixin on PlaylistAlbumScreenControllerBase {
  // This mixin is used to handle additional operations like sorting, searching, and performing actions on a list of songs.
  // It is used in various screens like Album, Playlist, and SongsCache.
  SortWidgetController? sortWidgetController;
  final additionalOperationMode = ObservableValue(OperationMode.none);
  final isSearchingOn = ObservableValue(false);
  List<MediaItem> tempListContainer = <MediaItem>[];

  void onSort(SortType sortType, bool isAscending) {
    final songlist_ = songList.toList();
    sortSongsNVideos(songlist_, sortType, isAscending);
    songList.value = songlist_;
    notifyListeners();
  }

  @override
  void onSearchStart(String? tag) {
    isSearchingOn.value = true;
    tempListContainer = songList.toList();
    notifyListeners();
  }

  @override
  void onSearch(String value, String? tag) {
    final songlist = tempListContainer
        .where(
          (element) =>
              element.title.toLowerCase().contains(value.toLowerCase()),
        )
        .toList();
    songList.value = songlist;
    notifyListeners();
  }

  @override
  void onSearchClose(String? tag) {
    isSearchingOn.value = false;
    songList.value = tempListContainer.toList();
    tempListContainer.clear();
    notifyListeners();
  }

  //Additional operations
  final additionalOperationTempList = ObservableList<MediaItem>();
  final additionalOperationTempMap = ObservableMap<int, bool>();

  @override
  void startAdditionalOperation(
    SortWidgetController sortWidgetController_,
    OperationMode mode,
  ) {
    sortWidgetController = sortWidgetController_;
    additionalOperationTempList.value = songList.toList();
    if (mode == OperationMode.addToPlaylist || mode == OperationMode.delete) {
      for (int i = 0; i < additionalOperationTempList.length; i++) {
        additionalOperationTempMap[i] = false;
      }
    }
    additionalOperationMode.value = mode;
    notifyListeners();
  }

  void checkIfAllSelected() {
    sortWidgetController!.toggleSelectAll(
      !additionalOperationTempMap.containsValue(false),
    );
    notifyListeners();
  }

  @override
  void selectAll(bool selectAll) {
    for (int i = 0; i < additionalOperationTempList.length; i++) {
      additionalOperationTempMap[i] = selectAll;
    }
    notifyListeners();
  }

  @override
  Future<void> performAdditionalOperation() async {
    final currMode = additionalOperationMode.value;
    if (currMode == OperationMode.arrange) {
      songList.value = additionalOperationTempList.toList();
      await updateSongsIntoDb().then((value) {
        sortWidgetController?.setActiveMode(OperationMode.none);
        cancelAdditionalOperation();
      });
    } else if (currMode == OperationMode.delete) {
      await deleteMultipleSongs(selectedSongs()).then((value) {
        sortWidgetController?.setActiveMode(OperationMode.none);
        cancelAdditionalOperation();
      });
    } else if (currMode == OperationMode.addToPlaylist) {
      final context = AppNavigator.context;
      if (context == null) return;
      await showDialog(
        context: context,
        builder: (context) => AddToPlaylist(selectedSongs()),
      ).whenComplete(() async {
        sortWidgetController?.setActiveMode(OperationMode.none);
        cancelAdditionalOperation();
      });
    }
  }

  @override
  List<MediaItem> selectedSongs() {
    return additionalOperationTempMap.entries
        .map((item) {
          if (item.value) {
            return additionalOperationTempList[item.key];
          }
        })
        .whereType<MediaItem>()
        .toList();
  }

  @override
  void cancelAdditionalOperation() {
    sortWidgetController!.toggleSelectAll(false);
    sortWidgetController = null;
    additionalOperationMode.value = OperationMode.none;
    additionalOperationTempList.clear();
    additionalOperationTempMap.clear();
    notifyListeners();
  }
}
