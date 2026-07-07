import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:harmonymusic/utils/get_localization.dart';

import '../app/providers/controller_providers.dart';
import '../utils/helper.dart';
import '../utils/insets.dart';
import '../utils/runtime_platform.dart';
import '../ui/navigator.dart';
import '../ui/player/player.dart';
import 'player/components/mini_player.dart';
import 'player/player_controller.dart';
import 'widgets/bottom_nav_bar.dart';
import 'widgets/scroll_to_hide.dart';
import 'widgets/sliding_up_panel.dart';
import 'widgets/snackbar.dart';
import 'widgets/system_ui_mode_scope.dart';
import 'widgets/up_next_queue.dart';

class Home extends ConsumerStatefulWidget {
  const Home({super.key});
  static const routeName = '/appHome';

  @override
  ConsumerState<Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<Home> {
  /// Whether the nested [ScreenNavigation] navigator has a route it can pop
  /// (album/playlist/artist/search pushed above the home shell). Tracked via
  /// [NavigationNotification] the same way the framework's
  /// [NavigatorPopHandler] does, so [PopScope.canPop] stays accurate and the
  /// Android predictive-back registration never desyncs.
  bool _nestedCanPop = false;

  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = ref.read(
      playerControllerProvider,
    );
    final settingsScreenController = ref.read(settingsScreenControllerProvider);
    final homeScreenController = ref.read(homeScreenControllerProvider);
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final isWideScreen = size.width > 800;
    if (!playerController.initFlagForPlayer &&
        !settingsScreenController.isBottomNavBarEnabled.value) {
      if (isWideScreen) {
        playerController.playerPanelMinHeight.value =
            105 + bottomNavInset(context);
      } else {
        playerController.playerPanelMinHeight.value =
            75 + bottomNavInset(context);
      }
    }
    return SystemUiModeScope.edgeToEdge(
      child: CallbackShortcuts(
        bindings: {
          LogicalKeySet(LogicalKeyboardKey.space):
              playerController.requestPlayPause,
        },
        child: AnimatedBuilder(
        // Deliberately NOT listening to currentQueue here: rebuilding the
        // whole Scaffold on every queue mutation (shuffle, enqueue, radio
        // continuation) causes a visible hitch. The queue panel and the
        // drawer's song counter have their own scoped listeners.
        animation: Listenable.merge([
          playerController.playerPanelOpen,
          playerController.isQueueLoopModeEnabled,
          playerController.isShuffleModeEnabled,
          playerController.playerPanelMinHeight,
          settingsScreenController.isBottomNavBarEnabled,
          homeScreenController,
        ]),
        builder: (context, _) {
          final panelOpen = playerController.playerPanelOpen.value;
          final onSubTab = homeScreenController.tabIndex != 0;
          // canPop must accurately reflect whether the app handles back:
          // Android predictive back reads it at gesture start, and a stale
          // value hands the gesture to the Activity default (app exit).
          return PopScope(
            canPop: !(panelOpen || _nestedCanPop || onSubTab),
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) {
                // canPop was true: the OS handled it (home-tab minimize).
                return;
              }
              if (panelOpen) {
                printINFO("back: closing player panel", tag: "BackHandler");
                unawaited(playerController.playerPanelController.close());
                return;
              }
              if (_nestedCanPop) {
                printINFO("back: popping nested route", tag: "BackHandler");
                unawaited(
                  ScreenNavigationSetup.navigatorKey.currentState?.maybePop(),
                );
                return;
              }
              if (onSubTab) {
                printINFO("back: switching to home tab", tag: "BackHandler");
                settingsScreenController.isBottomNavBarEnabled.value
                    ? homeScreenController.onBottonBarTabSelected(0)
                    : homeScreenController.onSideBarTabSelected(0);
              }
            },
            child: NotificationListener<NavigationNotification>(
              onNotification: (notification) {
                if (notification.canHandlePop != _nestedCanPop) {
                  setState(() => _nestedCanPop = notification.canHandlePop);
                }
                // The composite "framework handles back" state. A nested pop
                // while on a sub-tab keeps this true even though the nested
                // navigator reported false — if that notification bubbled
                // as-is, WidgetsApp would call setFrameworkHandlesBack(false)
                // and the next back press would go to the Activity default
                // (app exit). Absorb it and re-dispatch the corrected value,
                // mirroring Navigator's own listener.
                final frameworkHandlesBack =
                    _nestedCanPop ||
                    playerController.playerPanelOpen.value ||
                    homeScreenController.tabIndex != 0;
                if (notification.canHandlePop == frameworkHandlesBack) {
                  return false;
                }
                NavigationNotification(
                  canHandlePop: frameworkHandlesBack,
                ).dispatch(context);
                return true;
              },
              child: Scaffold(
                bottomNavigationBar:
                    settingsScreenController.isBottomNavBarEnabled.value
                    ? ScrollToHideWidget(
                        isVisible:
                            homeScreenController.isHomeScreenOnTop &&
                            !playerController.playerPanelOpen.value,
                        child: const BottomNavBar(),
                      )
                    : null,
                key: playerController.homeScaffoldKey,
                endDrawer: RuntimePlatform.isDesktop || isWideScreen
                    ? Container(
                        constraints: const BoxConstraints(maxWidth: 600),
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(10),
                          ),
                          border: Border(
                            left: BorderSide(
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                            top: BorderSide(
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        ),
                        margin: const EdgeInsets.only(top: 5, bottom: 106),
                        child: SizedBox(
                          child: Column(
                            children: [
                              SizedBox(
                                height: 60,
                                child: ColoredBox(
                                  color: Theme.of(context).canvasColor,
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        left: 15.0,
                                        right: 15,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          AnimatedBuilder(
                                            animation:
                                                playerController.currentQueue,
                                            builder: (context, _) => Text(
                                              "${playerController.currentQueue.length} ${"songs".tr}",
                                        ),
                                      ),
                                      Text(
                                        "upNext".tr,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                      Row(
                                        children: [
                                          InkWell(
                                            onTap: () {
                                              unawaited(
                                                playerController
                                                    .toggleQueueLoopMode(),
                                              );
                                            },
                                            child: AnimatedBuilder(
                                              animation: playerController
                                                  .isQueueLoopModeEnabled,
                                              builder: (context, _) => Container(
                                                height: 30,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 20,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      !playerController
                                                          .isQueueLoopModeEnabled
                                                          .value
                                                      ? Colors.white24
                                                      : Colors.white.withValues(
                                                          alpha: 0.8,
                                                        ),
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: Center(
                                                  child: Text("queueLoop".tr),
                                                ),
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: () async {
                                              if (playerController
                                                  .isShuffleModeEnabled
                                                  .value) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  snackbar(
                                                    context,
                                                    "queueShufflingDeniedMsg"
                                                        .tr,
                                                    size: SanckBarSize.BIG,
                                                  ),
                                                );
                                                return;
                                              }
                                              unawaited(
                                                playerController.shuffleQueue(),
                                              );
                                            },
                                            icon: const Icon(Icons.shuffle),
                                          ),
                                          IconButton(
                                            onPressed: () async {
                                              unawaited(
                                                playerController.clearQueue(),
                                              );
                                            },
                                            icon: const Icon(
                                              Icons.playlist_remove,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const Expanded(
                            child: UpNextQueue(isQueueInSlidePanel: false),
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
            drawerScrimColor: Colors.transparent,
            body: SlidingUpPanel(
              onPanelSlide: playerController.panelListener,
              controller: playerController.playerPanelController,
              minHeight: playerController.playerPanelMinHeight.value,
              maxHeight: size.height,
              isDraggable: !isWideScreen,
              onSwipeUp: () async {
                await playerController.queuePanelController.open();
              },
              panel: const Player(),
              body: const ScreenNavigation(),
              header: !isWideScreen
                  ? InkWell(
                      onTap: playerController.playerPanelController.open,
                      child: const MiniPlayer(),
                    )
                  : const MiniPlayer(),
            ),
              ),
            ),
          );
        },
      ),
      ),
    );
  }
}
