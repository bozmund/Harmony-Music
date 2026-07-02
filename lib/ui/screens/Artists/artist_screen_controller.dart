import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../../app/navigation/app_navigator.dart';
import '../../../domain/repositories/library_repository.dart';
import '../../widgets/add_to_playlist.dart';
import '/ui/widgets/sort_widget.dart';
import '../../../models/artist.dart';
import '../../../utils/helper.dart';
import '../Library/library_controller.dart';
import '/services/app_contracts.dart';
import '/ui/screens/Home/home_screen_controller.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';

class ArtistScreenControllerRegistry {
  static final _controllers = <String, ArtistScreenController>{};

  static void register(String tag, ArtistScreenController controller) {
    _controllers[tag] = controller;
  }

  static void unregister(String tag, ArtistScreenController controller) {
    if (_controllers[tag] == controller) {
      _controllers.remove(tag);
    }
  }

  static ArtistScreenController? maybeOf(String? tag) =>
      tag == null ? null : _controllers[tag];
}

class ArtistScreenController extends ChangeNotifier {
  ArtistScreenController({
    required MusicServiceContract musicService,
    required LibraryRepository libraryRepository,
    required SettingsScreenController settingsScreenController,
    required HomeScreenController homeScreenController,
  }) : musicServices = musicService,
       _libraryRepository = libraryRepository,
       _settingsScreenController = settingsScreenController,
       _homeScreenController = homeScreenController;

  bool isArtistContentFetched = false;
  int navigationRailCurrentIndex = 0;
  final MusicServiceContract musicServices;
  final LibraryRepository _libraryRepository;
  final SettingsScreenController _settingsScreenController;
  final HomeScreenController _homeScreenController;
  final railItems = <String>[];
  Map<String, dynamic> artistData = <String, dynamic>{};
  final separatedContent = <String, dynamic>{};
  bool isSeparatedArtistContentFetched = false;
  bool isAddedToLibrary = false;
  final songScrollController = ScrollController();
  final videoScrollController = ScrollController();
  final albumScrollController = ScrollController();
  final singlesScrollController = ScrollController();
  SortWidgetController? sortWidgetController;
  OperationMode additionalOperationMode = OperationMode.none;
  bool continuationInProgress = false;
  int _loadGeneration = 0;
  bool _closed = false;
  late Artist artist_;
  Map<String, List> tempListContainer = {};
  TabController? tabController;
  bool isTabTransitionReversed = false;

  void initialize({
    required bool isIdOnly,
    required dynamic artist,
    required bool isDesktopLayout,
    required TickerProvider vsync,
  }) {
    unawaited(_init(isIdOnly, artist));
    if (isDesktopLayout ||
        _settingsScreenController.isBottomNavBarEnabled.value) {
      tabController = TabController(vsync: vsync, length: 5);
      tabController?.animation?.addListener(() async {
        int indexChange = tabController!.offset.round();
        int index = tabController!.index + indexChange;

        if (index != navigationRailCurrentIndex) {
          await onDestinationSelected(index);
          navigationRailCurrentIndex = index;
          notifyListeners();
        }
      });
    }
  }

