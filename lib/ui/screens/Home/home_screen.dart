import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/l10n/l10n.dart';

import '../../../app/providers/controller_providers.dart';
import '../../../utils/runtime_platform.dart';
import '../Search/components/desktop_search_bar.dart';
import '/ui/widgets/animated_screen_transition.dart';
import '../Library/library_combined.dart';
import '../../widgets/side_nav_bar.dart';
import '../Library/library.dart';
import '../Search/search_screen.dart';
import '/ui/player/player_controller.dart';
import '/ui/widgets/create_playlist_dialog.dart';
import '../../navigator.dart';
import '../../widgets/content_list_widget.dart';
import '../../widgets/issue_report_dialog.dart';
import '../../widgets/quickpicks_widget.dart';
import '../../widgets/shimmer_widgets/home_shimmer.dart';
import 'home_screen_controller.dart';
import '../Settings/settings_screen.dart';
import '../listen_together/listen_together_sheet.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerController playerController = ref.watch(
      playerControllerProvider,
    );
    final homeScreenController = ref.watch(homeScreenControllerProvider);
    final settingsScreenController = ref.watch(
      settingsScreenControllerProvider,
    );
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    final homeShellAnimation = Listenable.merge([
      homeScreenController,
      settingsScreenController,
      playerController,
    ]);

    return AnimatedBuilder(
      animation: homeShellAnimation,
      builder: (context, _) => Scaffold(
        floatingActionButton:
            ((homeScreenController.tabIndex == 0 &&
                        !RuntimePlatform.isDesktop) ||
                    homeScreenController.tabIndex == 2) &&
                !settingsScreenController.isBottomNavBarEnabled.value
            ? Padding(
                padding: EdgeInsets.only(
                  bottom:
                      playerController.playerPanelMinHeight.value >
                          bottomPadding
                      ? playerController.playerPanelMinHeight.value -
                            bottomPadding
                      : playerController.playerPanelMinHeight.value,
                ),
                child: SizedBox(
                  height: 60,
                  width: 60,
                  child: FittedBox(
                    child: FloatingActionButton(
                      focusElevation: 0,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                      ),
                      elevation: 0,
                      onPressed: () async {
                        if (homeScreenController.tabIndex == 2) {
                          await showDialog(
                            context: context,
                            builder: (context) =>
                                const CreateNRenamePlaylistPopup(),
                          );
                        } else {
                          await ScreenNavigationSetup.navigatorKey.currentState
                              ?.pushNamed(ScreenNavigationSetup.searchScreen);
                        }
                        // file:///data/user/0/com.example.harmonymusic/cache/libCachedImageData/
                        //file:///data/user/0/com.example.harmonymusic/cache/just_audio_cache/
                      },
                      child: Icon(
                        homeScreenController.tabIndex == 2
                            ? Icons.add
                            : Icons.search,
                      ),
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink(),
        body: Row(
          children: <Widget>[
            // create a navigation rail
            !settingsScreenController.isBottomNavBarEnabled.value
                ? const SideNavBar()
                : const SizedBox(width: 0),
            //const VerticalDivider(thickness: 1, width: 2),
            Expanded(
              child: AnimatedScreenTransition(
                enabled: !settingsScreenController
                    .isTransitionAnimationDisabled
                    .value,
                resverse: homeScreenController.reverseAnimationTransition,
                horizontalTransition:
                    settingsScreenController.isBottomNavBarEnabled.value,
                child: Center(
                  key: ValueKey<int>(homeScreenController.tabIndex),
                  child: const Body(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Body extends ConsumerWidget {
  const Body({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeScreenController = ref.watch(homeScreenControllerProvider);
    final settingsScreenController = ref.watch(
      settingsScreenControllerProvider,
    );
    final playerController = ref.read(playerControllerProvider);
    final topPadding = RuntimePlatform.isDesktop ? 85.0 : 36.0;
    final leftPadding = settingsScreenController.isBottomNavBarEnabled.value
        ? 20.0
        : 5.0;
    return AnimatedBuilder(
      animation: Listenable.merge([
        homeScreenController,
        settingsScreenController,
      ]),
      builder: (context, _) {
        // Rendered as the first item of the scrolling home list (not a
        // pinned overlay), so it scrolls away with the content.
        final reportIssueButton = Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                if (RuntimePlatform.isAndroid || RuntimePlatform.isDesktop)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.color,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    icon: const Icon(Icons.groups_2_outlined, size: 20),
                    label: Text(context.l10n.listenTogether),
                    onPressed: () => showListenTogetherSheet(context),
                  ),
                Tooltip(
                  message: "Report an issue",
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.color,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    icon: const Icon(Icons.bug_report_outlined, size: 20),
                    label: const Text("Report issue"),
                    onPressed: () => _openIssueReportDialog(
                      context,
                      extraDiagnosticsBuilder:
                          settingsScreenController
                              .developerSettingsEnabled
                              .value
                          ? () async => {
                              'playback': await playerController
                                  .detailedPlaybackDebugSnapshot(),
                            }
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        return switch (homeScreenController.tabIndex) {
          0 => Padding(
            padding: EdgeInsets.only(left: leftPadding),
            child: Stack(
              children: [
                GestureDetector(
                  onTap: () {
                    if (RuntimePlatform.isDesktop) {
                      final searchScreenController = ref.read(
                        searchScreenControllerProvider,
                      );
                      if (searchScreenController.focusNode.hasFocus) {
                        searchScreenController.focusNode.unfocus();
                      }
                    }
                  },
                  child: homeScreenController.networkError
                      ? _HomeNetworkError(
                          onRetry: homeScreenController.loadContentFromNetwork,
                        )
                      : _HomeContentList(
                          topPadding: topPadding,
                          homeScreenController: homeScreenController,
                          getWidgetList: getWidgetList,
                          reportIssueButton: reportIssueButton,
                        ),
                ),
                if (RuntimePlatform.isDesktop) const _DesktopSearchBarHeader(),
              ],
            ),
          ),
          1 =>
            settingsScreenController.isBottomNavBarEnabled.value
                ? const SearchScreen()
                : const SongsLibraryWidget(),
          2 =>
            settingsScreenController.isBottomNavBarEnabled.value
                ? const CombinedLibrary()
                : const PlaylistNAlbumLibraryWidget(isAlbumContent: false),
          3 =>
            settingsScreenController.isBottomNavBarEnabled.value
                ? const SettingsScreen(isBottomNavActive: true)
                : const PlaylistNAlbumLibraryWidget(),
          4 => const LibraryArtistWidget(),
          5 => const SettingsScreen(),
          final tab => Center(child: Text("$tab")),
        };
      },
    );
  }

  List<Widget> getWidgetList(
    dynamic list,
    HomeScreenController homeScreenController,
  ) {
    return list
        .map((content) {
          final scrollController = ScrollController();
          homeScreenController.contentScrollControllers.add(scrollController);
          return ContentListWidget(
            content: content,
            scrollController: scrollController,
          );
        })
        .whereType<Widget>()
        .toList();
  }

  Future<void> _openIssueReportDialog(
    BuildContext context, {
    Future<Map<String, dynamic>?> Function()? extraDiagnosticsBuilder,
  }) async {
    await showDialog(
      context: context,
      builder: (context) =>
          IssueReportDialog(extraDiagnosticsBuilder: extraDiagnosticsBuilder),
    );
  }
}

class _HomeNetworkError extends StatelessWidget {
  const _HomeNetworkError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height - 180,
      child: Column(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Text(
              context.l10n.home,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    context.l10n.networkError1,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).textTheme.titleLarge!.color,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: InkWell(
                      onTap: onRetry,
                      child: Text(
                        context.l10n.retry,
                        style: TextStyle(color: Theme.of(context).canvasColor),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeContentList extends StatelessWidget {
  const _HomeContentList({
    required this.topPadding,
    required this.homeScreenController,
    required this.getWidgetList,
    required this.reportIssueButton,
  });

  final double topPadding;
  final HomeScreenController homeScreenController;
  final List<Widget> Function(
    dynamic list,
    HomeScreenController homeScreenController,
  )
  getWidgetList;
  final Widget reportIssueButton;

  @override
  Widget build(BuildContext context) {
    homeScreenController.disposeDetachedScrollControllers();
    final items = homeScreenController.isContentFetched
        ? [
            reportIssueButton,
            if (homeScreenController.quickPicks.songList.isNotEmpty)
              Builder(
                builder: (context) {
                  final scrollController = ScrollController();
                  homeScreenController.contentScrollControllers.add(
                    scrollController,
                  );
                  return QuickPicksWidget(
                    content: homeScreenController.quickPicks,
                    scrollController: scrollController,
                  );
                },
              ),
            ...getWidgetList(
              homeScreenController.middleContent,
              homeScreenController,
            ),
            ...getWidgetList(
              homeScreenController.fixedContent,
              homeScreenController,
            ),
          ]
        : [reportIssueButton, const HomeShimmer()];

    return ListView.builder(
      padding: EdgeInsets.only(bottom: 200, top: topPadding),
      itemCount: items.length,
      itemBuilder: (context, index) => items[index],
    );
  }
}

class _DesktopSearchBarHeader extends StatelessWidget {
  const _DesktopSearchBarHeader();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SizedBox(
            width: constraints.maxWidth > 800 ? 800 : constraints.maxWidth - 40,
            child: const Padding(
              padding: EdgeInsets.only(top: 15.0),
              child: DesktopSearchBar(),
            ),
          );
        },
      ),
    );
  }
}
