import 'dart:async';

import 'package:flutter/material.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';

import '../../../utils/helper.dart';
import '../Home/home_screen_controller.dart';
import '/services/app_contracts.dart';
import '/ui/widgets/sort_widget.dart';

class SearchResultScreenController extends ChangeNotifier {
  SearchResultScreenController({
    required MusicServiceContract musicService,
    required HomeScreenController homeScreenController,
    required SettingsScreenController settingsScreenController,
  }) : musicServices = musicService,
       _homeScreenController = homeScreenController,
       _settingsScreenController = settingsScreenController;

  int navigationRailCurrentIndex = 0;
  bool isResultContentFetched = false;
  bool isSeparatedResultContentFetched = false;
  Map<String, dynamic> resultContent = <String, dynamic>{};
  final Map<String, dynamic> separatedResultContent = <String, dynamic>{};
  final MusicServiceContract musicServices;
  final HomeScreenController _homeScreenController;
  final SettingsScreenController _settingsScreenController;
  String queryString = '';
  List<String> railItems = <String>[];
  double railItemHeight = 0;
  final additionalParamNext = {};
  bool continuationInProgress = false;
  TabController? tabController;
  bool isTabTransitionReversed = false;
  //ScrollControllers List
  final Map<String, ScrollController> scrollControllers = {};
  final Set<String> _scrollListenersAttached = {};
  static const List<String> _searchRailItems = [
    "Songs",
    "Videos",
    "Albums",
    "Featured playlists",
    "Community playlists",
    "Artists",
  ];

  Future<void> initialize({
    required String? query,
    required double screenHeight,
    required bool isDesktopLayout,
    required TickerProvider vsync,
  }) async {
    railItemHeight = screenHeight;
    await _initializeSearchResult(
      query: query,
      isDesktopLayout: isDesktopLayout,
      vsync: vsync,
    );
    _homeScreenController.whenHomeScreenOnTop();
  }

  void onDestinationSelected(int value, {bool ignoreTabCommand = false}) {
    unawaited(_selectDestination(value, ignoreTabCommand: ignoreTabCommand));
  }

  Future<void> _selectDestination(
    int value, {
    bool ignoreTabCommand = false,
  }) async {
    if (value < 0 || value > railItems.length) {
      return;
    }

    isTabTransitionReversed = value > navigationRailCurrentIndex;

    isSeparatedResultContentFetched = false;
    navigationRailCurrentIndex = value;
    notifyListeners();

    if (tabController != null && !ignoreTabCommand) {
      tabController?.animateTo(value);
    }

    if (value > 0 &&
        (!separatedResultContent.containsKey(railItems[value - 1]) ||
            separatedResultContent[railItems[value - 1]].isEmpty)) {
      final tabName = railItems[value - 1];
      final itemCount = (tabName == 'Songs' || tabName == 'Videos') ? 25 : 10;
      final filterParams = _filterParamsFor(tabName);
      final x = await musicServices.search(
        queryString,
        filter: tabName.replaceAll(" ", "_").toLowerCase(),
        limit: itemCount,
        filterParams: filterParams,
      );
      separatedResultContent[tabName] = x[tabName] ?? [];
      additionalParamNext[tabName] = x['params'];
      final scrollController = scrollControllers[tabName];
      if (scrollController != null &&
          !_scrollListenersAttached.contains(tabName) &&
          _hasValidContinuationParams(additionalParamNext[tabName])) {
        _scrollListenersAttached.add(tabName);
        scrollController.addListener(() async {
          double maxScroll = scrollController.position.maxScrollExtent;
          double currentScroll = scrollController.position.pixels;
          if (currentScroll >= maxScroll / 2 &&
              _hasValidContinuationParams(additionalParamNext[tabName])) {
            if (!continuationInProgress) {
              continuationInProgress = true;
              await getContinuationContents();
            }
          }
        });
      }
    }
    isSeparatedResultContentFetched = true;
    notifyListeners();
  }

  Future<void> getContinuationContents() async {
    if (navigationRailCurrentIndex <= 0 ||
        navigationRailCurrentIndex > railItems.length) {
      continuationInProgress = false;
      return;
    }
    final tabName = railItems[navigationRailCurrentIndex - 1];
    final params = additionalParamNext[tabName];
    if (!_hasValidContinuationParams(params)) {
      continuationInProgress = false;
      return;
    }

    try {
      final x = await musicServices.getSearchContinuation(params);
      (separatedResultContent[tabName] ?? []).addAll(x[tabName] ?? []);
      additionalParamNext[tabName] = x['params'];
      notifyListeners();
    } finally {
      continuationInProgress = false;
    }
  }

  Future<void> viewAllCallback(String text) async {
    await _selectDestination(railItems.indexOf(text) + 1);
  }

  Future<void> _initializeSearchResult({
    required String? query,
    required bool isDesktopLayout,
    required TickerProvider vsync,
  }) async {
    isResultContentFetched = false;
    notifyListeners();
    if (query != null) {
      queryString = query;
      resultContent = await musicServices.search(query);
      final allKeys = _searchRailItems.where(
        (element) =>
            _hasInitialContent(element) || _canLoadFilteredTab(element),
      );
      railItems = List<String>.from(allKeys);
      final len = railItems
          .where((element) => element.contains("playlists"))
          .length;
      final calH = 30 + (railItems.length + 1 - len) * 123 + len * 150.0;
      railItemHeight = calH >= railItemHeight ? calH : railItemHeight;

      //ScrollControllers for list Continuation callback implementation
      for (String item in railItems) {
        scrollControllers[item] = ScrollController();
      }

      //Case if bottom nav used
      if (isDesktopLayout ||
          _settingsScreenController.isBottomNavBarEnabled.value) {
        // assigning init val
        for (var element in railItems) {
          separatedResultContent[element] = [];
        }

        //tab controller for v2
        tabController = TabController(
          length: railItems.length + 1,
          vsync: vsync,
        );

        tabController?.animation?.addListener(() async {
          int indexChange = tabController!.offset.round();
          int index = tabController!.index + indexChange;

          if (index != navigationRailCurrentIndex) {
            await _selectDestination(index, ignoreTabCommand: true);
          }
        });
      }
      isResultContentFetched = true;
      notifyListeners();
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
    notifyListeners();
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
  void dispose() {
    for (String item in railItems) {
      scrollControllers[item]?.dispose();
    }
    _homeScreenController.whenHomeScreenOnTop();
    tabController?.dispose();
    super.dispose();
  }
}

class SearchResultScreenControllerRegistry {
  SearchResultScreenControllerRegistry._();

  static SearchResultScreenController? _controller;

  static SearchResultScreenController? get current => _controller;

  static void register(SearchResultScreenController controller) {
    _controller = controller;
  }

  static void unregister(SearchResultScreenController controller) {
    if (identical(_controller, controller)) {
      _controller = null;
    }
  }
}
