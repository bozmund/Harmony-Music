// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

typedef AwaitableCallback = Future<void> Function();

enum _AwaitableButtonVariant { elevated, filled, filledTonal, outlined, text }

enum _AwaitableIconButtonVariant { standard, filled, filledTonal, outlined }

class AwaitableButton extends StatefulWidget {
  const AwaitableButton.elevated({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.style,
    this.focusNode,
    this.autofocus = false,
    this.clipBehavior = Clip.none,
    this.statesController,
    this.iconAlignment,
    this.loadingIndicator,
    this.loadingIndicatorSize = 18,
    this.loadingStrokeWidth = 2,
  }) : _variant = _AwaitableButtonVariant.elevated;

  const AwaitableButton.filled({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.style,
    this.focusNode,
    this.autofocus = false,
    this.clipBehavior = Clip.none,
    this.statesController,
    this.iconAlignment,
    this.loadingIndicator,
    this.loadingIndicatorSize = 18,
    this.loadingStrokeWidth = 2,
  }) : _variant = _AwaitableButtonVariant.filled;

  const AwaitableButton.filledTonal({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.style,
    this.focusNode,
    this.autofocus = false,
    this.clipBehavior = Clip.none,
    this.statesController,
    this.iconAlignment,
    this.loadingIndicator,
    this.loadingIndicatorSize = 18,
    this.loadingStrokeWidth = 2,
  }) : _variant = _AwaitableButtonVariant.filledTonal;

  const AwaitableButton.outlined({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.style,
    this.focusNode,
    this.autofocus = false,
    this.clipBehavior = Clip.none,
    this.statesController,
    this.iconAlignment,
    this.loadingIndicator,
    this.loadingIndicatorSize = 18,
    this.loadingStrokeWidth = 2,
  }) : _variant = _AwaitableButtonVariant.outlined;

  const AwaitableButton.text({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.style,
    this.focusNode,
    this.autofocus = false,
    this.clipBehavior = Clip.none,
    this.statesController,
    this.iconAlignment,
    this.loadingIndicator,
    this.loadingIndicatorSize = 18,
    this.loadingStrokeWidth = 2,
  }) : _variant = _AwaitableButtonVariant.text;

  final Widget label;
  final Widget? icon;
  final AwaitableCallback? onPressed;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onHover;
  final ValueChanged<bool>? onFocusChange;
  final ButtonStyle? style;
  final FocusNode? focusNode;
  final bool autofocus;
  final Clip clipBehavior;
  final MaterialStatesController? statesController;
  final IconAlignment? iconAlignment;
  final Widget? loadingIndicator;
  final double loadingIndicatorSize;
  final double loadingStrokeWidth;
  final _AwaitableButtonVariant _variant;

  @override
  State<AwaitableButton> createState() => _AwaitableButtonState();
}

class _AwaitableButtonState extends State<AwaitableButton> {
  bool _isRunning = false;

  Future<void> _handlePressed() async {
    final onPressed = widget.onPressed;
    if (_isRunning || onPressed == null) return;
    setState(() => _isRunning = true);
    try {
      await onPressed();
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onPressed =
        widget.onPressed == null || _isRunning ? null : _handlePressed;
    final onLongPress = _isRunning ? null : widget.onLongPress;
    final icon = _isRunning ? _indicator() : widget.icon;
    final label =
        widget.icon == null && _isRunning
            ? _labelSizedIndicator()
            : widget.label;

    switch (widget._variant) {
      case _AwaitableButtonVariant.elevated:
        return ElevatedButton.icon(
          onPressed: onPressed,
          onLongPress: onLongPress,
          onHover: widget.onHover,
          onFocusChange: widget.onFocusChange,
          style: widget.style,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          clipBehavior: widget.clipBehavior,
          statesController: widget.statesController,
          icon: icon,
          label: label,
          iconAlignment: widget.iconAlignment,
        );
      case _AwaitableButtonVariant.filled:
        return FilledButton.icon(
          onPressed: onPressed,
          onLongPress: onLongPress,
          onHover: widget.onHover,
          onFocusChange: widget.onFocusChange,
          style: widget.style,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          clipBehavior: widget.clipBehavior,
          statesController: widget.statesController,
          icon: icon,
          label: label,
          iconAlignment: widget.iconAlignment,
        );
      case _AwaitableButtonVariant.filledTonal:
        return FilledButton.tonalIcon(
          onPressed: onPressed,
          onLongPress: onLongPress,
          onHover: widget.onHover,
          onFocusChange: widget.onFocusChange,
          style: widget.style,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          clipBehavior: widget.clipBehavior,
          statesController: widget.statesController,
          icon: icon,
          label: label,
          iconAlignment: widget.iconAlignment,
        );
      case _AwaitableButtonVariant.outlined:
        return OutlinedButton.icon(
          onPressed: onPressed,
          onLongPress: onLongPress,
          onHover: widget.onHover,
          onFocusChange: widget.onFocusChange,
          style: widget.style,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          clipBehavior: widget.clipBehavior,
          statesController: widget.statesController,
          icon: icon,
          label: label,
          iconAlignment: widget.iconAlignment,
        );
      case _AwaitableButtonVariant.text:
        return TextButton.icon(
          onPressed: onPressed,
          onLongPress: onLongPress,
          onHover: widget.onHover,
          onFocusChange: widget.onFocusChange,
          style: widget.style,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          clipBehavior: widget.clipBehavior,
          statesController: widget.statesController,
          icon: icon,
          label: label,
          iconAlignment: widget.iconAlignment,
        );
    }
  }

  Widget _labelSizedIndicator() {
    return Stack(
      alignment: Alignment.center,
      children: [Opacity(opacity: 0, child: widget.label), _indicator()],
    );
  }

  Widget _indicator() {
    return widget.loadingIndicator ??
        SizedBox.square(
          dimension: widget.loadingIndicatorSize,
          child: CircularProgressIndicator(
            strokeWidth: widget.loadingStrokeWidth,
          ),
        );
  }
}

class AwaitableIconButton extends StatefulWidget {
  const AwaitableIconButton({
    super.key,
    this.iconSize,
    this.visualDensity,
    this.padding,
    this.alignment,
    this.splashRadius,
    this.color,
    this.focusColor,
    this.hoverColor,
    this.highlightColor,
    this.splashColor,
    this.disabledColor,
    this.onPressed,
    this.onHover,
    this.onLongPress,
    this.mouseCursor,
    this.focusNode,
    this.autofocus = false,
    this.tooltip,
    this.enableFeedback,
    this.constraints,
    this.style,
    this.isSelected,
    this.selectedIcon,
    required this.icon,
    this.loadingIndicator,
    this.loadingIndicatorSize = 18,
    this.loadingStrokeWidth = 2,
  }) : _variant = _AwaitableIconButtonVariant.standard;

