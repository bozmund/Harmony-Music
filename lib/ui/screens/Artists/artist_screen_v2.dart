import 'package:flutter/material.dart';
import 'package:harmonymusic/utils/get_localization.dart';

import '/ui/screens/Artists/artist_screen.dart' show AboutArtist;
import '../../navigator.dart';
import '../../widgets/loader.dart';
import '../../widgets/separate_tab_item_widget.dart';
import 'artist_screen_controller.dart';

class ArtistScreenBN extends StatelessWidget {
  const ArtistScreenBN({
    super.key,
    required this.artistScreenController,
    required this.tag,
  });
  final ArtistScreenController artistScreenController;
  final String tag;
  @override
  Widget build(BuildContext context) {
    final separatedContent = artistScreenController.separatedContent;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 85,
        backgroundColor: Theme.of(context).canvasColor,
        leading: Padding(
          padding: const EdgeInsets.only(top: 25.0),
          child: IconButton(
            onPressed: () {
              ScreenNavigationSetup.navigatorKey.currentState?.pop();
            },
            icon: const Icon(Icons.arrow_back_ios_new),
          ),
        ),
        elevation: 0,
        bottom: TabBar(
          splashFactory: NoSplash.splashFactory,
          enableFeedback: true,
          isScrollable: true,
          controller: artistScreenController.tabController!,
          onTap: artistScreenController.onDestinationSelected,
          tabs: [
            "about".tr,
            "songs".tr,
            "videos".tr,
            "albums".tr,
            "singles".tr,
          ].map((e) => Tab(text: e)).toList(),
        ),
        title: AnimatedBuilder(
          animation: artistScreenController,
          builder: (context, _) => artistScreenController.isArtistContentFetched
              ? Padding(
                  padding: const EdgeInsets.only(top: 25.0),
                  child: Text(
                    artistScreenController.artist_.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
      body: AnimatedBuilder(
        animation: artistScreenController,
        builder: (context, _) => TabBarView(
          controller: artistScreenController.tabController,
          children: !artistScreenController.isArtistContentFetched
              ? List.generate(
                  5,
                  (index) => const Center(child: LoadingIndicator()),
                )
              : [
                  AboutArtist(
                    artistScreenController: artistScreenController,
                    padding: const EdgeInsets.only(
                      top: 10,
                      left: 15,
                      right: 5,
                      bottom: 200,
                    ),
                  ),
                  ...["Songs", "Videos", "Albums", "Singles"].map((item) {
                    if (artistScreenController
                                .isSeparatedArtistContentFetched ==
                            false &&
                        artistScreenController.navigationRailCurrentIndex !=
                            0) {
                      return const Center(child: LoadingIndicator());
                    }
                    return Padding(
                      padding: const EdgeInsets.only(left: 15.0, right: 5),
                      child: SeparateTabItemWidget(
                        artistControllerTag: tag,
                        hideTitle: true,
                        isResultWidget: false,
                        items: separatedContent.containsKey(item)
                            ? separatedContent[item]['results']
                            : [],
                        title: item,
                        scrollController: item == "Songs"
                            ? artistScreenController.songScrollController
                            : item == "Videos"
                            ? artistScreenController.videoScrollController
                            : item == "Albums"
                            ? artistScreenController.albumScrollController
                            : item == "Singles"
                            ? artistScreenController.singlesScrollController
                            : null,
                      ),
                    );
                  }),
                ],
        ),
      ),
    );
  }
}
