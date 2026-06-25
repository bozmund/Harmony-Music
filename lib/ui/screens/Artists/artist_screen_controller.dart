import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../widgets/add_to_playlist.dart';
import '/ui/widgets/sort_widget.dart';
import '../../../models/artist.dart';
import '../../../utils/helper.dart';
import '../Library/library_controller.dart';
import '/services/app_contracts.dart';
import '/ui/screens/Home/home_screen_controller.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';

class ArtistScreenController extends GetxController
    with GetSingleTickerProviderStateMixin {
  final isArtistContentFetched = false.obs;
  final navigationRailCurrentIndex = 0.obs;
  final musicServices = Get.find<MusicServiceContract>();
  final railItems = <String>[].obs;
  final artistData = <String, dynamic>{}.obs;
  final separatedContent = <String, dynamic>{}.obs;
  final isSeparatedArtistContentFetched = false.obs;
  final isAddedToLibrary = false.obs;
  final songScrollController = ScrollController();
  final videoScrollController = ScrollController();
  final albumScrollController = ScrollController();
  final singlesScrollController = ScrollController();
  SortWidgetController? sortWidgetController;
  final additionalOperationMode = OperationMode.none.obs;
  bool continuationInProgress = false;
  int _loadGeneration = 0;
  late Artist artist_;
  Map<String, List> tempListContainer = {};
  TabController? tabController;
  bool isTabTransitionReversed = false;

  @override
  void onInit() {
    final args = Get.arguments;
    unawaited(_init(args[0], args[1]));
    if (GetPlatform.isDesktop ||
        Get.find<SettingsScreenController>().isBottomNavBarEnabled.isTrue) {
      tabController = TabController(vsync: this, length: 5);
      tabController?.animation?.addListener(() async {
        int indexChange = tabController!.offset.round();
        int index = tabController!.index + indexChange;

        if (index != navigationRailCurrentIndex.value) {
          await onDestinationSelected(index);
          navigationRailCurrentIndex.value = index;
        }
      });
    }
    super.onInit();
  }

  @override
  void onReady() {
    Get.find<HomeScreenController>().whenHomeScreenOnTop();
    super.onReady();
  }

  Future<void> _init(bool isIdOnly, dynamic artist) async {
    final generation = ++_loadGeneration;
    if (!isIdOnly) artist_ = artist as Artist;
    await _fetchArtistContent(
      isIdOnly ? artist as String : artist.browseId,
      generation,
    );
    if (!_isLoadActive(generation)) return;
    await _checkIfAddedToLibrary(
      isIdOnly ? artist as String : artist.browseId,
      generation,
    );
  }

  bool _isLoadActive(int generation) =>
      !isClosed && generation == _loadGeneration;

  Future<void> _checkIfAddedToLibrary(String id, int generation) async {
    final box = await Hive.openBox("LibraryArtists");
    if (!_isLoadActive(generation)) {
      await box.close();
      return;
    }
    isAddedToLibrary.value = box.containsKey(id);
    await box.close();
  }

  Future<void> _fetchArtistContent(String id, int generation) async {
    final artistContent = await musicServices.getArtist(id);
    if (!_isLoadActive(generation)) return;
    artistData.value = artistContent;
    artistData["Singles"] = artistData["Singles & EPs"];
    artistData["Songs"] = artistData["Top songs"];
    isArtistContentFetched.value = true;
    //inspect(artistData.value);
    artist_ = Artist(
      browseId: id,
      name: artistData['name'],
      thumbnailUrl: artistData['thumbnails'] != null
          ? artistData['thumbnails'][0]['url']
          : "",
      subscribers: "${artistData['subscribers']} subscribers",
      radioId: artistData["radioId"],
    );
  }

  Future<bool> addNRemoveFromLibrary({bool add = true}) async {
    try {
      final box = await Hive.openBox("LibraryArtists");
      add
          ? await box.put(artist_.browseId, artist_.toJson())
          : await box.delete(artist_.browseId);
      isAddedToLibrary.value = add;
      //Update frontend
      await Get.find<LibraryArtistsController>().refreshLib();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> onDestinationSelected(int val) async {
    isTabTransitionReversed = val > navigationRailCurrentIndex.value;
    navigationRailCurrentIndex.value = val;
    final tabName = ["About", "Songs", "Videos", "Albums", "Singles"][val];

    //cancel additional operations in case of tab change
    if (sortWidgetController != null) {
      sortWidgetController?.setActiveMode(OperationMode.none);
      cancelAdditionalOperation();
    }

    //skip for about page
    if (val == 0 || separatedContent.containsKey(tabName)) return;
    if (artistData[tabName] == null) {
      isSeparatedArtistContentFetched.value = true;
      return;
    }
    isSeparatedArtistContentFetched.value = false;

    //check if params available for continuation
    //tab browse endpoint & top result stored in [artistData], tabContent & additionalParams for continuation stored in Separated Content
    if (artistData[tabName].containsKey("params")) {
      separatedContent[tabName] = await musicServices.getArtistRelatedContent(
        artistData[tabName],
        tabName,
      );
    } else {
      separatedContent[tabName] = {"results": artistData[tabName]['content']};
      isSeparatedArtistContentFetched.value = true;
      return;
    }

    // observed - continuation available only for song & vid
    if (val != 0) {
      final scrollController = val == 1
          ? songScrollController
          : val == 2
          ? videoScrollController
          : val == 3
          ? albumScrollController
          : singlesScrollController;

      scrollController.addListener(() async {
        double maxScroll = scrollController.position.maxScrollExtent;
        double currentScroll = scrollController.position.pixels;
        if (currentScroll >= maxScroll / 2 &&
            separatedContent[tabName]['additionalParams'] !=
                '&ctoken=null&continuation=null') {
          if (!continuationInProgress) {
            continuationInProgress = true;
            await getContinuationContents(artistData[tabName], tabName);
          }
        }
      });
    }
    isSeparatedArtistContentFetched.value = true;
  }

  Future<void> getContinuationContents(browseEndpoint, tabName) async {
    final x = await musicServices.getArtistRelatedContent(
      browseEndpoint,
      tabName,
      additionalParams: separatedContent[tabName]['additionalParams'],
    );
    separatedContent[tabName]['results'].addAll(x['results']);
    separatedContent[tabName]['additionalParams'] = x['additionalParams'];
    separatedContent.refresh();

    continuationInProgress = false;
  }

  void onSort(SortType sortType, bool isAscending, String title) {
    if (separatedContent[title] == null) {
      return;
    }
    if (title == "Songs" || title == "Videos") {
      final songlist = separatedContent[title]['results'].toList();
      sortSongsNVideos(songlist, sortType, isAscending);
      separatedContent[title]['results'] = songlist;
    } else if (title == "Albums" || title == "Singles") {
      final albumList = separatedContent[title]['results'].toList();
      sortAlbumNSingles(albumList, sortType, isAscending);
      separatedContent[title]['results'] = albumList;
    }
    separatedContent.refresh();
  }

  void onSearchStart(String? tag) {
    final title = tag?.split("_")[0];
    tempListContainer[title!] = separatedContent[title]['results'].toList();
  }

  void onSearch(String value, String? tag) {
    final title = tag?.split("_")[0];
    final list = tempListContainer[title]!
        .where(
          (element) =>
              element.title.toLowerCase().contains(value.toLowerCase()),
        )
        .toList();
    separatedContent[title]['results'] = list;
    separatedContent.refresh();
  }

  void onSearchClose(String? tag) {
    final title = tag?.split("_")[0];
    separatedContent[title]['results'] = (tempListContainer[title]!).toList();
    separatedContent.refresh();
    (tempListContainer[title]!).clear();
  }

  //Additional operations
  final additionalOperationTempList = <MediaItem>[].obs;
  final additionalOperationTempMap = <int, bool>{}.obs;

  void startAdditionalOperation(
    SortWidgetController sortWidgetController_,
    OperationMode mode,
  ) {
    sortWidgetController = sortWidgetController_;
    final tabName = [
      "About",
      "Songs",
      "Videos",
      "Albums",
      "Singles",
    ][navigationRailCurrentIndex.value];
    additionalOperationTempList.value = separatedContent[tabName]['results']
        .toList();
    if (mode == OperationMode.addToPlaylist || mode == OperationMode.delete) {
      for (int i = 0; i < additionalOperationTempList.length; i++) {
        additionalOperationTempMap[i] = false;
      }
    }
    additionalOperationMode.value = mode;
  }

  void checkIfAllSelected() {
    sortWidgetController!.isAllSelected.value = !additionalOperationTempMap
        .containsValue(false);
  }

  void selectAll(bool selected) {
    for (int i = 0; i < additionalOperationTempList.length; i++) {
      additionalOperationTempMap[i] = selected;
    }
  }

  Future<void> performAdditionalOperation() async {
    final currMode = additionalOperationMode.value;
    if (currMode == OperationMode.addToPlaylist) {
      await showDialog(
        context: Get.context!,
        builder: (context) => AddToPlaylist(selectedSongs()),
      ).whenComplete(() async {
        await Get.delete<AddToPlaylistController>();
        sortWidgetController?.setActiveMode(OperationMode.none);
        cancelAdditionalOperation();
      });
    }
  }

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

  void cancelAdditionalOperation() {
    sortWidgetController!.isAllSelected.value = false;
    sortWidgetController = null;
    additionalOperationMode.value = OperationMode.none;
    additionalOperationTempList.clear();
    additionalOperationTempMap.clear();
  }

  @override
  void onClose() {
    _loadGeneration++;
    tempListContainer.clear();
    songScrollController.dispose();
    videoScrollController.dispose();
    albumScrollController.dispose();
    singlesScrollController.dispose();
    tabController?.dispose();
    Get.find<HomeScreenController>().whenHomeScreenOnTop();
    super.onClose();
  }
}
