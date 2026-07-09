import 'package:flutter/material.dart';
import 'package:harmonymusic/utils/get_localization.dart';
import 'package:harmonymusic/ui/widgets/modification_list.dart';

import '../screens/Artists/artist_screen_controller.dart';
import '../screens/Search/search_result_screen_controller.dart';
import 'awaitable_button.dart';
import 'list_widget.dart';
import 'loader.dart';
import 'sort_widget.dart';

class SeparateTabItemWidget extends StatelessWidget {
  const SeparateTabItemWidget({
    super.key,
    required this.items,
    required this.title,
    this.isCompleteList = true,
    this.isResultWidget = true,
    this.hideTitle = false,
    this.topPadding = 0,
    this.scrollController,
    this.artistControllerTag,
    this.searchResultScreenController,
  });

  /// tag for accessing Artist controller inst, [artistControllerTag] only valid for Artist screen
  final String? artistControllerTag;
  final List<dynamic> items;
  final String title;
  final bool isCompleteList;
  final double topPadding;
  final bool isResultWidget;
  final bool hideTitle;
  final ScrollController? scrollController;
  final SearchResultScreenController? searchResultScreenController;

  @override
  Widget build(BuildContext context) {
    final artistController = ArtistScreenControllerRegistry.maybeOf(
      artistControllerTag,
    );
    final searchResController =
        searchResultScreenController ??
        SearchResultScreenControllerRegistry.current;

    return Padding(
      padding: EdgeInsets.only(top: topPadding, left: 5),
      child: Column(
        children: [
          if (!hideTitle)
            _TitleRow(
              title: title,
              isCompleteList: isCompleteList,
              searchResController: searchResController,
            ),
          if (isCompleteList)
            _SortRow(
              title: title,
              artistControllerTag: artistControllerTag,
              isResultWidget: isResultWidget,
              artistController: artistController,
              searchResController: searchResController,
            ),
          if (isCompleteList)
            isResultWidget
                ? _SearchResultList(
                  title: title,
                  isCompleteList: isCompleteList,
                  scrollController: scrollController,
                  searchResController: searchResController,
                )
                : _ArtistList(
                  title: title,
                  items: items,
                  isCompleteList: isCompleteList,
                  scrollController: scrollController,
                  artistController: artistController,
                )
          else
            ListWidget(
              items,
              title,
              isCompleteList,
              scrollController: scrollController,
            ),
        ],
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.title,
    required this.isCompleteList,
    required this.searchResController,
  });

  final String title;
  final bool isCompleteList;
  final SearchResultScreenController? searchResController;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title.toLowerCase().removeAllWhitespace.tr,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (!isCompleteList)
            AwaitableButton.text(
              onPressed: () async {
                await searchResController?.viewAllCallback(title);
              },
              label: Text(
                "viewAll".tr,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _SortRow extends StatelessWidget {
  const _SortRow({
    required this.title,
    required this.artistControllerTag,
    required this.isResultWidget,
    required this.artistController,
    required this.searchResController,
  });

  final String title;
  final String? artistControllerTag;
  final bool isResultWidget;
  final ArtistScreenController? artistController;
  final SearchResultScreenController? searchResController;

  @override
  Widget build(BuildContext context) {
    final animation =
        isResultWidget
            ? searchResController ?? const AlwaysStoppedAnimation(0)
            : artistController ?? const AlwaysStoppedAnimation(0);
    return AnimatedBuilder(
      animation: animation,
      builder:
          (context, _) => SortWidget(
            tag: "${title}_$artistControllerTag",
            screenController: artistController,
            isAdditionalOperationRequired:
                artistController != null &&
                (title == "Songs" || title == "Videos"),
            isSearchFeatureRequired: artistController != null,
            titleLeftPadding: 9,
            itemCountTitle:
                "${isResultWidget ? (searchResController?.separatedResultContent[title] ?? []).length : (artistController?.separatedContent[title] != null ? artistController?.separatedContent[title]['results'] : []).length} ${"items".tr}",
            requiredSortTypes: buildSortTypeSet(
              title == 'Albums' || title == "Singles",
              title == "Songs" || title == "Videos",
            ),
            onSort: (type, ascending) {
              if (isResultWidget) {
                searchResController!.onSort(type, ascending, title);
              } else {
                artistController?.onSort(type, ascending, title);
              }
            },
            onSearch: artistController?.onSearch,
            onSearchClose: artistController?.onSearchClose,
            onSearchStart: artistController?.onSearchStart,
            startAdditionalOperation:
                artistController?.startAdditionalOperation,
            selectAll: artistController?.selectAll,
            performAdditionalOperation:
                artistController?.performAdditionalOperation,
            cancelAdditionalOperation:
                artistController?.cancelAdditionalOperation,
          ),
    );
  }
}

class _SearchResultList extends StatelessWidget {
  const _SearchResultList({
    required this.title,
    required this.isCompleteList,
    required this.scrollController,
    required this.searchResController,
  });

  final String title;
  final bool isCompleteList;
  final ScrollController? scrollController;
  final SearchResultScreenController? searchResController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: searchResController ?? const AlwaysStoppedAnimation(0),
      builder: (context, _) {
        if (searchResController?.isSeparatedResultContentFetched ?? false) {
          return ListWidget(
            searchResController?.separatedResultContent[title],
            title,
            isCompleteList,
            scrollController: scrollController,
          );
        }
        return const Expanded(child: Center(child: LoadingIndicator()));
      },
    );
  }
}

class _ArtistList extends StatelessWidget {
  const _ArtistList({
    required this.title,
    required this.items,
    required this.isCompleteList,
    required this.scrollController,
    required this.artistController,
  });

  final String title;
  final List<dynamic> items;
  final bool isCompleteList;
  final ScrollController? scrollController;
  final ArtistScreenController? artistController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: artistController ?? const AlwaysStoppedAnimation(0),
      builder: (context, _) {
        if (!(artistController?.isArtistContentFetched ?? false)) {
          return const Expanded(child: Center(child: LoadingIndicator()));
        }
        if (artistController!.additionalOperationMode == OperationMode.none) {
          return ListWidget(
            items,
            title,
            isCompleteList,
            isArtistSongs: true,
            artist: artistController!.artist_,
            scrollController: scrollController,
          );
        }
        return ModificationList(
          mode: artistController!.additionalOperationMode,
          screenController: artistController,
        );
      },
    );
  }
}
