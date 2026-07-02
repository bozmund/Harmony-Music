import 'dart:async';

import 'package:flutter/material.dart';

class CustomExpansionTile extends StatefulWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  /// When true the tile mounts expanded and scrolls itself into view —
  /// used to reveal a specific settings section when navigating here from
  /// elsewhere (e.g. the release prompt's channel choice).
  final bool initiallyExpanded;

  const CustomExpansionTile({
    super.key,
    required this.children,
    required this.icon,
    required this.title,
    this.initiallyExpanded = false,
  });

  @override
  State<CustomExpansionTile> createState() => _CustomExpansionTileState();
}

class _CustomExpansionTileState extends State<CustomExpansionTile> {
  @override
  void initState() {
    super.initState();
    if (widget.initiallyExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: widget.initiallyExpanded,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        childrenPadding: const EdgeInsets.all(8),
        tilePadding: const EdgeInsets.only(right: 16, left: 10),
        textColor: Theme.of(context).textTheme.titleMedium!.color,
        iconColor: Theme.of(context).textTheme.titleMedium!.color,
        collapsedBackgroundColor: Theme.of(
          context,
        ).colorScheme.secondary.withAlpha(30),
        backgroundColor: Theme.of(context).colorScheme.secondary.withAlpha(30),
        title: Text(widget.title),
        leading: Icon(widget.icon),
        children: widget.children,
      ),
    );
  }
}
