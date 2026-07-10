import 'package:buttons_tabbar/buttons_tabbar.dart';
import 'package:flutter/material.dart';
import 'package:harmonymusic/l10n/l10n.dart';
import 'package:harmonymusic/ui/widgets/loader.dart';
import 'package:harmonymusic/ui/widgets/search_related_widgets.dart';

import '../../navigator.dart';
import '../../widgets/separate_tab_item_widget.dart';
import 'search_result_screen_controller.dart';

class SearchResultScreenBN extends StatelessWidget {
  const SearchResultScreenBN({super.key, required this.searchResScrController});

  final SearchResultScreenController searchResScrController;

  @override
  Widget build(BuildContext context) {
    final topPadding =
        MediaQuery.orientationOf(context) == Orientation.landscape
        ? 50.0
        : 80.0;
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 55,
                  child: Center(
                    child: IconButton(
                      onPressed: () {
                        ScreenNavigationSetup.navigatorKey.currentState!.pop();
                      },
                      icon: const Icon(Icons.arrow_back_ios_new),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          context.l10n.searchRes,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AnimatedBuilder(
                          animation: searchResScrController,
                          builder: (context, _) => Text(
                            "${context.l10n.for1} \"${searchResScrController.queryString}\"",
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: searchResScrController,
                builder: (context, _) {
                  if (searchResScrController.isResultContentFetched &&
                      searchResScrController.railItems.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            context.l10n.nomatch,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text("'${searchResScrController.queryString}'"),
                        ],
                      ),
                    );
                  } else if (searchResScrController.isResultContentFetched) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(left: 15.0, top: 10),
                          child: ButtonsTabBar(
                            onTap: searchResScrController.onDestinationSelected,

                            controller: searchResScrController.tabController,
                            contentPadding: const EdgeInsets.only(
                              left: 15,
                              right: 15,
                            ),
                            backgroundColor: Theme.of(
                              context,
                            ).textTheme.titleMedium?.color!,
                            unselectedBackgroundColor: Theme.of(
                              context,
                            ).colorScheme.secondary,
                            borderWidth: 0,
                            buttonMargin: const EdgeInsets.only(
                              right: 10,
                              left: 4,
                              top: 4,
                              bottom: 4,
                            ),
                            borderColor: Colors.black,
                            labelStyle: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                            unselectedLabelStyle: TextStyle(
                              color: Theme.of(
                                context,
                              ).textTheme.titleMedium?.color!,
                              fontWeight: FontWeight.bold,
                            ),
                            // Add your tabs here
                            tabs: [
                              Tab(text: context.l10n.results),
                              ...searchResScrController.railItems.map(
                                (item) =>
                                    Tab(text: context.l10n.sectionTitle(item)),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 15.0),
                            child: TabBarView(
                              controller: searchResScrController.tabController,
                              children: [
                                ResultWidget(
                                  isv2Used: true,
                                  searchResScrController:
                                      searchResScrController,
                                ),
                                ...searchResScrController.railItems.map((
                                  tabName,
                                ) {
                                  if (tabName == "Songs" ||
                                      tabName == "Videos") {
                                    return SeparateTabItemWidget(
                                      isResultWidget: true,
                                      hideTitle: true,
                                      items: const [],
                                      title: tabName,
                                      isCompleteList: true,
                                      scrollController: searchResScrController
                                          .scrollControllers[tabName],
                                      searchResultScreenController:
                                          searchResScrController,
                                    );
                                  } else {
                                    return SeparateTabItemWidget(
                                      title: tabName,
                                      hideTitle: true,
                                      items: const [],
                                      scrollController: searchResScrController
                                          .scrollControllers[tabName],
                                      searchResultScreenController:
                                          searchResScrController,
                                    );
                                  }
                                }),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  } else {
                    return const Center(child: LoadingIndicator());
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
