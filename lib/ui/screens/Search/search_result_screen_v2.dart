import 'package:buttons_tabbar/buttons_tabbar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/widgets/loader.dart';
import 'package:harmonymusic/ui/widgets/search_related_widgets.dart';

import '../../navigator.dart';
import '../../widgets/separate_tab_item_widget.dart';
import 'search_result_screen_controller.dart';

class SearchResultScreenBN extends StatelessWidget {
  const SearchResultScreenBN({super.key});

  @override
  Widget build(BuildContext context) {
    final SearchResultScreenController searchResScrController =
        Get.find<SearchResultScreenController>();
    final topPadding = context.isLandscape ? 50.0 : 80.0;
    return Scaffold(
      body: Padding(
          padding: EdgeInsets.only(
            top: topPadding,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 55,
                    child: Center(
                      child: IconButton(
                        onPressed: () {
                          Get.nestedKey(ScreenNavigationSetup.id)!
                              .currentState!
                              .pop();
                        },
                        icon: const Icon(Icons.arrow_back_ios_new),
                      ),
                    ),
                  ),
                  Expanded(
                      child: Column(children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "searchRes".tr,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Obx(
                        () => Text(
                          "${"for1".tr} \"${searchResScrController.queryString.value}\"",
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                  ]))
                ],
              ),
              Expanded(
                child: Obx(
                  () {
                    if (searchResScrController.isResultContentFetced.isTrue &&
                        searchResScrController.railItems.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "nomatch".tr,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                                "'${searchResScrController.queryString.value}'"),
                          ],
                        ),
                      );
                    } else if (searchResScrController.networkError.isTrue) {
                      return Center(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "networkError1".tr,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(
                                height: 10,
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 15, vertical: 10),
                                decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .textTheme
                                        .titleLarge!
                                        .color,
                                    borderRadius: BorderRadius.circular(10)),
                                child: InkWell(
                                  onTap: () {
                                    final currentTabName =
                                        searchResScrController.railItems[
                                            searchResScrController
                                                .navigationRailCurrentIndex
                                                .value];
                                    if (currentTabName == 'Results') {
                                      searchResScrController
                                          .queryString.refresh();
                                    } else {
                                      searchResScrController
                                          .onDestinationSelected(
                                              searchResScrController
                                                  .navigationRailCurrentIndex
                                                  .value);
                                    }
                                  },
                                  child: Text(
                                    "retry".tr,
                                    style: TextStyle(
                                        color: Theme.of(context).canvasColor),
                                  ),
                                ),
                              ),
                            ]),
                      );
                    } else if (searchResScrController
                        .isResultContentFetced.isTrue) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.only(left: 15.0, top: 10),
                            child: ButtonsTabBar(
                              onTap:
                                  searchResScrController.onDestinationSelected,

                              controller: searchResScrController.tabController,
                              contentPadding:
                                  const EdgeInsets.only(left: 15, right: 15),
                              backgroundColor: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.color!,
                              unselectedBackgroundColor:
                                  Theme.of(context).colorScheme.secondary,
                              borderWidth: 0,
                              buttonMargin: const EdgeInsets.only(
                                  right: 10, left: 4, top: 4, bottom: 4),
                              borderColor: Colors.black,
                              labelStyle: TextStyle(
                                color: Theme.of(context).primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                              unselectedLabelStyle: TextStyle(
                                color: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.color!,
                                fontWeight: FontWeight.bold,
                              ),
                              // Add your tabs here
                              tabs: searchResScrController.railItems
                                  .map((item) => Tab(
                                        text: item
                                            .toLowerCase()
                                            .removeAllWhitespace
                                            .tr,
                                      ))
                                  .toList(),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 15.0),
                              child: TabBarView(
                                controller:
                                    searchResScrController.tabController,
                                children: searchResScrController.railItems
                                    .map((tabName) {
                                  if (tabName == "Results") {
                                    return const ResultWidget(
                                      isv2Used: true,
                                    );
                                  } else if (tabName == "Songs" ||
                                      tabName == "Videos") {
                                    return SeparateTabItemWidget(
                                      isResultWidget: true,
                                      hideTitle: true,
                                      items: const [],
                                      title: tabName,
                                      isCompleteList: true,
                                      scrollController: searchResScrController
                                          .scrollControllers[tabName],
                                    );
                                  } else {
                                    return SeparateTabItemWidget(
                                      title: tabName,
                                      hideTitle: true,
                                      items: const [],
                                      scrollController: searchResScrController
                                          .scrollControllers[tabName],
                                    );
                                  }
                                }).toList(),
                              ),
                            ),
                          ),
                        ],
                      );
                    } else {
                      return const Center(
                        child: LoadingIndicator(),
                      );
                    }
                  },
                ),
              )
            ],
          )),
    );
  }
}