  void ready() {
    _homeScreenController.whenHomeScreenOnTop();
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
      !_closed && generation == _loadGeneration;

  Future<void> _checkIfAddedToLibrary(String id, int generation) async {
    final artists = await _libraryRepository.getArtists();
    if (!_isLoadActive(generation)) return;
    isAddedToLibrary = artists.any((artist) => artist.browseId == id);
    notifyListeners();
  }

  Future<void> _fetchArtistContent(String id, int generation) async {
    final artistContent = await musicServices.getArtist(id);
    if (!_isLoadActive(generation)) return;
    artistData = artistContent;
    artistData["Singles"] = artistData["Singles & EPs"];
    artistData["Songs"] = artistData["Top songs"];
    isArtistContentFetched = true;
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
    notifyListeners();
  }

  Future<bool> addNRemoveFromLibrary({bool add = true}) async {
    try {
      add
          ? await _libraryRepository.saveArtist(artist_)
          : await _libraryRepository.deleteArtist(artist_.browseId);
      isAddedToLibrary = add;
      notifyListeners();
      //Update frontend
      await LibraryArtistsControllerRegistry.current?.refreshLib();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> onDestinationSelected(int val) async {
    isTabTransitionReversed = val > navigationRailCurrentIndex;
    navigationRailCurrentIndex = val;
    notifyListeners();
    final tabName = ["About", "Songs", "Videos", "Albums", "Singles"][val];

    //cancel additional operations in case of tab change
    if (sortWidgetController != null) {
      sortWidgetController?.setActiveMode(OperationMode.none);
      cancelAdditionalOperation();
    }

    //skip for about page
    if (val == 0 || separatedContent.containsKey(tabName)) return;
    if (artistData[tabName] == null) {
      isSeparatedArtistContentFetched = true;
      notifyListeners();
      return;
    }
    isSeparatedArtistContentFetched = false;
    notifyListeners();

    //check if params available for continuation
    //tab browse endpoint & top result stored in [artistData], tabContent & additionalParams for continuation stored in Separated Content
    if (artistData[tabName].containsKey("params")) {
      separatedContent[tabName] = await musicServices.getArtistRelatedContent(
        artistData[tabName],
        tabName,
      );
    } else {
      separatedContent[tabName] = {"results": artistData[tabName]['content']};
      isSeparatedArtistContentFetched = true;
      notifyListeners();
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
    isSeparatedArtistContentFetched = true;
    notifyListeners();
  }

  Future<void> getContinuationContents(browseEndpoint, tabName) async {
    final x = await musicServices.getArtistRelatedContent(
      browseEndpoint,
      tabName,
      additionalParams: separatedContent[tabName]['additionalParams'],
    );
    separatedContent[tabName]['results'].addAll(x['results']);
    separatedContent[tabName]['additionalParams'] = x['additionalParams'];
    notifyListeners();

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
    notifyListeners();
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
    notifyListeners();
  }

  void onSearchClose(String? tag) {
    final title = tag?.split("_")[0];
    separatedContent[title]['results'] = (tempListContainer[title]!).toList();
    (tempListContainer[title]!).clear();
    notifyListeners();
  }

  //Additional operations
  List<MediaItem> additionalOperationTempList = <MediaItem>[];
  final additionalOperationTempMap = <int, bool>{};

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
    ][navigationRailCurrentIndex];
    additionalOperationTempList = List<MediaItem>.from(
      separatedContent[tabName]['results'],
    ).toList();
    if (mode == OperationMode.addToPlaylist || mode == OperationMode.delete) {
      for (int i = 0; i < additionalOperationTempList.length; i++) {
        additionalOperationTempMap[i] = false;
      }
    }
    additionalOperationMode = mode;
    notifyListeners();
  }

  void checkIfAllSelected() {
    sortWidgetController!.toggleSelectAll(
      !additionalOperationTempMap.containsValue(false),
    );
    notifyListeners();
  }

  void selectAll(bool selected) {
    for (int i = 0; i < additionalOperationTempList.length; i++) {
      additionalOperationTempMap[i] = selected;
    }
    notifyListeners();
  }

  Future<void> performAdditionalOperation() async {
    final currMode = additionalOperationMode;
    if (currMode == OperationMode.addToPlaylist) {
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
    sortWidgetController?.toggleSelectAll(false);
    sortWidgetController = null;
    additionalOperationMode = OperationMode.none;
    additionalOperationTempList = <MediaItem>[];
    additionalOperationTempMap.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _loadGeneration++;
    tempListContainer.clear();
    songScrollController.dispose();
    videoScrollController.dispose();
    albumScrollController.dispose();
    singlesScrollController.dispose();
    tabController?.dispose();
    _homeScreenController.whenHomeScreenOnTop();
    super.dispose();
  }
}
