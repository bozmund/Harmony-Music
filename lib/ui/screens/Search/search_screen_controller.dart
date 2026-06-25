import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/utils/app_link_controller.dart' show ProcessLink;
import '/services/app_contracts.dart';

class SearchScreenController extends GetxController with ProcessLink {
  final textInputController = TextEditingController();
  final musicServices = Get.find<MusicServiceContract>();
  final suggestionList = [].obs;
  final historyQueryList = [].obs;
  late Box<dynamic> queryBox;
  final urlPasted = false.obs;

  // Desktop search bar related
  final focusNode = FocusNode();
  final isSearchBarInFocus = false.obs;

  @override
  onInit() {
    _init();
    super.onInit();
  }

  _init() async {
    if (GetPlatform.isDesktop) {
      focusNode.addListener(() {
        isSearchBarInFocus.value = focusNode.hasFocus;
      });
    }
    queryBox = await Hive.openBox("searchQuery");
    historyQueryList.value = queryBox.values.toList().reversed.toList();
  }

  Future<void> onChanged(String text) async {
    if (text.contains("https://")) {
      urlPasted.value = true;
      return;
    }
    urlPasted.value = false;
    suggestionList.value = await musicServices.getSearchSuggestion(text);
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
      final queryForRemoval = queryBox.getAt(0);
      await queryBox.deleteAt(0);
      historyQueryList.removeWhere((element) => element == queryForRemoval);
    }
    if (!historyQueryList.contains(txt)) {
      await queryBox.add(txt);
      historyQueryList.insert(0, txt);
    }

    //reset current query and suggestionList
    reset();
  }

  void reset() {
    urlPasted.value = false;
    textInputController.text = "";
    suggestionList.clear();
  }

  Future<void> removeQueryFromHistory(String txt) async {
    final index = queryBox.values.toList().indexOf(txt);
    await queryBox.deleteAt(index);
    historyQueryList.remove(txt);
  }

  @override
  Future<void> dispose() async {
    focusNode.dispose();
    textInputController.dispose();
    await queryBox.close();
    super.dispose();
  }
}