  const AwaitableIconButton.filled({
    super.key,
    this.iconSize,
    this.visualDensity,
    this.padding,
    this.alignment,
    this.splashRadius,
    this.color,
    this.focusColor,
    this.hoverColor,
    this.highlightColor,
    this.splashColor,
    this.disabledColor,
    this.onPressed,
    this.onHover,
    this.onLongPress,
    this.mouseCursor,
    this.focusNode,
    this.autofocus = false,
    this.tooltip,
    this.enableFeedback,
    this.constraints,
    this.style,
    this.isSelected,
    this.selectedIcon,
    required this.icon,
    this.loadingIndicator,
    this.loadingIndicatorSize = 18,
    this.loadingStrokeWidth = 2,
  }) : _variant = _AwaitableIconButtonVariant.filled;

  const AwaitableIconButton.filledTonal({
    super.key,
    this.iconSize,
    this.visualDensity,
    this.padding,
    this.alignment,
    this.splashRadius,
    this.color,
    this.focusColor,
    this.hoverColor,
    this.highlightColor,
    this.splashColor,
    this.disabledColor,
    this.onPressed,
    this.onHover,
    this.onLongPress,
    this.mouseCursor,
    this.focusNode,
    this.autofocus = false,
    this.tooltip,
    this.enableFeedback,
    this.constraints,
    this.style,
    this.isSelected,
    this.selectedIcon,
    required this.icon,
    this.loadingIndicator,
    this.loadingIndicatorSize = 18,
    this.loadingStrokeWidth = 2,
  }) : _variant = _AwaitableIconButtonVariant.filledTonal;

  const AwaitableIconButton.outlined({
    super.key,
    this.iconSize,
    this.visualDensity,
    this.padding,
    this.alignment,
    this.splashRadius,
    this.color,
    this.focusColor,
    this.hoverColor,
    this.highlightColor,
    this.splashColor,
    this.disabledColor,
    this.onPressed,
    this.onHover,
    this.onLongPress,
    this.mouseCursor,
    this.focusNode,
    this.autofocus = false,
    this.tooltip,
    this.enableFeedback,
    this.constraints,
    this.style,
    this.isSelected,
    this.selectedIcon,
    required this.icon,
    this.loadingIndicator,
    this.loadingIndicatorSize = 18,
    this.loadingStrokeWidth = 2,
  }) : _variant = _AwaitableIconButtonVariant.outlined;

  final double? iconSize;
  final VisualDensity? visualDensity;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry? alignment;
  final double? splashRadius;
  final Color? color;
  final Color? focusColor;
  final Color? hoverColor;
  final Color? highlightColor;
  final Color? splashColor;
  final Color? disabledColor;
  final AwaitableCallback? onPressed;
  final ValueChanged<bool>? onHover;
  final VoidCallback? onLongPress;
  final MouseCursor? mouseCursor;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? tooltip;
  final bool? enableFeedback;
  final BoxConstraints? constraints;
  final ButtonStyle? style;
  final bool? isSelected;
  final Widget? selectedIcon;
  final Widget icon;
  final Widget? loadingIndicator;
  final double loadingIndicatorSize;
  final double loadingStrokeWidth;
  final _AwaitableIconButtonVariant _variant;

