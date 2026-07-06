import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/controller_providers.dart';
import '../../utils/theme_controller.dart';

class BackgroundImage extends ConsumerWidget {
  const BackgroundImage({super.key, this.cacheHeight});

  static const _defaultBackgroundCacheHeight = 360;

  final int? cacheHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerController = ref.read(playerControllerProvider);
    final settingsController = ref.read(settingsScreenControllerProvider);
    final themeController = ref.read(themeControllerProvider);
    final effectiveCacheHeight = cacheHeight ?? _defaultBackgroundCacheHeight;
    return AnimatedBuilder(
      animation: Listenable.merge([
        playerController.currentSong,
        settingsController.themeModeType,
      ]),
      builder: (context, _) {
        final currentSong = playerController.currentSong.value;
        return SizedBox.expand(
          /// if song is null then return empty container
          child: currentSong != null
              /// if song is local then return image from local file
              ? (currentSong.extras!['url'] ?? '').contains('file')
                    ? Builder(
                        builder: (context) {
                          final imgFile = File(
                            "${settingsController.supportDirPath}/thumbnails/${currentSong.id}.png",
                          );
                          return FutureBuilder(
                            future: imgFile.exists(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                      ConnectionState.done &&
                                  snapshot.hasData &&
                                  snapshot.data == true) {
                                /// if theme mode is dynamic then set the theme with image
                                if (settingsController.themeModeType.value ==
                                    ThemeType.dynamic) {
                                  unawaited(
                                    themeController.setTheme(
                                      FileImage(imgFile),
                                      currentSong.id,
                                    ),
                                  );
                                }

                                return Image.file(
                                  imgFile,
                                  cacheHeight: effectiveCacheHeight,
                                  fit: BoxFit.cover,
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          );
                        },
                      )
                    /// else return image from network
                    : CachedNetworkImage(
                        memCacheHeight: effectiveCacheHeight,
                        imageBuilder: (context, imageProvider) {
                          unawaited(
                            settingsController.themeModeType.value ==
                                    ThemeType.dynamic
                                ? Future.delayed(
                                    const Duration(milliseconds: 50),
                                    () => themeController.setTheme(
                                      imageProvider,
                                      currentSong.id,
                                    ),
                                  )
                                : null,
                          );
                          return Image(image: imageProvider, fit: BoxFit.cover);
                        },
                        imageUrl: currentSong.artUri.toString(),
                        cacheKey: "${currentSong.id}_song",
                      )
              : Container(),
        );
      },
    );
  }
}
