import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/utils/get_localization.dart';

import '../../../app/providers/controller_providers.dart';
import '../../../app/providers/repository_providers.dart';
import '../../../app/providers/service_providers.dart';
import '../../../utils/runtime_platform.dart';
import '/ui/screens/Artists/artist_screen_v2.dart';
import '../../widgets/animated_screen_transition.dart';
import '../../widgets/loader.dart';
import '../../widgets/separate_tab_item_widget.dart';
import '../../../services/app_platform_service.dart';
import '/ui/widgets/image_widget.dart';
import '../../navigator.dart';
import '../../widgets/snackbar.dart';
import 'artist_screen_controller.dart';

class ArtistScreen extends ConsumerStatefulWidget {
  const ArtistScreen({super.key});

  @override
  ConsumerState<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends ConsumerState<ArtistScreen>
    with SingleTickerProviderStateMixin {
  late final String tag;
  ArtistScreenController? _artistScreenController;

  @override
  void initState() {
    super.initState();
    tag = widget.key.hashCode.toString();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_artistScreenController != null) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final controller = ArtistScreenController(
      musicService: container.read(musicServiceContractProvider),
      libraryRepository: container.read(libraryRepositoryProvider),
      settingsScreenController: container.read(
        settingsScreenControllerProvider,
      ),
      homeScreenController: container.read(homeScreenControllerProvider),
    );
    ArtistScreenControllerRegistry.register(tag, controller);
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is! List) {
      throw StateError('ArtistScreen requires list route arguments');
    }
    controller.initialize(
      isIdOnly: args[0] as bool,
      artist: args[1],
      isDesktopLayout: RuntimePlatform.isDesktop,
      vsync: this,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.ready());
    _artistScreenController = controller;
  }

  @override
  void dispose() {
    final controller = _artistScreenController;
    if (controller != null) {
      ArtistScreenControllerRegistry.unregister(tag, controller);
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerController = ref.read(playerControllerProvider);
    final settingsController = ref.watch(settingsScreenControllerProvider);
    final artistScreenController = _artistScreenController!;
    return Scaffold(
      floatingActionButton: AnimatedBuilder(
        animation: playerController.playerPanelMinHeight,
        builder: (context, _) => Padding(
          padding: EdgeInsets.only(
            bottom: playerController.playerPanelMinHeight.value,
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
                  final radioId = artistScreenController.artist_.radioId;
                  if (radioId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      snackbar(
                        context,
                        "radioNotAvailable".tr,
                        size: SanckBarSize.BIG,
                      ),
                    );
                    return;
                  }
                  unawaited(
                    playerController.startRadio(
                      null,
                      playlistId: artistScreenController.artist_.radioId,
                    ),
                  );
                },
                child: const Icon(Icons.sensors),
              ),
            ),
          ),
        ),
      ),
      body:
          RuntimePlatform.isDesktop ||
              settingsController.isBottomNavBarEnabled.value
          ? ArtistScreenBN(
              artistScreenController: artistScreenController,
              tag: tag,
            )
          : Row(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 80),
                    child: IntrinsicHeight(
                      child: AnimatedBuilder(
                        animation: artistScreenController,
                        builder: (context, _) => NavigationRail(
                          onDestinationSelected:
                              artistScreenController.onDestinationSelected,
                          minWidth: 60,
                          destinations: [
                            "about".tr,
                            "songs".tr,
                            "videos".tr,
                            "albums".tr,
                            "singles".tr,
                          ].map((e) => railDestination(e)).toList(),
                          leading: Column(
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.orientationOf(context) ==
                                        Orientation.landscape
                                    ? 20.0
                                    : 45.0,
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
                                      .currentState
                                      ?.pop();
                                },
                              ),
                              const SizedBox(height: 10),
                            ],
                          ),
                          labelType: NavigationRailLabelType.all,
                          selectedIndex:
                              artistScreenController.navigationRailCurrentIndex,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: AnimatedBuilder(
                    animation: artistScreenController,
                    builder: (context, _) => AnimatedScreenTransition(
                      enabled: settingsController
                          .isTransitionAnimationDisabled
                          .value,
                      resverse: artistScreenController.isTabTransitionReversed,
                      child: Center(
                        key: ValueKey<int>(
                          artistScreenController.navigationRailCurrentIndex,
                        ),
                        child: Body(tag: tag),
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
      label: RotatedBox(quarterTurns: -1, child: Text(label)),
    );
  }
}

