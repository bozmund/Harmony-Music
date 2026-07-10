import 'dart:async';
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/utils/get_localization.dart';
import 'package:harmonymusic/services/app_platform_service.dart';
import 'package:harmonymusic/utils/helper.dart';
import 'package:harmonymusic/utils/lang_mapping.dart';

import '../../../app/providers/controller_providers.dart';
import '../../../utils/runtime_platform.dart';
import '../../widgets/awaitable_button.dart';
import '../../widgets/common_dialog_widget.dart';
import '../../widgets/custom_switch.dart';
import '../../widgets/export_file_dialog.dart';
import '../../widgets/import_spotify_playlist_dialog.dart';
import '../../widgets/import_ytmusic_playlist_dialog.dart';
import '../../widgets/backup_dialog.dart';
import '../../widgets/restore_dialog.dart';
import '/services/constant.dart';
import '../Library/library_controller.dart';
import '../../widgets/snackbar.dart';
import '/ui/widgets/link_piped.dart';
import '/services/music_service.dart';
import '/ui/utils/theme_controller.dart';
import 'components/custom_expansion_tile.dart';
import 'settings_screen_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.isBottomNavActive = false});

  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsController = ref.watch(settingsScreenControllerProvider);
    final playerController = ref.read(playerControllerProvider);
    // One-shot: set when something (the release channel prompt, or
    // disabling the update popup) sends the user here to see the update
    // controls; opens the App Info section.
    final revealUpdateSection = settingsController.consumeUpdateSectionReveal();
    final topPadding =
        MediaQuery.orientationOf(context) == Orientation.landscape
            ? 50.0
            : 90.0;
    final isDesktop = RuntimePlatform.isDesktop;
    return AnimatedBuilder(
      animation: Listenable.merge([
        settingsController,
        playerController.playerPanelMinHeight,
      ]),
      builder:
          (context, _) => Padding(
            padding:
                isBottomNavActive
                    ? EdgeInsets.only(left: 20, top: topPadding, right: 15)
                    : EdgeInsets.only(top: topPadding, left: 5, right: 5),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "settings".tr,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 200, top: 20),
                    children: [
                      CustomExpansionTile(
                        title: "personalisation".tr,
                        icon: Icons.palette,
                        childrenBuilder:
                            (context) => [
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: Text("themeMode".tr),
                                subtitle: Text(
                                  settingsController.themeModeType.value ==
                                          ThemeType.dynamic
                                      ? "dynamic".tr
                                      : settingsController
                                              .themeModeType
                                              .value ==
                                          ThemeType.system
                                      ? "systemDefault".tr
                                      : settingsController
                                              .themeModeType
                                              .value ==
                                          ThemeType.dark
                                      ? "dark".tr
                                      : "light".tr,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                onTap: () async {
                                  await showDialog(
                                    context: context,
                                    builder:
                                        (context) =>
                                            const ThemeSelectorDialog(),
                                  );
                                },
                              ),
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: Text("language".tr),
                                subtitle: Text(
                                  "languageDes".tr,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                trailing: DropdownButton(
                                  menuMaxHeight:
                                      MediaQuery.sizeOf(context).height - 250,
                                  dropdownColor: Theme.of(context).cardColor,
                                  underline: const SizedBox.shrink(),
                                  style: Theme.of(context).textTheme.titleSmall,
                                  value:
                                      settingsController
                                          .currentAppLanguageCode
                                          .value,
                                  items:
                                      langMap.entries
                                          .map(
                                            (lang) => DropdownMenuItem(
                                              value: lang.key,
                                              child: Text(lang.value),
                                            ),
                                          )
                                          .whereType<DropdownMenuItem<String>>()
                                          .toList(),
                                  selectedItemBuilder:
                                      (context) =>
                                          langMap.entries.map<Widget>((item) {
                                            return Container(
                                              alignment: Alignment.centerRight,
                                              constraints: const BoxConstraints(
                                                minWidth: 50,
                                              ),
                                              child: Text(item.value),
                                            );
                                          }).toList(),
                                  onChanged: settingsController.setAppLanguage,
                                ),
                              ),
                              if (!isDesktop)
                                ListTile(
                                  contentPadding: const EdgeInsets.only(
                                    left: 5,
                                    right: 10,
                                  ),
                                  title: Text("playerUi".tr),
                                  subtitle: Text(
                                    "playerUiDes".tr,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  trailing: DropdownButton(
                                    dropdownColor: Theme.of(context).cardColor,
                                    underline: const SizedBox.shrink(),
                                    value: settingsController.playerUi.value,
                                    items: [
                                      DropdownMenuItem(
                                        value: 0,
                                        child: Text("standard".tr),
                                      ),
                                      DropdownMenuItem(
                                        value: 1,
                                        child: Text("gesture".tr),
                                      ),
                                    ],
                                    onChanged: settingsController.setPlayerUi,
                                  ),
                                ),
                              if (!isDesktop)
                                ListTile(
                                  contentPadding: const EdgeInsets.only(
                                    left: 5,
                                    right: 10,
                                  ),
                                  title: Text("firstLibraryTab".tr),
                                  subtitle: Text(
                                    "firstLibraryTabDes".tr,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  trailing: DropdownButton(
                                    dropdownColor: Theme.of(context).cardColor,
                                    underline: const SizedBox.shrink(),
                                    value:
                                        settingsController
                                            .libraryFirstTab
                                            .value,
                                    items:
                                        libraryTabKeys
                                            .asMap()
                                            .entries
                                            .map(
                                              (entry) => DropdownMenuItem(
                                                value: entry.key,
                                                child: Text(entry.value.tr),
                                              ),
                                            )
                                            .toList(),
                                    onChanged: (val) async {
                                      if (val == null) return;
                                      await settingsController
                                          .setFirstLibraryTab(val);
                                    },
                                  ),
                                ),
                              if (!isDesktop)
                                ListTile(
                                  contentPadding: const EdgeInsets.only(
                                    left: 5,
                                    right: 10,
                                  ),
                                  title: Text("enableBottomNav".tr),
                                  subtitle: Text(
                                    "enableBottomNavDes".tr,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  trailing: CustomSwitch(
                                    value:
                                        settingsController
                                            .isBottomNavBarEnabled
                                            .value,
                                    onChanged:
                                        settingsController.enableBottomNavBar,
                                  ),
                                ),
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: Text("disableTransitionAnimation".tr),
                                subtitle: Text(
                                  "disableTransitionAnimationDes".tr,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                trailing: CustomSwitch(
                                  value:
                                      settingsController
                                          .isTransitionAnimationDisabled
                                          .value,
                                  onChanged:
                                      settingsController
                                          .disableTransitionAnimation,
                                ),
                              ),
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: Text("enableSlidableAction".tr),
                                subtitle: Text(
                                  "enableSlidableActionDes".tr,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                trailing: CustomSwitch(
                                  value:
                                      settingsController
                                          .slidableActionEnabled
                                          .value,
                                  onChanged:
                                      settingsController.toggleSlidableAction,
                                ),
                              ),
                            ],
                      ),
                      CustomExpansionTile(
                        title: "content".tr,
                        icon: Icons.music_video,
                        childrenBuilder:
                            (context) => [
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: Text("setDiscoverContent".tr),
                                subtitle: Text(
                                  settingsController
                                              .discoverContentType
                                              .value ==
                                          "QP"
                                      ? "quickpicks".tr
                                      : settingsController
                                              .discoverContentType
                                              .value ==
                                          "TMV"
                                      ? "topmusicvideos".tr
                                      : settingsController
                                              .discoverContentType
                                              .value ==
                                          "TR"
                                      ? "trending".tr
                                      : "basedOnLast".tr,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                onTap: () async {
                                  await showDialog(
                                    context: context,
                                    builder:
                                        (context) =>
                                            const DiscoverContentSelectorDialog(),
                                  );
                                },
                              ),
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: Text("homeContentCount".tr),
                                subtitle: Text(
                                  "homeContentCountDes".tr,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                trailing: DropdownButton(
                                  dropdownColor: Theme.of(context).cardColor,
                                  underline: const SizedBox.shrink(),
                                  value:
                                      settingsController
                                          .noOfHomeScreenContent
                                          .value,
                                  items:
                                      [3, 5, 7, 9, 11]
                                          .map(
                                            (e) => DropdownMenuItem(
                                              value: e,
                                              child: Text("$e"),
                                            ),
                                          )
                                          .toList(),
                                  onChanged:
                                      settingsController.setContentNumber,
                                ),
                              ),
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: Text("cacheHomeScreenData".tr),
                                subtitle: Text(
                                  "cacheHomeScreenDataDes".tr,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                trailing: CustomSwitch(
                                  value:
                                      settingsController
                                          .cacheHomeScreenData
                                          .value,
                                  onChanged:
                                      settingsController
                                          .toggleCacheHomeScreenData,
                                ),
                              ),
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: const Text("Reset app state"),
                                subtitle: Text(
                                  "Clears cached home content, saved playback session, temporary stream URLs, and returns navigation to Home.",
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                trailing: AwaitableButton.text(
                                  label: Text(
                                    "reset".tr,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium!
                                        .copyWith(fontSize: 15),
                                  ),
                                  onPressed: () async {
                                    await settingsController
                                        .resetRecoverableAppState();
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      snackbar(
                                        context,
                                        "App state reset",
                                        size: SanckBarSize.MEDIUM,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                  top: 0,
                                ),
                                title: Text("Piped".tr),
                                subtitle: Text(
                                  "linkPipedDes".tr,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                trailing: TextButton(
                                  child: Text(
                                    settingsController.isLinkedWithPiped.value
                                        ? "unLink".tr
                                        : "link".tr,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium!
                                        .copyWith(fontSize: 15),
                                  ),
                                  onPressed: () {
                                    if (!settingsController
                                        .isLinkedWithPiped
                                        .value) {
                                      unawaited(
                                        showDialog(
                                          context: context,
                                          builder:
                                              (context) => const LinkPiped(),
                                        ),
                                      );
                                    } else {
                                      unawaited(
                                        settingsController.unlinkPiped(),
                                      );
                                    }
                                  },
                                ),
                              ),
                              settingsController.isLinkedWithPiped.value
                                  ? ListTile(
                                    contentPadding: const EdgeInsets.only(
                                      left: 5,
                                      right: 10,
                                      top: 0,
                                    ),
                                    title: Text("resetBlacklistedPlaylist".tr),
                                    subtitle: Text(
                                      "resetBlacklistedPlaylistDes".tr,
                                      style:
                                          Theme.of(
                                            context,
                                          ).textTheme.bodyMedium,
                                    ),
                                    trailing: AwaitableButton.text(
                                      label: Text(
                                        "reset".tr,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium!
                                            .copyWith(fontSize: 15),
                                      ),
                                      onPressed: () async {
                                        await LibraryPlaylistsControllerRegistry
                                            .current
                                            ?.resetBlacklistedPlaylist();
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          snackbar(
                                            context,
                                            "blacklistPlaylistResetAlert".tr,
                                            size: SanckBarSize.MEDIUM,
                                          ),
                                        );
                                      },
                                    ),
                                  )
                                  : const SizedBox.shrink(),
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: Text("clearImgCache".tr),
                                subtitle: Text(
                                  "clearImgCacheDes".tr,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                isThreeLine: true,
                                onTap: () {
                                  unawaited(
                                    settingsController.clearImagesCache().then((
                                      value,
                                    ) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        snackbar(
                                          context,
                                          "clearImgCacheAlert".tr,
                                          size: SanckBarSize.BIG,
                                        ),
                                      );
                                    }),
                                  );
                                },
                              ),
                            ],
                      ),
                      CustomExpansionTile(
                        title: "music&Playback".tr,
                        icon: Icons.music_note,
                        childrenBuilder:
                            (context) => [
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: Text("streamingQuality".tr),
                                subtitle: Text(
                                  "streamingQualityDes".tr,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                trailing: DropdownButton(
                                  dropdownColor: Theme.of(context).cardColor,
                                  underline: const SizedBox.shrink(),
                                  value:
                                      settingsController.streamingQuality.value,
                                  items: [
                                    DropdownMenuItem(
                                      value: AudioQuality.Low,
                                      child: Text("low".tr),
                                    ),
                                    DropdownMenuItem(
                                      value: AudioQuality.High,
                                      child: Text("high".tr),
                                    ),
                                  ],
                                  onChanged:
                                      settingsController.setStreamingQuality,
                                ),
                              ),
                              if (RuntimePlatform.isAndroid)
                                ListTile(
                                  contentPadding: const EdgeInsets.only(
                                    left: 5,
                                    right: 10,
                                  ),
                                  title: const Text("Playback mode"),
                                  subtitle: Text(
                                    "Classic uses the stable one-song player. Preloaded is experimental.",
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  trailing: DropdownButton<PlaybackMode>(
                                    dropdownColor: Theme.of(context).cardColor,
                                    underline: const SizedBox.shrink(),
                                    value:
                                        settingsController.playbackMode.value,
                                    items: const [
                                      DropdownMenuItem<PlaybackMode>(
                                        value: PlaybackMode.classic,
                                        child: Text("Classic"),
                                      ),
                                      DropdownMenuItem<PlaybackMode>(
                                        value: PlaybackMode.preloaded,
                                        child: Text("Preloaded"),
                                      ),
                                    ],
                                    onChanged:
                                        settingsController.setPlaybackMode,
                                  ),
                                ),
                              if (RuntimePlatform.isAndroid)
                                settingsController.playbackMode.value ==
                                        PlaybackMode.preloaded
                                    ? ListTile(
                                      contentPadding: const EdgeInsets.only(
                                        left: 5,
                                        right: 10,
                                      ),
                                      title: const Text(
                                        "Playback preload range",
                                      ),
                                      subtitle: Text(
                                        "Higher values prepare nearby songs while playback is active.",
                                        style:
                                            Theme.of(
                                              context,
                                            ).textTheme.bodyMedium,
                                      ),
                                      trailing: DropdownButton<int>(
                                        dropdownColor:
                                            Theme.of(context).cardColor,
                                        underline: const SizedBox.shrink(),
                                        value:
                                            settingsController
                                                .playbackPreloadRange
                                                .value,
                                        items: List.generate(5, (index) {
                                          final range = index + 1;
                                          return DropdownMenuItem<int>(
                                            value: range,
                                            child: Text("$range"),
                                          );
                                        }),
                                        onChanged:
                                            settingsController
                                                .setPlaybackPreloadRange,
                                      ),
                                    )
                                    : const SizedBox.shrink(),
                              if (RuntimePlatform.isAndroid)
                                ListTile(
                                  contentPadding: const EdgeInsets.only(
                                    left: 5,
                                    right: 10,
                                  ),
                                  title: Text("loudnessNormalization".tr),
                                  subtitle: Text(
                                    "loudnessNormalizationDes".tr,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  trailing: CustomSwitch(
                                    value:
                                        settingsController
                                            .loudnessNormalizationEnabled
                                            .value,
                                    onChanged:
                                        settingsController
                                            .toggleLoudnessNormalization,
                                  ),
                                ),
                              if (!isDesktop)
                                ListTile(
                                  contentPadding: const EdgeInsets.only(
                                    left: 5,
                                    right: 10,
                                  ),
                                  title: Text("cacheSongs".tr),
                                  subtitle: Text(
                                    "cacheSongsDes".tr,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  trailing: CustomSwitch(
                                    value: settingsController.cacheSongs.value,
                                    onChanged:
                                        settingsController
                                            .toggleCachingSongsValue,
                                  ),
                                ),
                              if (!isDesktop)
                                ListTile(
                                  contentPadding: const EdgeInsets.only(
                                    left: 5,
                                    right: 10,
                                  ),
                                  title: Text("skipSilence".tr),
                                  subtitle: Text(
                                    "skipSilenceDes".tr,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  trailing: CustomSwitch(
                                    value:
                                        settingsController
                                            .skipSilenceEnabled
                                            .value,
                                    onChanged:
                                        settingsController.toggleSkipSilence,
                                  ),
                                ),
                              if (isDesktop)
                                ListTile(
                                  contentPadding: const EdgeInsets.only(
                                    left: 5,
                                    right: 10,
                                  ),
                                  title: Text("backgroundPlay".tr),
                                  subtitle: Text(
                                    "backgroundPlayDes".tr,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  trailing: CustomSwitch(
                                    value:
                                        settingsController
                                            .backgroundPlayEnabled
                                            .value,
                                    onChanged:
                                        settingsController.toggleBackgroundPlay,
                                  ),
                                ),
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: Text("keepScreenOnWhilePlaying".tr),
                                subtitle: Text(
                                  "keepScreenOnWhilePlayingDes".tr,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                trailing: CustomSwitch(
                                  value:
                                      settingsController.keepScreenAwake.value,
                                  onChanged:
                                      settingsController.toggleKeepScreenAwake,
                                ),
                              ),
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: Text("restoreLastPlaybackSession".tr),
                                subtitle: Text(
                                  "restoreLastPlaybackSessionDes".tr,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                trailing: CustomSwitch(
                                  value:
                                      settingsController
                                          .restorePlaybackSession
                                          .value,
                                  onChanged:
                                      settingsController
                                          .toggleRestorePlaybackSession,
                                ),
                              ),
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: Text("autoOpenPlayer".tr),
                                subtitle: Text(
                                  "autoOpenPlayerDes".tr,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                trailing: CustomSwitch(
                                  value:
                                      settingsController.autoOpenPlayer.value,
                                  onChanged:
                                      settingsController.toggleAutoOpenPlayer,
                                ),
                              ),
                              if (!isDesktop)
                                ListTile(
                                  contentPadding: const EdgeInsets.only(
                                    left: 5,
                                    right: 10,
                                    top: 0,
                                  ),
                                  title: Text("equalizer".tr),
                                  subtitle: Text(
                                    "equalizerDes".tr,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  onTap: () async {
                                    try {
                                      await playerController.openEqualizer();
                                    } catch (e) {
                                      printERROR(e);
                                    }
                                  },
                                ),
                              if (!isDesktop)
                                ListTile(
                                  contentPadding: const EdgeInsets.only(
                                    left: 5,
                                    right: 10,
                                  ),
                                  title: Text("stopMusicOnTaskClear".tr),
                                  subtitle: Text(
                                    "stopMusicOnTaskClearDes".tr,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  trailing: CustomSwitch(
                                    value:
                                        settingsController
                                            .stopPlaybackOnSwipeAway
                                            .value,
                                    onChanged:
                                        settingsController
                                            .toggleStopPlaybackOnSwipeAway,
                                  ),
                                ),
                              if (RuntimePlatform.isAndroid)
                                ListTile(
                                  contentPadding: const EdgeInsets.only(
                                    left: 5,
                                    right: 10,
                                  ),
                                  title: Text("ignoreBatOpt".tr),
                                  onTap:
                                      settingsController
                                          .openBatteryOptimizationSettings,
                                  subtitle: RichText(
                                    text: TextSpan(
                                      text:
                                          "${"status".tr}: ${settingsController.isIgnoringBatteryOptimizations.value ? "enabled".tr : "disabled".tr}\n",
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium!.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                      children: <TextSpan>[
                                        TextSpan(
                                          text: "ignoreBatOptDes".tr,
                                          style:
                                              Theme.of(
                                                context,
                                              ).textTheme.bodyMedium,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                      ),
                      CustomExpansionTile(
                        title: "download".tr,
                        icon: Icons.download,
                        childrenBuilder:
                            (context) => [
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: Text("autoDownFavSong".tr),
                                subtitle: Text(
                                  "autoDownFavSongDes".tr,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                trailing: CustomSwitch(
                                  value:
                                      settingsController
                                          .autoDownloadFavoriteSongEnabled
                                          .value,
                                  onChanged:
                                      settingsController
                                          .toggleAutoDownloadFavoriteSong,
                                ),
                              ),
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: Text("downloadingFormat".tr),
                                subtitle: Text(
                                  "downloadingFormatDes".tr,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                trailing: DropdownButton(
                                  dropdownColor: Theme.of(context).cardColor,
                                  underline: const SizedBox.shrink(),
                                  value:
                                      settingsController
                                          .downloadingFormat
                                          .value,
                                  items: const [
                                    DropdownMenuItem(
                                      value: "opus",
                                      child: Text("Opus/Ogg"),
                                    ),
                                    DropdownMenuItem(
                                      value: "m4a",
                                      child: Text("M4a"),
                                    ),
                                  ],
                                  onChanged:
                                      settingsController
                                          .changeDownloadingFormat,
                                ),
                              ),
                              ListTile(
                                trailing: AwaitableButton.text(
                                  label: Text(
                                    "reset".tr,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium!
                                        .copyWith(fontSize: 15),
                                  ),
                                  onPressed: () async {
                                    await settingsController
                                        .resetDownloadLocation();
                                  },
                                ),
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                  top: 0,
                                ),
                                title: Text("downloadLocation".tr),
                                subtitle: Text(
                                  settingsController
                                          .isCurrentPathSupportDownloadDir
                                      ? "In App storage directory"
                                      : settingsController
                                          .downloadLocationPath
                                          .value,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                onTap: () async {
                                  unawaited(
                                    settingsController.setDownloadLocation(),
                                  );
                                },
                              ),
                              if (RuntimePlatform.isAndroid)
                                ListTile(
                                  contentPadding: const EdgeInsets.only(
                                    left: 5,
                                    right: 10,
                                  ),
                                  title: Text("exportDownloadedFiles".tr),
                                  subtitle: Text(
                                    "exportDownloadedFilesDes".tr,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  isThreeLine: true,
                                  onTap: () async {
                                    await showDialog(
                                      context: context,
                                      builder:
                                          (context) => const ExportFileDialog(),
                                    );
                                  },
                                ),
                              if (RuntimePlatform.isAndroid)
                                ListTile(
                                  contentPadding: const EdgeInsets.only(
                                    left: 5,
                                    right: 10,
                                    top: 0,
                                  ),
                                  title: Text("exportedFileLocation".tr),
                                  subtitle: Text(
                                    settingsController.exportLocationPath.value,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  onTap: () async {
                                    unawaited(
                                      settingsController.setExportedLocation(),
                                    );
                                  },
                                ),
                            ],
                      ),
                      CustomExpansionTile(
                        title: "${"backup".tr} & ${"restore".tr}",
                        icon: Icons.restore,
                        childrenBuilder:
                            (context) => [
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: Text("backupAppData".tr),
                                subtitle: Text(
                                  "backupSettingsAndPlaylistsDes".tr,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                isThreeLine: true,
                                onTap: () async {
                                  await showDialog(
                                    context: context,
                                    builder: (context) => const BackupDialog(),
                                  );
                                },
                              ),
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: Text("restoreAppData".tr),
                                subtitle: Text(
                                  "restoreSettingsAndPlaylistsDes".tr,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                isThreeLine: true,
                                onTap: () async {
                                  await showDialog(
                                    context: context,
                                    builder: (context) => const RestoreDialog(),
                                  );
                                },
                              ),
                              if (RuntimePlatform.isAndroid) const Divider(),
                              if (RuntimePlatform.isAndroid)
                                ListTile(
                                  contentPadding: const EdgeInsets.only(
                                    left: 5,
                                    right: 10,
                                  ),
                                  title: const Text("Export clone package"),
                                  subtitle: Text(
                                    "Copies this app's DB, downloads, and thumbnails to a shared folder.",
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  isThreeLine: true,
                                  onTap:
                                      settingsController
                                          .exportDeveloperClonePackage,
                                ),
                              if (RuntimePlatform.isAndroid)
                                ListTile(
                                  contentPadding: const EdgeInsets.only(
                                    left: 5,
                                    right: 10,
                                  ),
                                  title: const Text("Import clone package"),
                                  subtitle: Text(
                                    "Overwrites this app sandbox with a clone export and rewrites download paths.",
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  isThreeLine: true,
                                  onTap:
                                      settingsController
                                          .importDeveloperClonePackage,
                                ),
                            ],
                      ),
                      CustomExpansionTile(
                        title: "Import",
                        icon: Icons.playlist_add,
                        childrenBuilder:
                            (context) => [
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: const Text(
                                  "Import YouTube Music playlist",
                                ),
                                subtitle: Text(
                                  "Creates a local playlist from a public YouTube Music or YouTube playlist URL.",
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                isThreeLine: true,
                                onTap: () async {
                                  await showDialog(
                                    context: context,
                                    builder:
                                        (context) =>
                                            const ImportYtMusicPlaylistDialog(),
                                  );
                                },
                              ),
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: const Text("Import Spotify export"),
                                subtitle: Text(
                                  "Creates local playlists from Spotify account-data playlist and library JSON or ZIP exports.",
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                isThreeLine: true,
                                onTap: () async {
                                  await showDialog(
                                    context: context,
                                    builder:
                                        (context) =>
                                            const ImportSpotifyPlaylistDialog(),
                                  );
                                },
                              ),
                            ],
                      ),
                      CustomExpansionTile(
                        icon: Icons.miscellaneous_services,
                        title: "misc".tr,
                        childrenBuilder:
                            (context) => [
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: Text("resetToDefault".tr),
                                subtitle: Text(
                                  "resetToDefaultDes".tr,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                onTap: () {
                                  unawaited(
                                    settingsController
                                        .resetAppSettingsToDefault()
                                        .then((_) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            snackbar(
                                              context,
                                              "resetToDefaultMsg".tr,
                                              size: SanckBarSize.BIG,
                                              duration: const Duration(
                                                seconds: 2,
                                              ),
                                            ),
                                          );
                                        }),
                                  );
                                },
                              ),
                            ],
                      ),
                      CustomExpansionTile(
                        icon: Icons.info,
                        title: "appInfo".tr,
                        initiallyExpanded: revealUpdateSection,
                        childrenBuilder:
                            (context) => [
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: Text("github".tr),
                                subtitle: Text(
                                  "${"githubDes".tr}${((playerController.playerPanelMinHeight.value) == 0 || !isBottomNavActive) ? "" : "\n\n${settingsController.currentVersion} ${"by".tr} bozmund"}",
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                isThreeLine: true,
                                onTap: () {
                                  unawaited(
                                    AppPlatformService.openUrl(
                                      'https://github.com/bozmund/Harmony-Music',
                                    ),
                                  );
                                },
                              ),
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: Text("checkUpdate".tr),
                                subtitle: Text(
                                  "Click here to check for updates manually",
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                onTap: () async {
                                  await settingsController.checkUpdate(context);
                                },
                              ),
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                title: const Text("Update channel"),
                                subtitle: Text(
                                  "Stable follows production releases. Rolling follows main-latest candidate builds.",
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                trailing: DropdownButton<String>(
                                  dropdownColor: Theme.of(context).cardColor,
                                  underline: const SizedBox.shrink(),
                                  value:
                                      settingsController
                                          .updateChannel
                                          .value
                                          .name,
                                  items: const [
                                    DropdownMenuItem(
                                      value: "stable",
                                      child: Text("Stable"),
                                    ),
                                    DropdownMenuItem(
                                      value: "rolling",
                                      child: Text("Rolling"),
                                    ),
                                  ],
                                  onChanged:
                                      settingsController.changeUpdateChannel,
                                ),
                              ),
                              const Divider(),
                              SizedBox(
                                child: Column(
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        unawaited(
                                          settingsController
                                              .setDeveloperSettingsEnabled(
                                                !settingsController
                                                    .developerSettingsEnabled
                                                    .value,
                                              ),
                                        );
                                      },
                                      child: Text(
                                        "Harmony Music",
                                        style:
                                            Theme.of(
                                              context,
                                            ).textTheme.titleLarge,
                                      ),
                                    ),
                                    Text(
                                      settingsController.currentVersion,
                                      style:
                                          Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                      ),
                      settingsController.developerSettingsEnabled.value
                          ? const _DeveloperSettingsInspector()
                          : const SizedBox.shrink(),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 20.0),
                  child: Text(
                    "${settingsController.currentVersion} ${"by".tr} bozmund",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
    );
  }
}

class _DeveloperSettingsInspector extends ConsumerWidget {
  const _DeveloperSettingsInspector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsController = ref.watch(settingsScreenControllerProvider);
    return CustomExpansionTile(
      icon: Icons.developer_mode,
      title: "Developer settings",
      childrenBuilder:
          (context) => [
            ListTile(
              contentPadding: const EdgeInsets.only(left: 5, right: 10),
              title: const Text("Refresh values"),
              subtitle: Text(
                "Reloads current AppPrefs, build, and update debug values.",
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              trailing: IconButton(
                tooltip: "Refresh values",
                icon: const Icon(Icons.refresh),
                onPressed: settingsController.refreshDeveloperSettingValues,
              ),
            ),
            const Divider(),
            AnimatedBuilder(
              animation: settingsController,
              builder:
                  (context, _) => Column(
                    children:
                        settingsController.developerSettingValues
                            .map(
                              (entry) => ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 5,
                                  right: 10,
                                ),
                                dense: true,
                                title: SelectableText(
                                  entry.name,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                subtitle: SelectableText(
                                  entry.value,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            )
                            .toList(),
                  ),
            ),
          ],
    );
  }
}

class ThemeSelectorDialog extends ConsumerWidget {
  const ThemeSelectorDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsController = ref.watch(settingsScreenControllerProvider);
    return CommonDialog(
      child: Container(
        height: 300,
        //color: Theme.of(context).cardColor,
        padding: const EdgeInsets.only(top: 30, left: 5, right: 30, bottom: 10),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 20.0, bottom: 5),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "themeMode".tr,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            radioWidget(
              context: context,
              label: "dynamic".tr,
              controller: settingsController,
              value: ThemeType.dynamic,
            ),
            radioWidget(
              context: context,
              label: "systemDefault".tr,
              controller: settingsController,
              value: ThemeType.system,
            ),
            radioWidget(
              context: context,
              label: "dark".tr,
              controller: settingsController,
              value: ThemeType.dark,
            ),
            radioWidget(
              context: context,
              label: "light".tr,
              controller: settingsController,
              value: ThemeType.light,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text("cancel".tr),
                ),
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DiscoverContentSelectorDialog extends ConsumerWidget {
  const DiscoverContentSelectorDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsController = ref.watch(settingsScreenControllerProvider);
    return CommonDialog(
      child: Container(
        height: 300,
        //color: Theme.of(context).cardColor,
        padding: const EdgeInsets.only(top: 30, left: 5, right: 30, bottom: 10),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 20.0, bottom: 5),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "setDiscoverContent".tr,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            SizedBox(
              height: 180,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    radioWidget(
                      context: context,
                      label: "quickpicks".tr,
                      controller: settingsController,
                      value: "QP",
                    ),
                    radioWidget(
                      context: context,
                      label: "topmusicvideos".tr,
                      controller: settingsController,
                      value: "TMV",
                    ),
                    radioWidget(
                      context: context,
                      label: "trending".tr,
                      controller: settingsController,
                      value: "TR",
                    ),
                    radioWidget(
                      context: context,
                      label: "basedOnLast".tr,
                      controller: settingsController,
                      value: "BOLI",
                    ),
                  ],
                ),
              ),
            ),
            const Expanded(child: SizedBox()),
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text("cancel".tr),
                ),
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget radioWidget({
  required BuildContext context,
  required String label,
  required SettingsScreenController controller,
  required value,
}) {
  return AnimatedBuilder(
    animation: controller,
    builder:
        (context, _) => ListTile(
          visualDensity: const VisualDensity(vertical: -4),
          onTap: () async {
            if (value.runtimeType == ThemeType) {
              await controller.onThemeChange(value);
            } else {
              await controller.onContentChange(value);
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            }
          },
          leading: Radio(
            value: value,
            groupValue:
                value.runtimeType == ThemeType
                    ? controller.themeModeType.value
                    : controller.discoverContentType.value,
            onChanged:
                value.runtimeType == ThemeType
                    ? controller.onThemeChange
                    : controller.onContentChange,
          ),
          title: Text(label),
        ),
  );
}
