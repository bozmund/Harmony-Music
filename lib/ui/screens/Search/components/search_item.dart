import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/controller_providers.dart';
import '../../../../utils/runtime_platform.dart';

import '../../../navigator.dart';
import '../../../widgets/awaitable_button.dart';

class SearchItem extends ConsumerWidget {
  final String queryString;
  final bool isHistoryString;
  const SearchItem({
    super.key,
    required this.queryString,
    required this.isHistoryString,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchScreenController = ref.watch(searchScreenControllerProvider);
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 10, right: 20),
      onTap: () async {
        await ScreenNavigationSetup.navigatorKey.currentState!.pushNamed(
          ScreenNavigationSetup.searchResultScreen,
          arguments: queryString,
        );
        await searchScreenController.addToHistoryQueryList(queryString);
        // for Desktop searchbar
        if (RuntimePlatform.isDesktop) {
          searchScreenController.focusNode.unfocus();
        }
      },
      leading: isHistoryString
          ? const Icon(Icons.history)
          : const Icon(Icons.search),
      minLeadingWidth: 20,
      dense: true,
      title: Text(queryString),
      trailing: SizedBox(
        width: 80,
        child: Row(
          children: [
            isHistoryString
                ? AwaitableIconButton(
                    iconSize: 18,
                    splashRadius: 18,
                    visualDensity: const VisualDensity(horizontal: -2),
                    onPressed: () async {
                      await searchScreenController.removeQueryFromHistory(
                        queryString,
                      );
                    },
                    icon: Icon(
                      Icons.clear,
                      color: Theme.of(context).textTheme.titleMedium!.color,
                    ),
                  )
                : const SizedBox(width: 40),
            AwaitableIconButton(
              iconSize: 20,
              splashRadius: 18,
              visualDensity: const VisualDensity(horizontal: -2),
              onPressed: () async {
                await searchScreenController.suggestionInput(queryString);
              },
              icon: Icon(
                Icons.north_west,
                color: Theme.of(context).textTheme.titleMedium!.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
