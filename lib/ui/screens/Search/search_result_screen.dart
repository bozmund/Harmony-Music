import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/utils/get_localization.dart';

import '../../../app/providers/controller_providers.dart';
import '../../../app/providers/service_providers.dart';
import '../../../utils/runtime_platform.dart';
import '/ui/screens/Search/search_result_screen_v2.dart';
import '../../navigator.dart';
import '../../widgets/animated_screen_transition.dart';
import '../../widgets/loader.dart';
import '../../widgets/search_related_widgets.dart';
import '../../widgets/separate_tab_item_widget.dart';
import 'search_result_screen_controller.dart';

class SearchResultScreen extends ConsumerStatefulWidget {
  const SearchResultScreen({super.key});

  @override
  ConsumerState<SearchResultScreen> createState() => _SearchResultScreenState();
}

class _SearchResultScreenState extends ConsumerState<SearchResultScreen>
    with SingleTickerProviderStateMixin {
  SearchResultScreenController? _controller;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final controller = SearchResultScreenController(
      musicService: ref.read(musicServiceContractProvider),
      homeScreenController: ref.read(homeScreenControllerProvider),
      settingsScreenController: ref.read(settingsScreenControllerProvider),
    );
    _controller = controller;
    SearchResultScreenControllerRegistry.register(controller);
    final query = ModalRoute.of(context)?.settings.arguments;
    final queryString = query is String ? query : query?.toString();
    final isDesktopLayout = RuntimePlatform.isDesktop;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        controller.initialize(
          query: queryString,
          screenHeight: MediaQuery.sizeOf(context).height,
          isDesktopLayout: isDesktopLayout,
          vsync: this,
        ),
      );
    });
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      SearchResultScreenControllerRegistry.unregister(controller);
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchResScrController = _controller;
    if (searchResScrController == null) {
      return const Scaffold(body: Center(child: LoadingIndicator()));
    }
    final settingsScreenController = ref.watch(
      settingsScreenControllerProvider,
    );
    return RuntimePlatform.isDesktop ||
            settingsScreenController.isBottomNavBarEnabled.value
        ? SearchResultScreenBN(searchResScrController: searchResScrController)
        : Scaffold(
            body: Row(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 80),
                    child: IntrinsicHeight(
                      child: AnimatedBuilder(
                        animation: searchResScrController,
                        builder: (context, _) => NavigationRail(
                          onDestinationSelected:
                              searchResScrController.onDestinationSelected,
                          minWidth: 60,
                          destinations:
                              (searchResScrController.isResultContentFetched &&
                                  searchResScrController.railItems.isNotEmpty)
                              ? [
                                  railDestination("results".tr),
                                  ...(searchResScrController.railItems.map(
                                    (element) => railDestination(element),
                                  )),
                                ]
                              : [
                                  railDestination("results".tr),
                                  railDestination(""),
                                ],
                          leading: Column(
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.orientationOf(context) ==
                                        Orientation.landscape
                                    ? 20
                                    : 45,
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.arrow_back_ios_new,
                                  color: Theme.of(
                                    context,
                                  ).textTheme.titleMedium!.color,
                                ),
                                onPressed: () {
                                  ScreenNavigationSetup
                                      .navigatorKey
                                      .currentState!
                                      .pop();
                                },
                              ),
                              const SizedBox(height: 10),
                            ],
                          ),
                          labelType: NavigationRailLabelType.all,
                          selectedIndex:
                              searchResScrController.navigationRailCurrentIndex,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: AnimatedBuilder(
                    animation: searchResScrController,
                    builder: (context, _) => AnimatedScreenTransition(
                      enabled: !settingsScreenController
                          .isTransitionAnimationDisabled
                          .value,
                      resverse: searchResScrController.isTabTransitionReversed,
                      child: Center(
                        key: ValueKey<int>(
                          searchResScrController.navigationRailCurrentIndex * 8,
                        ),
                        child: Body(
                          searchResScrController: searchResScrController,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
  }

  NavigationRailDestination railDestination(String label) {
    return NavigationRailDestination(
      icon: const SizedBox.shrink(),
      label: RotatedBox(
        quarterTurns: -1,
        child: Text(label.toLowerCase().removeAllWhitespace.tr),
      ),
    );
  }
}

class Body extends StatelessWidget {
  const Body({super.key, required this.searchResScrController});

  final SearchResultScreenController searchResScrController;

  @override
  Widget build(BuildContext context) {
    if (searchResScrController.navigationRailCurrentIndex == 0) {
      return AnimatedBuilder(
        animation: searchResScrController,
        builder: (context, _) {
          if (searchResScrController.isResultContentFetched &&
              searchResScrController.railItems.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "nomatch".tr,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text("'${searchResScrController.queryString}'"),
                ],
              ),
            );
          } else if (searchResScrController.isResultContentFetched) {
            return ResultWidget(searchResScrController: searchResScrController);
          } else {
            return const Center(child: LoadingIndicator());
          }
        },
      );
    } else {
      if (searchResScrController.isResultContentFetched) {
        final topPadding =
            MediaQuery.orientationOf(context) == Orientation.landscape
            ? 50.0
            : 80.0;
        final name = searchResScrController
            .railItems[searchResScrController.navigationRailCurrentIndex - 1];
        return SeparateTabItemWidget(
          items: const [],
          title: name,
          topPadding: topPadding,
          scrollController: searchResScrController.scrollControllers[name],
          searchResultScreenController: searchResScrController,
        );
      }
    }
    return const SizedBox.shrink();
  }
}
