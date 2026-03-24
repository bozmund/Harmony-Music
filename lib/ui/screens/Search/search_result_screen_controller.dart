import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';

import '../../../utils/helper.dart';
import '../Home/home_screen_controller.dart';
import '/services/music_service.dart';
import '/ui/widgets/sort_widget.dart';

class SearchResultScreenController extends GetxController
    with GetTickerProviderStateMixin {
  final navigationRailCurrentIndex = 0.obs;
  final isResultContentFetced = false.obs;
  final isSeparatedResultContentFetced = false.obs;
  final resultContent = <String, dynamic>{}.obs;
  final separatedResultContent = <String, dynamic>{}.obs;
  final musicServices = Get.find<MusicServices>();
  final queryString = ''.obs;
  final networkError = false.obs;
  final railItems = <String>[].obs;
  final railitemHeight = Get.size.height.obs;
  final additionalParamNext = {};
  bool continuationInProgress = false;
  TabController? tabController;
  bool isTabTransitionReversed = false;
  //ScrollContollers List
  final Map<String, ScrollController> scrollControllers = {};

  @override
  void onInit() {
    super.onInit();
    // Listen for query changes to refresh search
    ever(queryString, (_) => _getInitSearchResult());
  }

  @override
  void onReady() {
    final args = Get.arguments;
    if (args != null) {
      queryString.value = args;
    }
    super.onReady();
  }

  Future<void> onDestinationSelected(int value,
      {bool ignoreTabCommand = false}) async {
    if (railItems.isEmpty || value >= railItems.length) {
      return;
    }

    isTabTransitionReversed = value > navigationRailCurrentIndex.value;

    isSeparatedResultContentFetced.value = false;
    navigationRailCurrentIndex.value = value;
    networkError.value = false;

    if (tabController != null && !ignoreTabCommand) {
      tabController?.animateTo(value);
    }

    final tabName = railItems[value];
    if (tabName != 'Results' &&
        (!separatedResultContent.containsKey(tabName) ||
            separatedResultContent[tabName].isEmpty)) {
      final itemCount = (tabName == 'Songs' || tabName == 'Videos') ? 25 : 10;
      try {
        final x = await musicServices.search(queryString.value,
            filter: tabName.replaceAll(" ", "_").toLowerCase(),
            limit: itemCount,
            filterParams: resultContent['searchEndpoint']?[tabName]);
        separatedResultContent[tabName] = x[tabName];
        additionalParamNext[tabName] = x['params'];
        isSeparatedResultContentFetced.value = true;
        final scrollController = scrollControllers[tabName];
        if (scrollController != null) {
          scrollController.addListener(() {
            double maxScroll = scrollController.position.maxScrollExtent;
            double currentScroll = scrollController.position.pixels;
            if (currentScroll >= maxScroll / 2 &&
                additionalParamNext[tabName]['additionalParams'] !=
                    '&ctoken=null&continuation=null') {
              if (!continuationInProgress) {
                printINFO("Acchhsk");
                continuationInProgress = true;
                getContinuationContents();
              }
            }
          });
        }
      } catch (e) {
        printERROR("Search error for $tabName: $e");
        networkError.value = true;
      }
    }
    isSeparatedResultContentFetced.value = true;
  }

  Future<void> getContinuationContents() async {
    final tabName = railItems[navigationRailCurrentIndex.value];

    final x =
        await musicServices.getSearchContinuation(additionalParamNext[tabName]);
    (separatedResultContent[tabName]).addAll(x[tabName]);
    additionalParamNext[tabName] = x['params'];
    separatedResultContent.refresh();

    continuationInProgress = false;
  }

  void viewAllCallback(String text) {
    onDestinationSelected(railItems.indexOf(text));
  }

  Future<void> _getInitSearchResult() async {
    isResultContentFetced.value = false;
    networkError.value = false;
    final query = queryString.value;
    if (query.isNotEmpty) {
      // Clear previous results
      railItems.clear();
      resultContent.clear();
      separatedResultContent.clear();
      additionalParamNext.clear();
      scrollControllers.forEach((key, value) => value.dispose());
      scrollControllers.clear();

      // Initial categories list for immediate display
      const order = [
        "Songs",
        "Results",
        "Videos",
        "Albums",
        "Artists",
        "Featured playlists",
        "Community playlists"
      ];
      railItems.value = order;
      navigationRailCurrentIndex.value = 0;

      // Initialize scroll controllers and content placeholders
      for (String item in railItems) {
        if (item != 'Results') {
          scrollControllers[item] = ScrollController();
          separatedResultContent[item] = [];
        }
      }

      // Re-initialize tab controller if needed
      if (GetPlatform.isDesktop ||
          Get.find<SettingsScreenController>().isBottomNavBarEnabled.isTrue) {
        tabController?.dispose();
        tabController = TabController(length: railItems.length, vsync: this);
        tabController?.animation?.addListener(() {
          int indexChange = tabController!.offset.round();
          int index = tabController!.index + indexChange;

          if (index != navigationRailCurrentIndex.value &&
              index < railItems.length) {
            onDestinationSelected(index, ignoreTabCommand: true);
          }
        });
      }

      isResultContentFetced.value = true;

      // Load initial tab data (usually Songs)
      onDestinationSelected(0);

      try {
        // Fetch full results in background to populate endpoints and other categories
        final results = await musicServices.search(query);
        resultContent.value = results;

        final availableKeys = resultContent.keys
            .where((element) => ([
                  "Songs",
                  "Videos",
                  "Albums",
                  "Featured playlists",
                  "Community playlists",
                  "Artists"
                ]).contains(element))
            .toList();
        availableKeys.add("Results");

        // Filter railItems to only those returned by the service, but keep requested order
        final filteredOrder =
            order.where((e) => availableKeys.contains(e)).toList();

        if (filteredOrder.join() != railItems.join()) {
          final currentTabName = railItems[navigationRailCurrentIndex.value];
          railItems.value = filteredOrder;

          // Sync tab controller
          if (tabController != null) {
            final newIndex = railItems.indexOf(currentTabName);
            tabController = TabController(
              length: railItems.length,
              vsync: this,
              initialIndex: newIndex >= 0 ? newIndex : 0,
            );
            navigationRailCurrentIndex.value = newIndex >= 0 ? newIndex : 0;

            tabController?.animation?.addListener(() {
              int indexChange = tabController!.offset.round();
              int index = tabController!.index + indexChange;

              if (index != navigationRailCurrentIndex.value &&
                  index < railItems.length) {
                onDestinationSelected(index, ignoreTabCommand: true);
              }
            });
          }
        }

        final len =
            railItems.where((element) => element.contains("playlists")).length;
        final calH = 30 + (railItems.length - len) * 123 + len * 150.0;
        railitemHeight.value =
            calH >= railitemHeight.value ? calH : railitemHeight.value;
      } catch (e) {
        printERROR("Search error for Results: $e");
        networkError.value = true;
      }
    }
  }

  void onSort(SortType sortType, bool isAscending, String title) {
    if (title == "Songs" || title == "Videos") {
      final songList = separatedResultContent[title].toList();
      sortSongsNVideos(songList, sortType, isAscending);
      separatedResultContent[title] = songList;
    } else if (title.contains('playlists')) {
      final playlists = separatedResultContent[title].toList();
      sortPlayLists(playlists, sortType, isAscending);
      separatedResultContent[title] = playlists;
    } else if (title == "Artists") {
      final artistList = separatedResultContent[title].toList();
      sortArtist(artistList, sortType, isAscending);
      separatedResultContent[title] = artistList;
    } else if (title == "Albums") {
      final albumList = separatedResultContent[title].toList();
      sortAlbumNSingles(albumList, sortType, isAscending);
      separatedResultContent[title] = albumList;
    }
  }

  @override
  void onClose() {
    for (String item in railItems) {
      if (scrollControllers.containsKey(item)) {
        (scrollControllers[item])!.dispose();
      }
    }
    Get.find<HomeScreenController>().whenHomeScreenOnTop();
    tabController?.dispose();
    super.onClose();
  }
}
