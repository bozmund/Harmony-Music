import 'package:flutter/material.dart';

import 'components/player_queue_panel.dart';

class Player extends StatelessWidget {
  const Player({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: PlayerQueuePanel());
  }
}
