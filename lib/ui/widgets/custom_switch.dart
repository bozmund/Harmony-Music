import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/controller_providers.dart';

class CustomSwitch extends ConsumerWidget {
  const CustomSwitch({super.key, this.onChanged, required this.value});
  final void Function(bool)? onChanged;
  final bool value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeController = ref.watch(themeControllerProvider);
    final isLightMode =
        themeController.themeData.value!.primaryColor == Colors.white;
    return Switch(
      activeThumbColor: Colors.white,
      activeTrackColor: isLightMode ? Colors.grey : null,
      inactiveTrackColor: isLightMode ? Colors.grey : null,
      inactiveThumbColor: isLightMode
          ? Colors.grey[300]
          : Colors.white.withValues(alpha: 0.5),
      value: value,
      onChanged: onChanged,
    );
  }
}
