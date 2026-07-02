import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/utils/get_localization.dart';

import '../../app/providers/controller_providers.dart';
import '/ui/player/player_controller.dart';
import 'snackbar.dart';

class SleepTimerBottomSheet extends ConsumerWidget {
  const SleepTimerBottomSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerController = ref.read(playerControllerProvider);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: AnimatedBuilder(
        animation: Listenable.merge([
          playerController.isSleepTimerActive,
          playerController.isSleepEndOfSongActive,
          playerController.timerDurationLeft,
        ]),
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.timer),
              title: Text("sleepTimer".tr),
            ),
            const Divider(),
            if (playerController.isSleepTimerActive.value)
              SizedBox(
                height: 90,
                child: Container(
                  width: 180,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Align(
                    alignment: Alignment.center,
                    child: Builder(
                      builder: (context) {
                        final leftDurationInSec =
                            playerController.timerDurationLeft.value;
                        final hrs = (leftDurationInSec ~/ 3600)
                            .toString()
                            .padLeft(2, '0');
                        final min = ((leftDurationInSec % 3600) ~/ 60)
                            .toString()
                            .padLeft(2, '0');
                        final sec = ((leftDurationInSec % 3600) % 60)
                            .toString()
                            .padLeft(2, '0');

                        return Text(
                          "$hrs:$min:$sec",
                          style: Theme.of(
                            context,
                          ).textTheme.titleLarge!.copyWith(fontSize: 35),
                        );
                      },
                    ),
                  ),
                ),
              ),
            if (!playerController.isSleepTimerActive.value)
              Column(children: getTimeListWidget(context, playerController)),
            if (playerController.isSleepTimerActive.value)
              Padding(
                padding: const EdgeInsets.only(bottom: 20.0, top: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (!playerController.isSleepEndOfSongActive.value)
                      OutlinedButton(
                        onPressed: playerController.addFiveMinutes,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(
                            context,
                          ).textTheme.titleMedium!.color!,
                          side: BorderSide(
                            color: Theme.of(
                              context,
                            ).textTheme.titleMedium!.color!,
                          ),
                        ),
                        child: Text("add5Minutes".tr),
                      ),
                    OutlinedButton(
                      onPressed: () {
                        Future.delayed(
                          const Duration(milliseconds: 200),
                          playerController.cancelSleepTimer,
                        );
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          snackbar(
                            context,
                            "cancelTimerAlert".tr,
                            size: SanckBarSize.BIG,
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(
                          context,
                        ).textTheme.titleMedium!.color!,
                        side: BorderSide(
                          color: Theme.of(
                            context,
                          ).textTheme.titleMedium!.color!,
                        ),
                      ),
                      child: Text("cancelTimer".tr),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> getTimeListWidget(
    BuildContext context,
    PlayerController playerController,
  ) {
    final List<Widget> widgets = [];
    widgets.addAll(
      [5, 10, 15, 30, 45, 60]
          .map(
            (dur) => ListTile(
              onTap: () {
                Navigator.of(context).pop();
                Future.delayed(const Duration(milliseconds: 200), () {
                  playerController.startSleepTimer(dur);
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  snackbar(
                    context,
                    "sleepTimeSetAlert".tr,
                    size: SanckBarSize.BIG,
                  ),
                );
              },
              leading: Padding(
                padding: const EdgeInsets.only(left: 10.0),
                child: Text(
                  "$dur ${'minutes'.tr}",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          )
          .toList(),
    );
    widgets.add(
      ListTile(
        onTap: () {
          Navigator.of(context).pop();
          playerController.sleepEndOfSong();
        },
        leading: Padding(
          padding: const EdgeInsets.only(left: 10.0),
          child: Text(
            "endOfThisSong".tr,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    );
    return widgets;
  }
}