  @override
  State<AwaitableIconButton> createState() => _AwaitableIconButtonState();
}

class _AwaitableIconButtonState extends State<AwaitableIconButton> {
  bool _isRunning = false;

  Future<void> _handlePressed() async {
    final onPressed = widget.onPressed;
    if (_isRunning || onPressed == null) return;
    setState(() => _isRunning = true);
    try {
      await onPressed();
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onPressed =
        widget.onPressed == null || _isRunning ? null : _handlePressed;
    final onLongPress = _isRunning ? null : widget.onLongPress;
    final icon = _isRunning ? _indicator() : widget.icon;
    final selectedIcon = _isRunning ? icon : widget.selectedIcon;

    switch (widget._variant) {
      case _AwaitableIconButtonVariant.standard:
        return IconButton(
          iconSize: widget.iconSize,
          visualDensity: widget.visualDensity,
          padding: widget.padding,
          alignment: widget.alignment,
          splashRadius: widget.splashRadius,
          color: widget.color,
          focusColor: widget.focusColor,
          hoverColor: widget.hoverColor,
          highlightColor: widget.highlightColor,
          splashColor: widget.splashColor,
          disabledColor: widget.disabledColor,
          onPressed: onPressed,
          onHover: widget.onHover,
          onLongPress: onLongPress,
          mouseCursor: widget.mouseCursor,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          tooltip: widget.tooltip,
          enableFeedback: widget.enableFeedback,
          constraints: widget.constraints,
          style: widget.style,
          isSelected: widget.isSelected,
          selectedIcon: selectedIcon,
          icon: icon,
        );
      case _AwaitableIconButtonVariant.filled:
        return IconButton.filled(
          iconSize: widget.iconSize,
          visualDensity: widget.visualDensity,
          padding: widget.padding,
          alignment: widget.alignment,
          splashRadius: widget.splashRadius,
          color: widget.color,
          focusColor: widget.focusColor,
          hoverColor: widget.hoverColor,
          highlightColor: widget.highlightColor,
          splashColor: widget.splashColor,
          disabledColor: widget.disabledColor,
          onPressed: onPressed,
          onHover: widget.onHover,
          onLongPress: onLongPress,
          mouseCursor: widget.mouseCursor,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          tooltip: widget.tooltip,
          enableFeedback: widget.enableFeedback,
          constraints: widget.constraints,
          style: widget.style,
          isSelected: widget.isSelected,
          selectedIcon: selectedIcon,
          icon: icon,
        );
      case _AwaitableIconButtonVariant.filledTonal:
        return IconButton.filledTonal(
          iconSize: widget.iconSize,
          visualDensity: widget.visualDensity,
          padding: widget.padding,
          alignment: widget.alignment,
          splashRadius: widget.splashRadius,
          color: widget.color,
          focusColor: widget.focusColor,
          hoverColor: widget.hoverColor,
          highlightColor: widget.highlightColor,
          splashColor: widget.splashColor,
          disabledColor: widget.disabledColor,
          onPressed: onPressed,
          onHover: widget.onHover,
          onLongPress: onLongPress,
          mouseCursor: widget.mouseCursor,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          tooltip: widget.tooltip,
          enableFeedback: widget.enableFeedback,
          constraints: widget.constraints,
          style: widget.style,
          isSelected: widget.isSelected,
          selectedIcon: selectedIcon,
          icon: icon,
        );
      case _AwaitableIconButtonVariant.outlined:
        return IconButton.outlined(
          iconSize: widget.iconSize,
          visualDensity: widget.visualDensity,
          padding: widget.padding,
          alignment: widget.alignment,
          splashRadius: widget.splashRadius,
          color: widget.color,
          focusColor: widget.focusColor,
          hoverColor: widget.hoverColor,
          highlightColor: widget.highlightColor,
          splashColor: widget.splashColor,
          disabledColor: widget.disabledColor,
          onPressed: onPressed,
          onHover: widget.onHover,
          onLongPress: onLongPress,
          mouseCursor: widget.mouseCursor,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          tooltip: widget.tooltip,
          enableFeedback: widget.enableFeedback,
          constraints: widget.constraints,
          style: widget.style,
          isSelected: widget.isSelected,
          selectedIcon: selectedIcon,
          icon: icon,
        );
    }
  }

  Widget _indicator() {
    return widget.loadingIndicator ??
        SizedBox.square(
          dimension: widget.iconSize ?? widget.loadingIndicatorSize,
          child: Center(
            child: SizedBox.square(
              dimension: widget.loadingIndicatorSize,
              child: CircularProgressIndicator(
                strokeWidth: widget.loadingStrokeWidth,
              ),
            ),
          ),
        );
  }
}
