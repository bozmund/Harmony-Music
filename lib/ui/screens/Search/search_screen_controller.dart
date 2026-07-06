import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/repositories/search_history_repository.dart';
import '/services/app_contracts.dart';
import '/ui/player/player_controller.dart';
import '/utils/app_link_controller.dart' show ProcessLink;

class SearchScreenController extends ChangeNotifier with ProcessLink {
  SearchScreenController({
    required SearchHistoryRepository searchHistoryRepository,
    required MusicServiceContract musicService,
    required PlayerController playerController,
  }) : _searchHistoryRepository = searchHistoryRepository,
       _musicServices = musicService,
       _playerController = playerController {
    unawaited(_init());
  }

  final SearchHistoryRepository _searchHistoryRepository;
  final MusicServiceContract _musicServices;
  final PlayerController _playerController;
  @override
  MusicServiceContract get musicService => _musicServices;
  @override
  PlayerController get playerController => _playerController;
  final textInputController = TextEditingController();
  List<String> suggestionList = [];
  List<String> historyQueryList = [];
  bool urlPasted = false;

  // Desktop search bar related
  final focusNode = FocusNode();
  bool isSearchBarInFocus = false;

  Future<void> _init() async {
    focusNode.addListener(() {
      isSearchBarInFocus = focusNode.hasFocus;
      notifyListeners();
    });
    historyQueryList = (await _searchHistoryRepository.getQueries()).reversed
        .cast<String>()
        .toList();
    notifyListeners();
  }

  Future<void> onChanged(String text) async {
    if (text.contains("https://")) {
      urlPasted = true;
      notifyListeners();
      return;
    }
    urlPasted = false;
    suggestionList = List<String>.from(
      await _musicServices.getSearchSuggestion(text),
    );
    notifyListeners();
  }

  Future<void> suggestionInput(String txt) async {
    textInputController.text = txt;
    textInputController.selection = TextSelection.collapsed(
      offset: textInputController.text.length,
    );
    await onChanged(txt);
  }

  Future<void> addToHistoryQueryList(String txt) async {
    if (historyQueryList.length > 9) {
      final queryForRemoval = historyQueryList.last;
      historyQueryList = historyQueryList
          .where((element) => element != queryForRemoval)
          .toList();
    }
    if (!historyQueryList.contains(txt)) {
      await _searchHistoryRepository.addQuery(txt, maxEntries: 10);
      historyQueryList = [txt, ...historyQueryList];
    }

    //reset current query and suggestionList
    reset();
  }

  void reset() {
    urlPasted = false;
    textInputController.text = "";
    suggestionList = [];
    notifyListeners();
  }

  Future<void> removeQueryFromHistory(String txt) async {
    await _searchHistoryRepository.deleteQuery(txt);
    historyQueryList = historyQueryList.where((query) => query != txt).toList();
    notifyListeners();
  }

  @override
  void dispose() {
    focusNode.dispose();
    textInputController.dispose();
    super.dispose();
  }
}
