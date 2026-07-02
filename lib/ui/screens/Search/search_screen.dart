import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/utils/get_localization.dart';

import '../../../app/providers/controller_providers.dart';
import 'components/search_item.dart';
import '../../widgets/modified_text_field.dart';
import '/ui/navigator.dart';

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchScreenController = ref.watch(searchScreenControllerProvider);
    final settingsScreenController = ref.watch(
      settingsScreenControllerProvider,
    );
    final topPadding =
        MediaQuery.orientationOf(context) == Orientation.landscape
        ? 50.0
        : 80.0;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: AnimatedBuilder(
        animation: Listenable.merge([
          searchScreenController,
          settingsScreenController,
        ]),
        builder: (context, _) => Row(
          children: [
            !settingsScreenController.isBottomNavBarEnabled.value
                ? Container(
                    width: 60,
                    color: Theme.of(
                      context,
                    ).navigationRailTheme.backgroundColor,
                    child: Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: topPadding),
                          child: IconButton(
                            icon: Icon(
                              Icons.arrow_back_ios_new,
                              color: Theme.of(
                                context,
                              ).textTheme.titleMedium!.color,
                            ),
                            onPressed: () {
                              ScreenNavigationSetup.navigatorKey.currentState!
                                  .pop();
                            },
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: 15),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: topPadding, left: 5),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "search".tr,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ModifiedTextField(
                      textCapitalization: TextCapitalization.sentences,
                      controller: searchScreenController.textInputController,
                      textInputAction: TextInputAction.search,
                      onChanged: searchScreenController.onChanged,
                      onSubmitted: (val) async {
                        if (val.contains("https://")) {
                          await searchScreenController.filterLinks(
                            Uri.parse(val),
                          );
                          searchScreenController.reset();
                          return;
                        }
                        await ScreenNavigationSetup.navigatorKey.currentState!
                            .pushNamed(
                              ScreenNavigationSetup.searchResultScreen,
                              arguments: val,
                            );
                        await searchScreenController.addToHistoryQueryList(val);
                      },
                      autofocus:
                          !settingsScreenController.isBottomNavBarEnabled.value,
                      cursorColor: Theme.of(context).textTheme.bodySmall!.color,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.only(left: 5),
                        focusColor: Colors.white,
                        hintText: "searchDes".tr,
                        suffix: IconButton(
                          onPressed: searchScreenController.reset,
                          icon: const Icon(Icons.close),
                          splashRadius: 16,
                          iconSize: 19,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final isEmpty =
                              searchScreenController.suggestionList.isEmpty ||
                              searchScreenController.textInputController.text ==
                                  "";
                          final list = isEmpty
                              ? searchScreenController.historyQueryList.toList()
                              : searchScreenController.suggestionList.toList();
                          return ListView(
                            padding: const EdgeInsets.only(top: 5, bottom: 400),
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            children: searchScreenController.urlPasted
                                ? [
                                    InkWell(
                                      onTap: () async {
                                        await searchScreenController
                                            .filterLinks(
                                              Uri.parse(
                                                searchScreenController
                                                    .textInputController
                                                    .text,
                                              ),
                                            );
                                        searchScreenController.reset();
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 10.0,
                                        ),
                                        child: SizedBox(
                                          width: double.maxFinite,
                                          height: 60,
                                          child: Center(
                                            child: Text(
                                              "urlSearchDes".tr,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleMedium,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ]
                                : list
                                      .map(
                                        (item) => SearchItem(
                                          queryString: item,
                                          isHistoryString: isEmpty,
                                        ),
                                      )
                                      .toList(),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
