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
  final railItems = <String>[].obs;
  final railitemHeight = Get.size.height.obs;
  final additionalParamNext = {};
  bool continuationInProgress = false;
  TabController? tabController;
  bool isTabTransitionReversed = false;
  //ScrollContollers List
  final Map<String, ScrollController> scrollControllers = {};
  final Set<String> _scrollListenersAttached = {};
  static const List<String> _searchRailItems = [
    "Songs",
    "Videos",
    "Albums",
    "Featured playlists",
    "Community playlists",
    "Artists"
  ];

  @override
  void onReady() {
    _getInitSearchResult();
    Get.find<HomeScreenController>().whenHomeScreenOnTop();
    super.onReady();
  }

  Future<void> onDestinationSelected(int value,
      {bool ignoreTabCommand = false}) async {
    if (value < 0 || value > railItems.length) {
      return;
    }

    isTabTransitionReversed = value > navigationRailCurrentIndex.value;

    isSeparatedResultContentFetced.value = false;
    navigationRailCurrentIndex.value = value;

    if (tabController != null && !ignoreTabCommand) {
      tabController?.animateTo(value);
    }

    if (value > 0 &&
        (!separatedResultContent.containsKey(railItems[value - 1]) ||
            separatedResultContent[railItems[value - 1]].isEmpty)) {
      final tabName = railItems[value - 1];
      final itemCount = (tabName == 'Songs' || tabName == 'Videos') ? 25 : 10;
      final filterParams = _filterParamsFor(tabName);
      final x = await musicServices.search(queryString.value,
          filter: tabName.replaceAll(" ", "_").toLowerCase(),
          limit: itemCount,
          filterParams: filterParams);
      separatedResultContent[tabName] = x[tabName] ?? [];
      additionalParamNext[tabName] = x['params'];
      isSeparatedResultContentFetced.value = true;
      final scrollController = scrollControllers[tabName];
      if (scrollController != null &&
          !_scrollListenersAttached.contains(tabName) &&
          _hasValidContinuationParams(additionalParamNext[tabName])) {
        _scrollListenersAttached.add(tabName);
        scrollController.addListener(() {
          double maxScroll = scrollController.position.maxScrollExtent;
          double currentScroll = scrollController.position.pixels;
          if (currentScroll >= maxScroll / 2 &&
              _hasValidContinuationParams(additionalParamNext[tabName])) {
            if (!continuationInProgress) {
              continuationInProgress = true;
              getContinuationContents();
            }
          }
        });
      }
    }
    isSeparatedResultContentFetced.value = true;
  }

  Future<void> getContinuationContents() async {
    if (navigationRailCurrentIndex.value <= 0 ||
        navigationRailCurrentIndex.value > railItems.length) {
      continuationInProgress = false;
      return;
    }
    final tabName = railItems[navigationRailCurrentIndex.value - 1];
    final params = additionalParamNext[tabName];
    if (!_hasValidContinuationParams(params)) {
      continuationInProgress = false;
      return;
    }

    try {
      final x = await musicServices.getSearchContinuation(params);
      (separatedResultContent[tabName] ?? []).addAll(x[tabName] ?? []);
      additionalParamNext[tabName] = x['params'];
      separatedResultContent.refresh();
    } finally {
      continuationInProgress = false;
    }
  }

  void viewAllCallback(String text) {
    onDestinationSelected(railItems.indexOf(text) + 1);
  }

  Future<void> _getInitSearchResult() async {
    isResultContentFetced.value = false;
    final args = Get.arguments;
    if (args != null) {
      queryString.value = args;
      resultContent.value = await musicServices.search(args);
      final allKeys = _searchRailItems.where((element) =>
          _hasInitialContent(element) || _canLoadFilteredTab(element));
      railItems.value = List<String>.from(allKeys);
      final len =
          railItems.where((element) => element.contains("playlists")).length;
      final calH = 30 + (railItems.length + 1 - len) * 123 + len * 150.0;
      railitemHeight.value =
          calH >= railitemHeight.value ? calH : railitemHeight.value;

      //ScrollControlers for list Continuation callback implementarion
      for (String item in railItems) {
        scrollControllers[item] = ScrollController();
      }

      //Case if bottom nav used
      if (GetPlatform.isDesktop ||
          Get.find<SettingsScreenController>().isBottomNavBarEnabled.isTrue) {
        // assiging init val
        for (var element in railItems) {
          separatedResultContent[element] = [];
        }

        //tab controller for v2
        tabController =
            TabController(length: railItems.length + 1, vsync: this);

        tabController?.animation?.addListener(() {
          int indexChange = tabController!.offset.round();
          int index = tabController!.index + indexChange;

          if (index != navigationRailCurrentIndex.value) {
            onDestinationSelected(index, ignoreTabCommand: true);
          }
        });
      }
      isResultContentFetced.value = true;
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

  bool _hasInitialContent(String tabName) {
    final value = resultContent[tabName];
    return value is List && value.isNotEmpty;
  }

  bool _canLoadFilteredTab(String tabName) {
    if (tabName == "Community playlists") return false;
    final params = _filterParamsFor(tabName);
    return params != null && params.isNotEmpty;
  }

  String? _filterParamsFor(String tabName) {
    final endpoints = resultContent['searchEndpoint'];
    if (endpoints is! Map) return null;
    final params = endpoints[tabName];
    return params is String ? params : null;
  }

  bool _hasValidContinuationParams(dynamic params) {
    if (params is! Map) return false;
    final additionalParams = params['additionalParams'];
    return additionalParams != null &&
        additionalParams != '&ctoken=null&continuation=null';
  }

  @override
  void onClose() {
    for (String item in railItems) {
      scrollControllers[item]?.dispose();
    }
    Get.find<HomeScreenController>().whenHomeScreenOnTop();
    tabController?.dispose();
    super.onClose();
  }
}
