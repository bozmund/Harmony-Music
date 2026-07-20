import 'dart:async';
// ignore_for_file: deprecated_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/l10n/l10n.dart';
import 'package:harmonymusic/services/app_platform_service.dart';
import 'package:harmonymusic/utils/helper.dart';
import 'package:harmonymusic/utils/lang_mapping.dart';

import '../../../app/providers/controller_providers.dart';
import '../../../app/providers/auth_providers.dart';
import '../../../services/cloud/cloud_audio_backup_service.dart';
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
import '/services/resolver/resolver_source_mode.dart';
import '../Library/library_controller.dart';
import '../../widgets/snackbar.dart';
import '/ui/widgets/link_piped.dart';
import '/services/music_service.dart';
import '/ui/utils/theme_controller.dart';
import 'components/custom_expansion_tile.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';

bool _cloudOptInDialogOpen = false;
const _latestAndroidApkUrl =
    'https://github.com/bozmund/Harmony-Music/releases/download/main-latest/harmonymusic-main-latest.apk';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.isBottomNavActive = false});

  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsController = ref.watch(settingsScreenControllerProvider);
    final authController = ref.watch(authControllerProvider);
    if (authController.needsCloudOptIn && !_cloudOptInDialogOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          unawaited(_showCloudOptInDialog(context, authController));
        }
      });
    }
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
      builder: (context, _) => Padding(
        padding: isBottomNavActive
            ? EdgeInsets.only(left: 20, top: topPadding, right: 15)
            : EdgeInsets.only(top: topPadding, left: 5, right: 5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.l10n.settings,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 200, top: 20),
                children: [
                  CustomExpansionTile(
                    title: context.l10n.accountSection,
                    icon: Icons.account_circle,
                    childrenBuilder: (context) => [
                      ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 5,
                          right: 10,
                        ),
                        leading: authController.userProfile?.pictureUrl == null
                            ? const Icon(Icons.person_outline)
                            : CircleAvatar(
                                backgroundImage: NetworkImage(
                                  authController.userProfile!.pictureUrl
                                      .toString(),
                                ),
                              ),
                        title: Text(
                          authController.isAuthenticated
                              ? (authController.userProfile?.name ??
                                    context.l10n.accountSection)
                              : context.l10n.optionalAccount,
                        ),
                        subtitle: Text(
                          authController.isAuthenticated
                              ? "${context.l10n.loggedInAs} ${authController.userProfile?.email ?? authController.userProfile!.sub}"
                              : !authController.isSupportedPlatform
                              ? context.l10n.authUnsupportedPlatform
                              : authController.isConfigured
                              ? context.l10n.optionalAccountDes
                              : context.l10n.authNotConfigured,
                        ),
                        trailing: authController.isBusy
                            ? const SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : TextButton(
                                onPressed: !authController.isAvailable
                                    ? null
                                    : authController.isAuthenticated
                                    ? authController.logout
                                    : authController.login,
                                child: Text(
                                  authController.isAuthenticated
                                      ? context.l10n.logout
                                      : context.l10n.loginOrRegister,
                                ),
                              ),
                      ),
                      if (authController.errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(5, 0, 10, 12),
                          child: Text(
                            authController.errorMessage!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (authController.isAuthenticated)
                        ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 5,
                            right: 10,
                          ),
                          leading: const Icon(Icons.cloud_sync_outlined),
                          title: Text(context.l10n.cloudBackup),
                          subtitle: Text(context.l10n.cloudBackupDescription),
                          trailing: CustomSwitch(
                            value: authController.cloudSyncEnabled,
                            onChanged: authController.setCloudSyncEnabled,
                          ),
                        ),
                      if (authController.isAuthenticated &&
                          authController.cloudSyncEnabled)
                        ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 5,
                            right: 10,
                          ),
                          leading: const Icon(Icons.cloud_upload_outlined),
                          title: Text(context.l10n.cloudBackupNow),
                          subtitle: authController.cloudBackupRunning
                              ? Text(context.l10n.cloudBackupInProgress)
                              : null,
                          onTap: authController.cloudBackupRunning
                              ? null
                              : () => _runCloudAudioBackup(
                                  context,
                                  authController,
                                ),
                        ),
                    ],
                  ),
                  if (settingsController.developerSettingsEnabled.value)
                    CustomExpansionTile(
                      title: context.l10n.resolverBackend,
                      icon: Icons.dns_outlined,
                      childrenBuilder: (context) => [
                        ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 5,
                            right: 10,
                          ),
                          title: Text(context.l10n.resolverBackend),
                          subtitle: Text(
                            context.l10n.resolverBackendDescription,
                          ),
                          trailing: CustomSwitch(
                            value: settingsController.resolverEnabled.value,
                            onChanged: settingsController.setResolverEnabled,
                          ),
                        ),
                        if (kDebugMode)
                          ListTile(
                            contentPadding: const EdgeInsets.only(
                              left: 5,
                              right: 10,
                            ),
                            title: Text(context.l10n.resolverPlaybackSource),
                            subtitle: Text(
                              context.l10n.resolverPlaybackSourceDescription,
                            ),
                            trailing: DropdownButton<ResolverSourceMode>(
                              dropdownColor: Theme.of(context).cardColor,
                              underline: const SizedBox.shrink(),
                              value:
                                  settingsController.resolverSourceMode.value,
                              items: [
                                DropdownMenuItem(
                                  value: ResolverSourceMode.both,
                                  child: Text(
                                    context.l10n.resolverPlaybackSourceBoth,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: ResolverSourceMode.resolverOnly,
                                  child: Text(
                                    context
                                        .l10n
                                        .resolverPlaybackSourceResolverOnly,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: ResolverSourceMode.existingOnly,
                                  child: Text(
                                    context
                                        .l10n
                                        .resolverPlaybackSourceExistingOnly,
                                  ),
                                ),
                              ],
                              onChanged:
                                  settingsController.setResolverSourceMode,
                            ),
                          ),
                        ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 5,
                            right: 10,
                          ),
                          title: Text(context.l10n.resolverTestConnection),
                          subtitle: Text(
                            settingsController
                                    .resolverEffectiveUrl
                                    .value
                                    .isEmpty
                                ? context.l10n.resolverNotConfigured
                                : settingsController.resolverEffectiveUrl.value,
                          ),
                          trailing: AwaitableIconButton(
                            icon: const Icon(Icons.network_check),
                            onPressed: () async {
                              await settingsController.testResolverConnection();
                            },
                          ),
                        ),
                        if (settingsController.resolverStatus.value ==
                                'ready' ||
                            settingsController.resolverStatus.value ==
                                'unreachable' ||
                            settingsController.resolverStatus.value ==
                                'not_ready')
                          Padding(
                            padding: const EdgeInsets.fromLTRB(5, 0, 10, 12),
                            child: Text(
                              settingsController.resolverStatus.value == 'ready'
                                  ? context.l10n.resolverReady
                                  : context.l10n.resolverUnavailable,
                            ),
                          ),
                        ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 5,
                            right: 10,
                          ),
                          title: Text(context.l10n.resolverAddress),
                          subtitle: SelectableText(
                            settingsController
                                    .resolverEffectiveUrl
                                    .value
                                    .isEmpty
                                ? context.l10n.resolverNotConfigured
                                : settingsController.resolverEffectiveUrl.value,
                          ),
                          trailing: IconButton(
                            tooltip: context.l10n.resolverAddress,
                            icon: const Icon(Icons.edit),
                            onPressed: () => _editResolverAddress(
                              context,
                              settingsController,
                            ),
                          ),
                        ),
                        ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 5,
                            right: 10,
                          ),
                          title: Text(context.l10n.resolverDiscover),
                          subtitle: Text(
                            settingsController.resolverDiscoveredUrls.isEmpty
                                ? settingsController.resolverStatus.value
                                : settingsController.resolverDiscoveredUrls
                                      .join('\n'),
                          ),
                          trailing: AwaitableIconButton(
                            icon: const Icon(Icons.radar),
                            onPressed: () async {
                              await settingsController.discoverResolvers();
                            },
                          ),
                        ),
                        ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 5,
                            right: 10,
                          ),
                          title: Text(context.l10n.resolverResetAddress),
                          trailing: IconButton(
                            icon: const Icon(Icons.restore),
                            onPressed: () =>
                                settingsController.setResolverOverride(null),
                          ),
                        ),
                      ],
                    ),
                  CustomExpansionTile(
                    title: context.l10n.personalisation,
                    icon: Icons.palette,
                    childrenBuilder: (context) => [
                      ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 5,
                          right: 10,
                        ),
                        title: Text(context.l10n.themeMode),
                        subtitle: Text(
                          settingsController.themeModeType.value ==
                                  ThemeType.dynamic
                              ? context.l10n.dynamicTheme
                              : settingsController.themeModeType.value ==
                                    ThemeType.system
                              ? context.l10n.systemDefault
                              : settingsController.themeModeType.value ==
                                    ThemeType.dark
                              ? context.l10n.dark
                              : context.l10n.light,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        onTap: () async {
                          await showDialog(
                            context: context,
                            builder: (context) => const ThemeSelectorDialog(),
                          );
                        },
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 5,
                          right: 10,
                        ),
                        title: Text(context.l10n.language),
                        subtitle: Text(
                          context.l10n.languageDes,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        trailing: DropdownButton(
                          menuMaxHeight:
                              MediaQuery.sizeOf(context).height - 250,
                          dropdownColor: Theme.of(context).cardColor,
                          underline: const SizedBox.shrink(),
                          style: Theme.of(context).textTheme.titleSmall,
                          value:
                              settingsController.currentAppLanguageCode.value,
                          items: langMap.entries
                              .map(
                                (lang) => DropdownMenuItem(
                                  value: lang.key,
                                  child: Text(lang.value),
                                ),
                              )
                              .whereType<DropdownMenuItem<String>>()
                              .toList(),
                          selectedItemBuilder: (context) =>
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
                          title: Text(context.l10n.playerUi),
                          subtitle: Text(
                            context.l10n.playerUiDes,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          trailing: DropdownButton(
                            dropdownColor: Theme.of(context).cardColor,
                            underline: const SizedBox.shrink(),
                            value: settingsController.playerUi.value,
                            items: [
                              DropdownMenuItem(
                                value: 0,
                                child: Text(context.l10n.standard),
                              ),
                              DropdownMenuItem(
                                value: 1,
                                child: Text(context.l10n.gesture),
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
                          title: Text(context.l10n.firstLibraryTab),
                          subtitle: Text(
                            context.l10n.firstLibraryTabDes,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          trailing: DropdownButton(
                            dropdownColor: Theme.of(context).cardColor,
                            underline: const SizedBox.shrink(),
                            value: settingsController.libraryFirstTab.value,
                            items: libraryTabKeys
                                .asMap()
                                .entries
                                .map(
                                  (entry) => DropdownMenuItem(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) async {
                              if (val == null) return;
                              await settingsController.setFirstLibraryTab(val);
                            },
                          ),
                        ),
                      if (!isDesktop)
                        ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 5,
                            right: 10,
                          ),
                          title: Text(context.l10n.enableBottomNav),
                          subtitle: Text(
                            context.l10n.enableBottomNavDes,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          trailing: CustomSwitch(
                            value:
                                settingsController.isBottomNavBarEnabled.value,
                            onChanged: settingsController.enableBottomNavBar,
                          ),
                        ),
                      ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 5,
                          right: 10,
                        ),
                        title: Text(context.l10n.disableTransitionAnimation),
                        subtitle: Text(
                          context.l10n.disableTransitionAnimationDes,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        trailing: CustomSwitch(
                          value: settingsController
                              .isTransitionAnimationDisabled
                              .value,
                          onChanged:
                              settingsController.disableTransitionAnimation,
                        ),
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 5,
                          right: 10,
                        ),
                        title: Text(context.l10n.enableSlidableAction),
                        subtitle: Text(
                          context.l10n.enableSlidableActionDes,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        trailing: CustomSwitch(
                          value: settingsController.slidableActionEnabled.value,
                          onChanged: settingsController.toggleSlidableAction,
                        ),
                      ),
                    ],
                  ),
                  CustomExpansionTile(
                    title: context.l10n.content,
                    icon: Icons.music_video,
                    childrenBuilder: (context) => [
                      ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 5,
                          right: 10,
                        ),
                        title: Text(context.l10n.setDiscoverContent),
                        subtitle: Text(
                          settingsController.discoverContentType.value == "QP"
                              ? context.l10n.quickpicks
                              : settingsController.discoverContentType.value ==
                                    "TMV"
                              ? context.l10n.topmusicvideos
                              : settingsController.discoverContentType.value ==
                                    "TR"
                              ? context.l10n.trending
                              : context.l10n.basedOnLast,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        onTap: () async {
                          await showDialog(
                            context: context,
                            builder: (context) =>
                                const DiscoverContentSelectorDialog(),
                          );
                        },
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 5,
                          right: 10,
                        ),
                        title: Text(context.l10n.homeContentCount),
                        subtitle: Text(
                          context.l10n.homeContentCountDes,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        trailing: DropdownButton(
                          dropdownColor: Theme.of(context).cardColor,
                          underline: const SizedBox.shrink(),
                          value: settingsController.noOfHomeScreenContent.value,
                          items: [3, 5, 7, 9, 11]
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text("$e"),
                                ),
                              )
                              .toList(),
                          onChanged: settingsController.setContentNumber,
                        ),
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 5,
                          right: 10,
                        ),
                        title: Text(context.l10n.cacheHomeScreenData),
                        subtitle: Text(
                          context.l10n.cacheHomeScreenDataDes,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        trailing: CustomSwitch(
                          value: settingsController.cacheHomeScreenData.value,
                          onChanged:
                              settingsController.toggleCacheHomeScreenData,
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
                            context.l10n.reset,
                            style: Theme.of(
                              context,
                            ).textTheme.titleMedium!.copyWith(fontSize: 15),
                          ),
                          onPressed: () async {
                            await settingsController.resetRecoverableAppState();
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
                        title: Text(context.l10n.piped),
                        subtitle: Text(
                          context.l10n.linkPipedDes,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        trailing: TextButton(
                          child: Text(
                            settingsController.isLinkedWithPiped.value
                                ? context.l10n.unLink
                                : context.l10n.link,
                            style: Theme.of(
                              context,
                            ).textTheme.titleMedium!.copyWith(fontSize: 15),
                          ),
                          onPressed: () {
                            if (!settingsController.isLinkedWithPiped.value) {
                              unawaited(
                                showDialog(
                                  context: context,
                                  builder: (context) => const LinkPiped(),
                                ),
                              );
                            } else {
                              unawaited(
                                settingsController.unlinkPiped(context),
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
                              title: Text(
                                context.l10n.resetBlacklistedPlaylist,
                              ),
                              subtitle: Text(
                                context.l10n.resetBlacklistedPlaylistDes,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              trailing: AwaitableButton.text(
                                label: Text(
                                  context.l10n.reset,
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
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    snackbar(
                                      context,
                                      context.l10n.blacklistPlaylistResetAlert,
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
                        title: Text(context.l10n.clearImgCache),
                        subtitle: Text(
                          context.l10n.clearImgCacheDes,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        isThreeLine: true,
                        onTap: () {
                          unawaited(
                            settingsController.clearImagesCache().then((value) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                snackbar(
                                  context,
                                  context.l10n.clearImgCacheAlert,
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
                    title: context.l10n.musicAndPlayback,
                    icon: Icons.music_note,
                    childrenBuilder: (context) => [
                      ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 5,
                          right: 10,
                        ),
                        title: Text(context.l10n.streamingQuality),
                        subtitle: Text(
                          context.l10n.streamingQualityDes,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        trailing: DropdownButton(
                          dropdownColor: Theme.of(context).cardColor,
                          underline: const SizedBox.shrink(),
                          value: settingsController.streamingQuality.value,
                          items: [
                            DropdownMenuItem(
                              value: AudioQuality.Low,
                              child: Text(context.l10n.low),
                            ),
                            DropdownMenuItem(
                              value: AudioQuality.High,
                              child: Text(context.l10n.high),
                            ),
                          ],
                          onChanged: settingsController.setStreamingQuality,
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
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          trailing: DropdownButton<PlaybackMode>(
                            dropdownColor: Theme.of(context).cardColor,
                            underline: const SizedBox.shrink(),
                            value: settingsController.playbackMode.value,
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
                            onChanged: settingsController.setPlaybackMode,
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
                                title: const Text("Playback preload range"),
                                subtitle: Text(
                                  "Higher values prepare nearby songs while playback is active.",
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                trailing: DropdownButton<int>(
                                  dropdownColor: Theme.of(context).cardColor,
                                  underline: const SizedBox.shrink(),
                                  value: settingsController
                                      .playbackPreloadRange
                                      .value,
                                  items: List.generate(5, (index) {
                                    final range = index + 1;
                                    return DropdownMenuItem<int>(
                                      value: range,
                                      child: Text("$range"),
                                    );
                                  }),
                                  onChanged: settingsController
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
                          title: Text(context.l10n.loudnessNormalization),
                          subtitle: Text(
                            context.l10n.loudnessNormalizationDes,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          trailing: CustomSwitch(
                            value: settingsController
                                .loudnessNormalizationEnabled
                                .value,
                            onChanged:
                                settingsController.toggleLoudnessNormalization,
                          ),
                        ),
                      if (!isDesktop)
                        ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 5,
                            right: 10,
                          ),
                          title: Text(context.l10n.cacheSongs),
                          subtitle: Text(
                            context.l10n.cacheSongsDes,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          trailing: CustomSwitch(
                            value: settingsController.cacheSongs.value,
                            onChanged:
                                settingsController.toggleCachingSongsValue,
                          ),
                        ),
                      if (!isDesktop)
                        ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 5,
                            right: 10,
                          ),
                          title: Text(context.l10n.skipSilence),
                          subtitle: Text(
                            context.l10n.skipSilenceDes,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          trailing: CustomSwitch(
                            value: settingsController.skipSilenceEnabled.value,
                            onChanged: settingsController.toggleSkipSilence,
                          ),
                        ),
                      if (isDesktop)
                        ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 5,
                            right: 10,
                          ),
                          title: Text(context.l10n.backgroundPlay),
                          subtitle: Text(
                            context.l10n.backgroundPlayDes,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          trailing: CustomSwitch(
                            value:
                                settingsController.backgroundPlayEnabled.value,
                            onChanged: settingsController.toggleBackgroundPlay,
                          ),
                        ),
                      ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 5,
                          right: 10,
                        ),
                        title: Text(context.l10n.keepScreenOnWhilePlaying),
                        subtitle: Text(
                          context.l10n.keepScreenOnWhilePlayingDes,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        trailing: CustomSwitch(
                          value: settingsController.keepScreenAwake.value,
                          onChanged: settingsController.toggleKeepScreenAwake,
                        ),
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 5,
                          right: 10,
                        ),
                        title: Text(context.l10n.restoreLastPlaybackSession),
                        subtitle: Text(
                          context.l10n.restoreLastPlaybackSessionDes,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        trailing: CustomSwitch(
                          value:
                              settingsController.restorePlaybackSession.value,
                          onChanged:
                              settingsController.toggleRestorePlaybackSession,
                        ),
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 5,
                          right: 10,
                        ),
                        title: Text(context.l10n.autoOpenPlayer),
                        subtitle: Text(
                          context.l10n.autoOpenPlayerDes,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        trailing: CustomSwitch(
                          value: settingsController.autoOpenPlayer.value,
                          onChanged: settingsController.toggleAutoOpenPlayer,
                        ),
                      ),
                      if (!isDesktop)
                        ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 5,
                            right: 10,
                            top: 0,
                          ),
                          title: Text(context.l10n.equalizer),
                          subtitle: Text(
                            context.l10n.equalizerDes,
                            style: Theme.of(context).textTheme.bodyMedium,
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
                          title: Text(context.l10n.stopMusicOnTaskClear),
                          subtitle: Text(
                            context.l10n.stopMusicOnTaskClearDes,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          trailing: CustomSwitch(
                            value: settingsController
                                .stopPlaybackOnSwipeAway
                                .value,
                            onChanged: settingsController
                                .toggleStopPlaybackOnSwipeAway,
                          ),
                        ),
                      if (RuntimePlatform.isAndroid)
                        ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 5,
                            right: 10,
                          ),
                          title: Text(context.l10n.ignoreBatOpt),
                          onTap: settingsController
                              .openBatteryOptimizationSettings,
                          subtitle: RichText(
                            text: TextSpan(
                              text:
                                  "${context.l10n.status}: ${settingsController.isIgnoringBatteryOptimizations.value ? context.l10n.enabled : context.l10n.disabled}\n",
                              style: Theme.of(context).textTheme.bodyMedium!
                                  .copyWith(fontWeight: FontWeight.bold),
                              children: <TextSpan>[
                                TextSpan(
                                  text: context.l10n.ignoreBatOptDes,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  CustomExpansionTile(
                    title: context.l10n.download,
                    icon: Icons.download,
                    childrenBuilder: (context) => [
                      ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 5,
                          right: 10,
                        ),
                        title: Text(context.l10n.autoDownFavSong),
                        subtitle: Text(
                          context.l10n.autoDownFavSongDes,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        trailing: CustomSwitch(
                          value: settingsController
                              .autoDownloadFavoriteSongEnabled
                              .value,
                          onChanged:
                              settingsController.toggleAutoDownloadFavoriteSong,
                        ),
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 5,
                          right: 10,
                        ),
                        title: Text(context.l10n.downloadingFormat),
                        subtitle: Text(
                          context.l10n.downloadingFormatDes,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        trailing: DropdownButton(
                          dropdownColor: Theme.of(context).cardColor,
                          underline: const SizedBox.shrink(),
                          value: settingsController.downloadingFormat.value,
                          items: const [
                            DropdownMenuItem(
                              value: "opus",
                              child: Text("Opus/Ogg"),
                            ),
                            DropdownMenuItem(value: "m4a", child: Text("M4a")),
                          ],
                          onChanged: settingsController.changeDownloadingFormat,
                        ),
                      ),
                      ListTile(
                        trailing: AwaitableButton.text(
                          label: Text(
                            context.l10n.reset,
                            style: Theme.of(
                              context,
                            ).textTheme.titleMedium!.copyWith(fontSize: 15),
                          ),
                          onPressed: () async {
                            await settingsController.resetDownloadLocation();
                          },
                        ),
                        contentPadding: const EdgeInsets.only(
                          left: 5,
                          right: 10,
                          top: 0,
                        ),
                        title: Text(context.l10n.downloadLocation),
                        subtitle: Text(
                          settingsController.isCurrentPathSupportDownloadDir
                              ? "In App storage directory"
                              : settingsController.downloadLocationPath.value,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        onTap: () async {
                          unawaited(settingsController.setDownloadLocation());
                        },
                      ),
                      if (RuntimePlatform.isAndroid)
                        ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 5,
                            right: 10,
                          ),
                          title: Text(context.l10n.exportDownloadedFiles),
                          subtitle: Text(
                            context.l10n.exportDownloadedFilesDes,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          isThreeLine: true,
                          onTap: () async {
                            await showDialog(
                              context: context,
                              builder: (context) => const ExportFileDialog(),
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
                          title: Text(context.l10n.exportedFileLocation),
                          subtitle: Text(
                            settingsController.exportLocationPath.value,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          onTap: () async {
                            unawaited(settingsController.setExportedLocation());
                          },
                        ),
                    ],
                  ),
                  CustomExpansionTile(
                    title: "${context.l10n.backup} & ${context.l10n.restore}",
                    icon: Icons.restore,
                    childrenBuilder: (context) => [
                      ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 5,
                          right: 10,
                        ),
                        title: Text(context.l10n.backupAppData),
                        subtitle: Text(
                          context.l10n.backupSettingsAndPlaylistsDes,
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
                        title: Text(context.l10n.restoreAppData),
                        subtitle: Text(
                          context.l10n.restoreSettingsAndPlaylistsDes,
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
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          isThreeLine: true,
                          onTap: settingsController.exportDeveloperClonePackage,
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
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          isThreeLine: true,
                          onTap: settingsController.importDeveloperClonePackage,
                        ),
                    ],
                  ),
                  CustomExpansionTile(
                    title: "Import",
                    icon: Icons.playlist_add,
                    childrenBuilder: (context) => [
                      ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 5,
                          right: 10,
                        ),
                        title: const Text("Import YouTube Music playlist"),
                        subtitle: Text(
                          "Creates a local playlist from a public YouTube Music or YouTube playlist URL.",
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        isThreeLine: true,
                        onTap: () async {
                          await showDialog(
                            context: context,
                            builder: (context) =>
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
                            builder: (context) =>
                                const ImportSpotifyPlaylistDialog(),
                          );
                        },
                      ),
                    ],
                  ),
                  CustomExpansionTile(
                    icon: Icons.miscellaneous_services,
                    title: context.l10n.misc,
                    childrenBuilder: (context) => [
                      ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 5,
                          right: 10,
                        ),
                        title: Text(context.l10n.resetToDefault),
                        subtitle: Text(
                          context.l10n.resetToDefaultDes,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        onTap: () {
                          unawaited(
                            settingsController.resetAppSettingsToDefault().then(
                              (_) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  snackbar(
                                    context,
                                    context.l10n.resetToDefaultMsg,
                                    size: SanckBarSize.BIG,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  CustomExpansionTile(
                    icon: Icons.info,
                    title: context.l10n.appInfo,
                    initiallyExpanded: revealUpdateSection,
                    childrenBuilder: (context) => [
                      ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 5,
                          right: 10,
                        ),
                        title: Text(context.l10n.github),
                        subtitle: Text(
                          "${context.l10n.githubDes}${((playerController.playerPanelMinHeight.value) == 0 || !isBottomNavActive) ? "" : "\n\n${settingsController.currentVersion} ${context.l10n.by} bozmund"}",
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
                      if (RuntimePlatform.isAndroid)
                        ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 5,
                            right: 10,
                          ),
                          leading: const Icon(Icons.share_outlined),
                          title: Text(context.l10n.shareAndroidApp),
                          subtitle: Text(
                            context.l10n.shareAndroidAppDescription,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          onTap: () => unawaited(
                            AppPlatformService.shareText(_latestAndroidApkUrl),
                          ),
                        ),
                      ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 5,
                          right: 10,
                        ),
                        title: Text(context.l10n.checkUpdate),
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
                          value: settingsController.updateChannel.value.name,
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
                          onChanged: settingsController.changeUpdateChannel,
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
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            Text(
                              settingsController.currentVersion,
                              style: Theme.of(context).textTheme.titleMedium,
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
                "${settingsController.currentVersion} ${context.l10n.by} bozmund",
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
      childrenBuilder: (context) => [
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
          builder: (context, _) => Column(
            children: settingsController.developerSettingValues
                .map(
                  (entry) => ListTile(
                    contentPadding: const EdgeInsets.only(left: 5, right: 10),
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

Future<void> _showCloudOptInDialog(
  BuildContext context,
  AuthController controller,
) async {
  if (_cloudOptInDialogOpen || !controller.needsCloudOptIn) return;
  _cloudOptInDialogOpen = true;
  try {
    final enabled = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.cloudBackup),
        content: Text(dialogContext.l10n.cloudBackupPrompt),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.cloudBackupNotNow),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.cloudBackupEnable),
          ),
        ],
      ),
    );
    if (enabled != null) await controller.setCloudSyncEnabled(enabled);
  } finally {
    _cloudOptInDialogOpen = false;
  }
}

Future<void> _runCloudAudioBackup(
  BuildContext context,
  AuthController controller, {
  bool overrideBatteryPolicy = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final result = await controller.backupCloudAudioNow(
      overrideBatteryPolicy: overrideBatteryPolicy,
    );
    if (!context.mounted) return;
    if (result == CloudAudioBackupResult.batteryTooLow) {
      final continueBackup = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(dialogContext.l10n.cloudBackupLowBatteryTitle),
          content: Text(dialogContext.l10n.cloudBackupLowBatteryMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(dialogContext.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(dialogContext.l10n.cloudBackupAnyway),
            ),
          ],
        ),
      );
      if (continueBackup == true && context.mounted) {
        await _runCloudAudioBackup(
          context,
          controller,
          overrideBatteryPolicy: true,
        );
      }
      return;
    }
    final message = switch (result) {
      CloudAudioBackupResult.completed => context.l10n.cloudBackupComplete,
      CloudAudioBackupResult.wifiRequired =>
        context.l10n.cloudBackupWifiRequired,
      CloudAudioBackupResult.alreadyRunning =>
        context.l10n.cloudBackupInProgress,
      CloudAudioBackupResult.disabled => context.l10n.cloudBackupFailed,
      CloudAudioBackupResult.batteryTooLow => context.l10n.cloudBackupFailed,
    };
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        snackbar(context, message, duration: const Duration(seconds: 3)),
      );
  } catch (_) {
    if (!context.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        snackbar(
          context,
          context.l10n.cloudBackupFailed,
          duration: const Duration(seconds: 3),
        ),
      );
  }
}

Future<void> _editResolverAddress(
  BuildContext context,
  SettingsScreenController controller,
) async {
  final textController = TextEditingController(
    text: controller.resolverEffectiveUrl.value,
  );
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.resolverAddress),
      content: TextField(
        controller: textController,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: const InputDecoration(hintText: 'http://192.168.1.10:8088'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, textController.text),
          child: Text(context.l10n.resolverSaveAddress),
        ),
      ],
    ),
  );
  textController.dispose();
  if (value != null) await controller.setResolverOverride(value);
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
                  context.l10n.themeMode,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            radioWidget(
              context: context,
              label: context.l10n.dynamicTheme,
              controller: settingsController,
              value: ThemeType.dynamic,
            ),
            radioWidget(
              context: context,
              label: context.l10n.systemDefault,
              controller: settingsController,
              value: ThemeType.system,
            ),
            radioWidget(
              context: context,
              label: context.l10n.dark,
              controller: settingsController,
              value: ThemeType.dark,
            ),
            radioWidget(
              context: context,
              label: context.l10n.light,
              controller: settingsController,
              value: ThemeType.light,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(context.l10n.cancel),
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
                  context.l10n.setDiscoverContent,
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
                      label: context.l10n.quickpicks,
                      controller: settingsController,
                      value: "QP",
                    ),
                    radioWidget(
                      context: context,
                      label: context.l10n.topmusicvideos,
                      controller: settingsController,
                      value: "TMV",
                    ),
                    radioWidget(
                      context: context,
                      label: context.l10n.trending,
                      controller: settingsController,
                      value: "TR",
                    ),
                    radioWidget(
                      context: context,
                      label: context.l10n.basedOnLast,
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
                  child: Text(context.l10n.cancel),
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
    builder: (context, _) => ListTile(
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
        groupValue: value.runtimeType == ThemeType
            ? controller.themeModeType.value
            : controller.discoverContentType.value,
        onChanged: value.runtimeType == ThemeType
            ? controller.onThemeChange
            : controller.onContentChange,
      ),
      title: Text(label),
    ),
  );
}
