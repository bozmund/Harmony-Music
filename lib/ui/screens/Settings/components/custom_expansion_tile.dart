import 'dart:async';

import 'package:flutter/material.dart';

class CustomExpansionTile extends StatefulWidget {
  final String title;
  final IconData icon;
  final List<Widget>? children;
  final List<Widget> Function(BuildContext context)? childrenBuilder;

  /// When true the tile mounts expanded and scrolls itself into view —
  /// used to reveal a specific settings section when navigating here from
  /// elsewhere (e.g. the release prompt's channel choice).
  final bool initiallyExpanded;

  const CustomExpansionTile({
    super.key,
    this.children,
    this.childrenBuilder,
    required this.icon,
    required this.title,
    this.initiallyExpanded = false,
  }) : assert(
         children != null || childrenBuilder != null,
         'Either children or childrenBuilder must be provided.',
       );

  @override
  State<CustomExpansionTile> createState() => _CustomExpansionTileState();
}

class _CustomExpansionTileState extends State<CustomExpansionTile> {
  late bool _childrenMounted;

  @override
  void initState() {
    super.initState();
    _childrenMounted = widget.initiallyExpanded;
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

  void _handleExpansionChanged(bool expanded) {
    if (expanded && !_childrenMounted) {
      setState(() {
        _childrenMounted = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = _childrenMounted
        ? widget.children ?? widget.childrenBuilder!(context)
        : const <Widget>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: widget.initiallyExpanded,
        onExpansionChanged: _handleExpansionChanged,
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
        children: children,
      ),
    );
  }
}
