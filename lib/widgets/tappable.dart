import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Whether a tappable's remote-focused or mouse-hovered highlight should show. The two look
/// the same everywhere in this app, so widgets don't need to care which one it was.
bool isHighlighted(Set<WidgetState> states) =>
    states.contains(WidgetState.focused) || states.contains(WidgetState.hovered);

/// Something you can tap, click, or select with a remote (Enter, Select, Space), that draws
/// itself from its current [WidgetState]s: for the app's own cards and tiles, where a Material
/// button's look doesn't fit.
///
/// [WidgetState.focused] is only set while focus should show (a keyboard or remote is in use),
/// not after a tap. Without [onPress] it's disabled and can't take focus.
///
/// [onLongPress]: holding Select (or Enter or Space), a long press, or a right-click. Then a
/// quick press of Select only acts as it lets go, so a hold can be told apart from it.
class Tappable extends StatefulWidget {
  const Tappable({
    super.key,
    this.focusNode,
    this.autofocus = false,
    required this.onPress,
    this.onLongPress,
    this.semanticsLabel,
    this.builder,
    this.child,
  }) : assert(builder != null || child != null);

  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onPress;
  final VoidCallback? onLongPress;
  final String? semanticsLabel;

  /// How long Select is held for [onLongPress].
  static const holdFor = Duration(milliseconds: 500);

  /// Draws it from its states. [child] is passed through, for the parts that never change.
  final Widget Function(BuildContext context, Set<WidgetState> states, Widget? child)? builder;
  final Widget? child;

  @override
  State<Tappable> createState() => _TappableState();
}

class _TappableState extends State<Tappable> {
  bool _focused = false;
  bool _hovered = false;
  bool _pressed = false;

  /// Running while Select is held, until it counts as a hold.
  Timer? _hold;

  static final _selectKeys = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.gameButtonA,
  };

  /// With [Tappable.onLongPress], Select is watched here, before it can activate on the way
  /// down: a press acts as it comes up, a hold once it's been down for [Tappable.holdFor].
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final onPress = widget.onPress, onLongPress = widget.onLongPress;
    if (onPress == null || onLongPress == null || !_selectKeys.contains(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    switch (event) {
      case KeyDownEvent():
        _hold?.cancel();
        _setPressed(true);
        _hold = Timer(Tappable.holdFor, () {
          _setPressed(false);
          onLongPress();
        });
      case KeyUpEvent():
        // Up without a down here (it went down somewhere else, e.g. in a menu that just
        // closed): nothing to do.
        if (_hold?.isActive ?? false) {
          _hold!.cancel();
          _setPressed(false);
          onPress();
        }
        _hold = null;
      case KeyRepeatEvent():
        // Held long enough for the system to repeat it (Android's long press): a hold.
        if (_hold?.isActive ?? false) {
          _hold!.cancel();
          _setPressed(false);
          onLongPress();
        }
      default:
    }
    return KeyEventResult.handled;
  }

  /// The node it focuses with: the one passed in, or its own, which watches for a hold. (A node
  /// passed in is left alone, so holding Select there just presses.)
  late final FocusNode _ownNode = FocusNode(onKeyEvent: _onKey);
  FocusNode get _node => widget.focusNode ?? _ownNode;

  @override
  void dispose() {
    _hold?.cancel();
    _ownNode.dispose();
    super.dispose();
  }

  late final _actions = <Type, Action<Intent>>{
    ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPress?.call()),
    ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => widget.onPress?.call()),
  };

  void _setPressed(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPress != null;
    final states = <WidgetState>{
      if (_focused && enabled) WidgetState.focused,
      if (_hovered && enabled) WidgetState.hovered,
      if (_pressed && enabled) WidgetState.pressed,
      if (!enabled) WidgetState.disabled,
    };
    return FocusableActionDetector(
      focusNode: _node,
      autofocus: widget.autofocus,
      enabled: enabled,
      actions: _actions,
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.semanticsLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPress,
          onTapDown: enabled ? (_) => _setPressed(true) : null,
          onTapUp: enabled ? (_) => _setPressed(false) : null,
          onTapCancel: enabled ? () => _setPressed(false) : null,
          onLongPress: enabled ? widget.onLongPress : null,
          onSecondaryTap: enabled ? widget.onLongPress : null,
          child: widget.builder?.call(context, states, widget.child) ?? widget.child,
        ),
      ),
    );
  }
}
