import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/utils/get_localization.dart';

import '../../app/providers/controller_providers.dart';
import '../../utils/runtime_platform.dart';
import '/models/quick_picks.dart';
import 'awaitable_button.dart';
import 'image_widget.dart';
import 'song_info_bottom_sheet.dart';

class QuickPicksWidget extends ConsumerWidget {
  const QuickPicksWidget({
    super.key,
    required this.content,
    this.scrollController,
  });
  final QuickPicks content;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerController = ref.read(playerControllerProvider);
    return SizedBox(
      height: 340,
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              content.title.toLowerCase().removeAllWhitespace.tr,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Scrollbar(
              thickness: RuntimePlatform.isDesktop ? null : 0,
              controller: scrollController,
              child: GridView.builder(
                controller: scrollController,
                physics: const BouncingScrollPhysics(),
                scrollDirection: Axis.horizontal,
                itemCount: content.songList.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: .26 / 1,
                  crossAxisSpacing: 1,
                  mainAxisSpacing: 5,
                ),
                itemBuilder: (_, item) {
                  return Listener(
                    onPointerDown: (PointerDownEvent event) async {
                      if (event.buttons == kSecondaryMouseButton) {
                        //show song info bottom sheet
                        await showModalBottomSheet(
                          constraints: const BoxConstraints(maxWidth: 500),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(10.0),
                            ),
                          ),
                          isScrollControlled: true,
                          context:
                              playerController
                                  .homeScaffoldKey
                                  .currentState!
                                  .context,
                          barrierColor: Colors.transparent.withAlpha(100),
                          builder:
                              (context) =>
                                  SongInfoBottomSheet(content.songList[item]),
                        ).whenComplete(() {});
                      }
                    },
                    child: ListTile(
                      contentPadding: const EdgeInsets.only(left: 5),
                      leading: ImageWidget(
                        song: content.songList[item],
                        size: 55,
                      ),
                      title: Text(
                        content.songList[item].title,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: Text(
                        "${content.songList[item].artist}",
                        maxLines: 1,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      onTap: () async {
                        await playerController.pushSongToQueue(
                          content.songList[item],
                        );
                      },
                      onLongPress: () async {
                        await showModalBottomSheet(
                          constraints: const BoxConstraints(maxWidth: 500),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(10.0),
                            ),
                          ),
                          isScrollControlled: true,
                          context:
                              playerController
                                  .homeScaffoldKey
                                  .currentState!
                                  .context,
                          barrierColor: Colors.transparent.withAlpha(100),
                          builder:
                              (context) =>
                                  SongInfoBottomSheet(content.songList[item]),
                        ).whenComplete(() {});
                      },
                      trailing:
                          RuntimePlatform.isDesktop
                              ? AwaitableIconButton(
                                splashRadius: 20,
                                onPressed: () async {
                                  await showModalBottomSheet(
                                    constraints: const BoxConstraints(
                                      maxWidth: 500,
                                    ),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(10.0),
                                      ),
                                    ),
                                    isScrollControlled: true,
                                    context:
                                        playerController
                                            .homeScaffoldKey
                                            .currentState!
                                            .context,
                                    barrierColor: Colors.transparent.withAlpha(
                                      100,
                                    ),
                                    builder:
                                        (context) => SongInfoBottomSheet(
                                          content.songList[item],
                                        ),
                                  ).whenComplete(() {});
                                },
                                icon: const Icon(Icons.more_vert),
                              )
                              : null,
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
