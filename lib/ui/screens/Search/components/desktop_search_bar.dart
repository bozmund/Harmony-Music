import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/utils/get_localization.dart';

import '../../../../app/providers/controller_providers.dart';
import 'search_item.dart';

import '../../../navigator.dart';

class DesktopSearchBar extends ConsumerWidget {
  const DesktopSearchBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchScreenController = ref.watch(searchScreenControllerProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Shortcuts(
          shortcuts: {
            LogicalKeySet(LogicalKeyboardKey.space):
                const DoNothingAndStopPropagationTextIntent(),
          },
          child: SearchBar(
            controller: searchScreenController.textInputController,
            onTapOutside: (event) {},
            onChanged: searchScreenController.onChanged,
            onSubmitted: (val) async {
              if (val.contains("https://")) {
                await searchScreenController.filterLinks(Uri.parse(val));
                searchScreenController.reset();
                return;
              }
              await ScreenNavigationSetup.navigatorKey.currentState!.pushNamed(
                ScreenNavigationSetup.searchResultScreen,
                arguments: val,
              );
              await searchScreenController.addToHistoryQueryList(val);
              searchScreenController.focusNode.unfocus();
            },
            focusNode: searchScreenController.focusNode,
            backgroundColor: WidgetStatePropertyAll<Color>(
              Theme.of(context).colorScheme.secondary,
            ),
            hintText: "searchDes".tr,
            leading: IconButton(
              onPressed: () {
                if (searchScreenController.focusNode.hasFocus) {
                  searchScreenController.focusNode.unfocus();
                }
              },
              icon: Icon(
                searchScreenController.isSearchBarInFocus
                    ? Icons.arrow_back
                    : Icons.search,
              ),
            ),
            trailing: [
              searchScreenController.isSearchBarInFocus
                  ? IconButton(
                      onPressed: searchScreenController.reset,
                      icon: const Icon(Icons.clear),
                    )
                  : const SizedBox.shrink(),
            ],
            padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
              EdgeInsets.only(left: 15, right: 15),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10.0),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondary,
              borderRadius: BorderRadius.circular(20),
            ),
            constraints: const BoxConstraints(minHeight: 0, maxHeight: 300),
            child: Builder(
              builder: (context) {
                final isHistoryString =
                    searchScreenController.textInputController.text.isEmpty &&
                    searchScreenController.suggestionList.isEmpty;
                final listToShow = isHistoryString
                    ? searchScreenController.historyQueryList
                    : searchScreenController.suggestionList;
                return searchScreenController.urlPasted
                    ? InkWell(
                        onTap: () async {
                          await searchScreenController.filterLinks(
                            Uri.parse(
                              searchScreenController.textInputController.text,
                            ),
                          );
                          searchScreenController.reset();
                        },
                        child: SizedBox(
                          width: double.maxFinite,
                          height: 50,
                          child: Center(
                            child: Text(
                              "urlSearchDes".tr,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ),
                      )
                    : searchScreenController.isSearchBarInFocus &&
                          listToShow.isNotEmpty
                    ? ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(5.0),
                        children: listToShow.map((item) {
                          return SearchItem(
                            queryString: item,
                            isHistoryString: isHistoryString,
                          );
                        }).toList(),
                      )
                    : const SizedBox.shrink();
              },
            ),
          ),
        ),
      ],
    );
  }
}
