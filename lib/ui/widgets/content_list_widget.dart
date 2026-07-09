import 'package:flutter/material.dart';
import 'package:harmonymusic/utils/get_localization.dart';

import '../../utils/runtime_platform.dart';
import '../screens/Search/search_result_screen_controller.dart';
import 'awaitable_button.dart';
import '/ui/widgets/content_list_widget_item.dart';

class ContentListWidget extends StatelessWidget {
  ///ContentListWidget is used to render a section of Content like a list of Albums or Playlists in HomeScreen
  const ContentListWidget({
    super.key,
    this.content,
    this.isHomeContent = true,
    this.scrollController,
    this.searchResultScreenController,
  });

  ///content will be of class Type AlbumContent or PlaylistContent
  final dynamic content;
  final bool isHomeContent;
  final ScrollController? scrollController;
  final SearchResultScreenController? searchResultScreenController;

  @override
  Widget build(BuildContext context) {
    final isAlbumContent = content.runtimeType.toString() == "AlbumContent";
    // ignore: avoid_unnecessary_containers
    return Container(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  !isHomeContent && content.title.length > 12
                      ? "${content.title.substring(0, 12)}..."
                      : content.title,
                  //maxLines: 2,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                !isHomeContent
                    ? AwaitableButton.text(
                      onPressed: () async {
                        final searchResultScreenController =
                            this.searchResultScreenController ??
                            SearchResultScreenControllerRegistry.current;
                        await searchResultScreenController?.viewAllCallback(
                          content.title,
                        );
                      },
                      label: Text(
                        "viewAll".tr,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    )
                    : const SizedBox.shrink(),
              ],
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 200,
            //color: Colors.blueAccent,
            child: Scrollbar(
              thickness: RuntimePlatform.isDesktop ? null : 0,
              controller: scrollController,
              child: ListView.separated(
                controller: scrollController,
                addAutomaticKeepAlives: false, //Testing going
                addRepaintBoundaries: false, //on this
                physics: const BouncingScrollPhysics(),
                separatorBuilder: (context, index) => const SizedBox(width: 15),
                scrollDirection: Axis.horizontal,
                itemCount:
                    isAlbumContent
                        ? content.albumList.length
                        : content.playlistList.length,
                itemBuilder: (_, index) {
                  if (isAlbumContent) {
                    return ContentListItem(content: content.albumList[index]);
                  }
                  return ContentListItem(content: content.playlistList[index]);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
