import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'focus_rows.dart';

/// Scrolls the page so this widget sits comfortably in view whenever keyboard or remote focus
/// arrives inside it: about a third of the way down, rather than Flutter's default of
/// scrolling just far enough to fit, which leaves it hugging the edge of the screen.
///
/// Wrap whole rows or single items, never a card inside a sideways-scrolling row: the scroll
/// applies to every scrolling area above this widget, including that row.
class ScrollIntoViewOnFocus extends StatelessWidget {
  const ScrollIntoViewOnFocus({
    super.key,
    required this.child,
    this.alignment = 0.3,
  });

  final Widget child;

  /// Where the widget's top edge lands: 0 = top of the screen, 0.5 = middle.
  final double alignment;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus:
        false, // doesn't take focus itself; only notices it arriving inside
    skipTraversal: true,
    onFocusChange: (hasFocus) {
      // Keyboard and remote only: clicking or tapping shouldn't scroll the page.
      if (!hasFocus ||
          FocusManager.instance.highlightMode != FocusHighlightMode.traditional) {
        return;
      }
      // Near the top of the page: all the way up, so nothing above it (Home's edit banner)
      // is left half-hidden.
      const duration = Duration(milliseconds: 300);
      if (scrollToStartIfFits(context, Axis.vertical, duration: duration, curve: Curves.easeOutCubic)) return;
      Scrollable.ensureVisible(
        context,
        alignment: alignment,
        duration: duration,
        curve: Curves.easeOutCubic,
      );
    },
    child: child,
  );
}

/// Keeps this widget clear of the page's top and bottom edges while keyboard or remote focus is
/// inside it: if it lands closer than [margin] (a share of the page's height) to either edge, the
/// page scrolls just enough to give it that room. Unlike [ScrollIntoViewOnFocus], it doesn't
/// move the page while the item is already comfortably in view. For grids.
class KeepClearOfEdges extends StatelessWidget {
  const KeepClearOfEdges({super.key, required this.child, this.margin = 0.12});

  final Widget child;

  /// The room to keep above and below, as a share of the page's height.
  final double margin;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false, // doesn't take focus itself; only notices it arriving inside
    skipTraversal: true,
    onFocusChange: (hasFocus) {
      if (!hasFocus || FocusManager.instance.highlightMode != FocusHighlightMode.traditional) return;
      // After the frame: Flutter's own scroll (just far enough to show it) goes first, then this.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) reveal(context, margin: margin);
      });
    },
    child: child,
  );

  /// Scrolls the page just enough to bring [context]'s widget clear of its top and bottom edges
  /// (by [margin], a share of the page's height), if it isn't already; a widget too tall for
  /// that gets its top in view instead.
  static void reveal(BuildContext context, {double margin = 0.12}) {
    final item = context.findRenderObject();
    if (item is! RenderBox || !item.attached) return;
    // The page's own scrolling: the nearest area that scrolls up and down (a grid laid out whole
    // inside a page, like a collection's titles, doesn't scroll itself).
    var scrollable = Scrollable.maybeOf(context);
    while (scrollable != null &&
        (scrollable.position.axis != Axis.vertical || scrollable.position.maxScrollExtent <= 0)) {
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
    final box = scrollable?.context.findRenderObject();
    if (scrollable == null || box is! RenderBox) return;
    final position = scrollable.position;
    final room = position.viewportDimension * margin;
    // Where it is on the page's visible part, and how far to scroll to give it the room.
    final top = item.localToGlobal(Offset.zero, ancestor: box).dy;
    final bottom = top + item.size.height;
    final double by;
    if (top < room) {
      by = top - room; // up
    } else if (bottom > position.viewportDimension - room) {
      // Down, but never so far that its top goes past the room above (a tall item).
      by = math.min(bottom - (position.viewportDimension - room), top - room);
    } else {
      return; // comfortably in view
    }
    final target = (position.pixels + by).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 0.5) return;
    position.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
  }
}

/// Makes a long block of content (like an expanded description) readable with a keyboard or remote.
/// While it has focus, ↓/↑ scroll the page through it. At its end, ↓ calls [onEnd] (e.g. to focus
/// a link inside it), or else lets focus move on as usual.
class KeyboardReadable extends StatefulWidget {
  const KeyboardReadable({
    super.key,
    required this.child,
    required this.enabled,
    this.focusNode,
    this.onEnd,
  });

  final Widget child;

  /// When false, it can't be focused and is skipped entirely (e.g. while collapsed).
  final bool enabled;
  final FocusNode? focusNode;

  /// Called when ↓ is pressed with the end of the content already shown.
  final VoidCallback? onEnd;

  @override
  State<KeyboardReadable> createState() => _KeyboardReadableState();
}

class _KeyboardReadableState extends State<KeyboardReadable> {
  static const _step = 120.0; // how far each ↓/↑ scrolls
  static const _margin =
      48.0; // treat content this close to the edge as fully shown

  late final FocusNode _node = widget.focusNode ?? FocusNode();

  bool get _keyboard =>
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  @override
  void dispose() {
    if (widget.focusNode == null) _node.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final down = event.logicalKey == LogicalKeyboardKey.arrowDown;
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!down && !up) return KeyEventResult.ignored;

    // Focus is on something inside (like the "Show less" link): ↑ goes back to reading,
    // ↓ moves on normally.
    if (!node.hasPrimaryFocus) {
      if (up && widget.enabled) {
        node.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final scrollable = Scrollable.maybeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    final viewport = scrollable?.context.findRenderObject() as RenderBox?;
    if (scrollable == null || box == null || viewport == null) return KeyEventResult.ignored;

    // Where this content sits within the visible area.
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final bottom = top + box.size.height;
    final position = scrollable.position;

    void scrollBy(double delta) => position.animateTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );

    // (In a small scrolling box, as a description beside a title's logo: the room it has.)
    final margin = math.min(_margin, viewport.size.height * 0.1);
    final atEnd = position.pixels >= position.maxScrollExtent - 0.5;
    final atStart = position.pixels <= position.minScrollExtent + 0.5;

    if (down) {
      if (!atEnd && bottom > viewport.size.height - margin) {
        scrollBy(
          math.min(_step, bottom - (viewport.size.height - margin)),
        ); // more below: keep reading
      } else if (widget.onEnd != null) {
        widget.onEnd!(); // reached the end
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }

    if (!atStart && top < margin) {
      scrollBy(-math.min(_step, margin - top)); // more above: keep reading
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored; // back at the start: let focus move up
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _node,
    canRequestFocus: widget.enabled,
    skipTraversal: !widget.enabled,
    onKeyEvent: _onKey,
    onFocusChange: (_) {
      // Arriving by keyboard: the page grows by as much as it needs to show all of it, from
      // where it is (or, too long for that, its start at the top), rather than jumping it up.
      if (_node.hasPrimaryFocus && _keyboard) KeepClearOfEdges.reveal(context, margin: 0.06);
    },
    child: widget.child,
  );
}