class Body extends StatelessWidget {
  const Body({super.key, required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    final ArtistScreenController artistScreenController =
        ArtistScreenControllerRegistry.maybeOf(tag)!;

    final tabIndex = artistScreenController.navigationRailCurrentIndex;

    if (tabIndex == 0) {
      return AnimatedBuilder(
        animation: artistScreenController,
        builder: (context, _) => artistScreenController.isArtistContentFetched
            ? AboutArtist(artistScreenController: artistScreenController)
            : const Center(child: LoadingIndicator()),
      );
    } else {
      final separatedContent = artistScreenController.separatedContent;
      final currentTabName = [
        "About",
        "Songs",
        "Videos",
        "Albums",
        "Singles",
      ][tabIndex];
      return AnimatedBuilder(
        animation: artistScreenController,
        builder: (context, _) {
          if (!artistScreenController.isSeparatedArtistContentFetched &&
              artistScreenController.navigationRailCurrentIndex != 0) {
            return const Center(child: LoadingIndicator());
          }
          return SeparateTabItemWidget(
            artistControllerTag: tag,
            isResultWidget: false,
            items: separatedContent.containsKey(currentTabName)
                ? separatedContent[currentTabName]['results']
                : [],
            title: currentTabName,
            topPadding:
                MediaQuery.orientationOf(context) == Orientation.landscape
                ? 50.0
                : 80.0,
            scrollController: currentTabName == "Songs"
                ? artistScreenController.songScrollController
                : currentTabName == "Videos"
                ? artistScreenController.videoScrollController
                : currentTabName == "Albums"
                ? artistScreenController.albumScrollController
                : currentTabName == "Singles"
                ? artistScreenController.singlesScrollController
                : null,
          );
        },
      );
    }
  }
}

class AboutArtist extends StatelessWidget {
  const AboutArtist({
    super.key,
    required this.artistScreenController,
    this.padding = const EdgeInsets.only(bottom: 90, top: 70),
  });
  final EdgeInsetsGeometry padding;
  final ArtistScreenController artistScreenController;

  @override
  Widget build(BuildContext context) {
    final artistData = artistScreenController.artistData;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SingleChildScrollView(
          padding: padding,
          child: artistScreenController.isArtistContentFetched
              ? Column(
                  children: [
                    SizedBox(
                      height: 200,
                      width: 260,
                      child: Stack(
                        children: [
                          Center(
                            child: ImageWidget(
                              size: 200,
                              artist: artistScreenController.artist_,
                            ),
                          ),
                          Align(
                            alignment: Alignment.topRight,
                            child: Column(
                              children: [
                                InkWell(
                                  onTap: () async {
                                    final bool add =
                                        artistScreenController
                                            .isAddedToLibrary ==
                                        false;
                                    await artistScreenController
                                        .addNRemoveFromLibrary(add: add)
                                        .then((value) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              snackbar(
                                                context,
                                                value
                                                    ? add
                                                          ? "artistBookmarkAddAlert"
                                                                .tr
                                                          : "artistBookmarkRemoveAlert"
                                                                .tr
                                                    : "operationFailed".tr,
                                                size: SanckBarSize.MEDIUM,
                                              ),
                                            );
                                          }
                                        });
                                  },
                                  child: AnimatedBuilder(
                                    animation: artistScreenController,
                                    builder: (context, _) =>
                                        !artistScreenController
                                            .isArtistContentFetched
                                        ? const SizedBox.shrink()
                                        : Icon(
                                            !artistScreenController
                                                    .isAddedToLibrary
                                                ? Icons.bookmark_add
                                                : Icons.bookmark_added,
                                          ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.share, size: 20),
                                  splashRadius: 18,
                                  onPressed: () => AppPlatformService.shareText(
                                    "https://music.youtube.com/channel/${artistScreenController.artist_.browseId}",
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 10),
                      child: Text(
                        artistScreenController.artist_.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    (artistData.containsKey("description") &&
                            artistData["description"] != null)
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "\"${artistData["description"]}\"",
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          )
                        : SizedBox(
                            height: 300,
                            child: Center(
                              child: Text(
                                "artistDesNotAvailable".tr,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                          ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
