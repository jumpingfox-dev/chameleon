import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/platform/screen_type.dart';

/// A text field the way TV apps have them: the remote moves onto it and past it like a button,
/// without the on-screen keyboard popping up, and Select opens the keyboard to type. Elsewhere
/// it's just the field.
///
/// [builder] builds the [TextField] with the given focus node (pass it as the field's
/// `focusNode`) and, while the remote is on it but not typing, [highlighted] true, to draw it
/// as focused ([remoteFieldBorder]). Requesting another field's node, e.g. from the keyboard's
/// Next, opens that one straight away. Leave [focusNode] out to have one made.
class RemoteTextField extends StatefulWidget {
  const RemoteTextField({super.key, this.focusNode, this.autofocus = false, required this.builder});

  final FocusNode? focusNode;

  /// Starts focused: on a TV with the remote on it (the keyboard stays shut until Select),
  /// elsewhere ready to type. Use this rather than the field's own `autofocus`.
  final bool autofocus;

  final Widget Function(BuildContext context, FocusNode focusNode, bool highlighted) builder;

  @override
  State<RemoteTextField> createState() => _RemoteTextFieldState();
}

/// The border for a [RemoteTextField] the remote is on: [base] (the field's own shape, rounded
/// corners by default) drawn like a focused field's.
InputBorder remoteFieldBorder(BuildContext context, [InputBorder? base]) {
  final side = BorderSide(color: Theme.of(context).colorScheme.primary, width: 2);
  return base?.copyWith(borderSide: side) ??
      OutlineInputBorder(borderRadius: const BorderRadius.all(Radius.circular(12)), borderSide: side);
}

class _RemoteTextFieldState extends State<RemoteTextField> {
  /// What the remote lands on: the field's place in the page, standing in for it.
  late final _shell = FocusNode()..addListener(() => setState(() {}));

  FocusNode? _ownNode;
  FocusNode get _field => widget.focusNode ?? (_ownNode ??= FocusNode());

  bool _isTv = false;
  bool _started = false;

  static final _selectKeys = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  };

  @override
  void initState() {
    super.initState();
    _field.addListener(_onFieldFocus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isTv = ScreenType.of(context).isTv;
    // On a TV the remote passes over the field itself and stops on the shell instead.
    _field.skipTraversal = _isTv;
    if (!_started) {
      _started = true;
      // Elsewhere, autofocus is the field's own: ready to type (on a TV, the shell's below).
      if (widget.autofocus && !_isTv) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _field.requestFocus();
        });
      }
    }
  }

  @override
  void didUpdateWidget(RemoteTextField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownNode)?.removeListener(_onFieldFocus);
      _field
        ..addListener(_onFieldFocus)
        ..skipTraversal = _isTv;
    }
  }

  @override
  void dispose() {
    _field.removeListener(_onFieldFocus);
    _ownNode?.dispose();
    _shell.dispose();
    super.dispose();
  }

  /// Done typing (the keyboard's Done, say), with nothing else taking focus: back onto the
  /// shell, so the remote carries on from here.
  void _onFieldFocus() {
    if (!_isTv || _field.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (FocusManager.instance.primaryFocus case final FocusScopeNode _?) _shell.requestFocus();
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !_selectKeys.contains(event.logicalKey)) return KeyEventResult.ignored;
    if (_field.hasFocus) {
      // Typing in it with the keyboard put away (Back): Select brings it back.
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } else {
      _field.requestFocus(); // the keyboard opens with it
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isTv) return widget.builder(context, _field, false);
    return Focus(
      focusNode: _shell,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: widget.builder(context, _field, _shell.hasPrimaryFocus),
    );
  }
}
