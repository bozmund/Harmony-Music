import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/screens/Search/search_result_screen_v2.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '../../navigator.dart';
import '../../widgets/animated_screen_transition.dart';
import '../../widgets/loader.dart';
import '../../widgets/search_related_widgets.dart';
import '../../widgets/separate_tab_item_widget.dart';
import 'search_result_screen_controller.dart';

class SearchResultScreen extends StatelessWidget {
  const SearchResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final searchResScrController = Get.put(SearchResultScreenController());
    return GetPlatform.isDesktop ||
            Get.find<SettingsScreenController>().isBottomNavBarEnabled.isTrue
        ? const SearchResultScreenBN()
        : Scaffold(
            body: Row(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 80),
                    child: IntrinsicHeight(
                      child: Obx(
                        () => NavigationRail(
                          onDestinationSelected:
                              searchResScrController.onDestinationSelected,
                          minWidth: 60,
                          destinations: (searchResScrController
                                      .isResultContentFetced.value &&
                                  searchResScrController.railItems.isNotEmpty)
                              ? searchResScrController.railItems
                                  .map((element) => railDestination(element))
                                  .toList()
                              : [
                                  railDestination("results".tr),
                                  railDestination("")
                                ],
                          leading: Column(
                            children: [
                              SizedBox(
                                height: context.isLandscape ? 20 : 45,
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.arrow_back_ios_new,
                                  color: Theme.of(context)
                                      .textTheme
                                      .titleMedium!
                                      .color,
                                ),
                                onPressed: () {
                                  Get.nestedKey(ScreenNavigationSetup.id)!
                                      .currentState!
                                      .pop();
                                },
                              ),
                              const SizedBox(
                                height: 10,
                              ),
                            ],
                          ),
                          labelType: NavigationRailLabelType.all,
                          selectedIndex: searchResScrController
                              .navigationRailCurrentIndex.value,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GetX<SearchResultScreenController>(
                    builder: (controller) => AnimatedScreenTransition(
                      enabled: Get.find<SettingsScreenController>()
                          .isTransitionAnimationDisabled
                          .isFalse,
                      resverse: controller.isTabTransitionReversed,
                      child: Center(
                        key: ValueKey<int>(
                            controller.navigationRailCurrentIndex.toInt() * 8),
                        child: Body(
                            searchResScrController: searchResScrController),
                      ),
                    ),
                  ),
                )
              ],
            ),
          );
  }

  NavigationRailDestination railDestination(String label) {
    return NavigationRailDestination(
      icon: const SizedBox.shrink(),
      label: RotatedBox(
          quarterTurns: -1,
          child: Text(label.toLowerCase().removeAllWhitespace.tr)),
    );
  }
}

class Body extends StatelessWidget {
  const Body({
    super.key,
    required this.searchResScrController,
  });

  final SearchResultScreenController searchResScrController;

  @override
  Widget build(BuildContext context) {
    final tabName = searchResScrController
        .railItems[searchResScrController.navigationRailCurrentIndex.value];
    if (tabName == "Results") {
      return Obx(() {
        if (searchResScrController.networkError.isTrue) {
          return Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(
                "networkError1".tr,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(
                height: 10,
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                decoration: BoxDecoration(
                    color: Theme.of(context).textTheme.titleLarge!.color,
                    borderRadius: BorderRadius.circular(10)),
                child: InkWell(
                  onTap: () {
                    searchResScrController.queryString.refresh();
                  },
                  child: Text(
                    "retry".tr,
                    style: TextStyle(color: Theme.of(context).canvasColor),
                  ),
                ),
              ),
            ]),
          );
        } else if (searchResScrController.isResultContentFetced.isTrue &&
            searchResScrController.railItems.length <= 1) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "nomatch".tr,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text("'${searchResScrController.queryString.value}'"),
              ],
            ),
          );
        } else if (searchResScrController.isResultContentFetced.isTrue) {
          return const ResultWidget();
        } else {
          return const Center(
            child: LoadingIndicator(),
          );
        }
      });
    } else {
      return Obx(() {
        if (searchResScrController.networkError.isTrue) {
          return Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(
                "networkError1".tr,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(
                height: 10,
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                decoration: BoxDecoration(
                    color: Theme.of(context).textTheme.titleLarge!.color,
                    borderRadius: BorderRadius.circular(10)),
                child: InkWell(
                  onTap: () {
                    searchResScrController.onDestinationSelected(
                        searchResScrController.navigationRailCurrentIndex.value);
                  },
                  child: Text(
                    "retry".tr,
                    style: TextStyle(color: Theme.of(context).canvasColor),
                  ),
                ),
              ),
            ]),
          );
        } else if (searchResScrController.isResultContentFetced.isTrue) {
          final topPadding = context.isLandscape ? 50.0 : 80.0;
          final name = tabName;
          return SeparateTabItemWidget(
            items: const [],
            title: name,
            topPadding: topPadding,
            scrollController: searchResScrController.scrollControllers[name],
          );
        }
        return const Center(
          child: LoadingIndicator(),
        );
      });
    }
  }
}
