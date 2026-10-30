import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/focus/focus_rows.dart';
import '../core/platform/screen_type.dart';

/// The focus border a [FocusSlotRow] keeps fixed over its first slot: the shape of a focused
/// card's picture, where it sits in the card, and how much it grows when focused.
class SlotFrame {
  const SlotFrame({
    required this.width,
    required this.height,
    this.left = 0,
    this.top = 0,
    this.radius = 8,
    this.circle = false,
    this.borderWidth = 2.5,
    this.scale = 1,
  });

  /// The picture's size.
  final double width;
  final double height;

  /// Where the picture starts in the card: how far in from its left, and down from its top.
  final double left;
  final double top;

  final double radius;
  final bool circle; // a round photo (the cast)
  final double borderWidth;

  /// How much a focused card grows (about its middle).
  final double scale;
}

/// A sideways row of cards that, with a remote or keyboard, keeps the card you're on in its
/// first slot under one focus border that stays put: the row slides along under it, as
/// "Who's watching?" does, and each card lights up as it arrives. Room after the last card lets
/// every card reach the slot. On phones, and with touch or a mouse, it's an ordinary row: cards
/// show their own focus.
///
/// The cards in it leave their own focus border to the row (see [FocusSlotRow.ownsBorder]).
class FocusSlotRow extends StatefulWidget {
  const FocusSlotRow({
    super.key,
    required this.itemCount,
    required this.itemWidth,
    required this.itemBuilder,
    required this.separatorBuilder,
    required this.frameFor,
    this.padding = EdgeInsets.zero,
    this.controller,
    this.clipBehavior = Clip.hardEdge,
  });

  final int itemCount;

  /// A card's width, for the room after the last one.
  final double itemWidth;

  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder separatorBuilder;

  /// The border for card [index] (its picture can change size: a poster widening for its stills).
  final SlotFrame Function(int index) frameFor;

  /// Inside the list: its left side is where the slot is.
  final EdgeInsets padding;

  final ScrollController? controller;
  final Clip clipBehavior;

  /// Whether a card at [context] leaves its focus border to the [FocusSlotRow] it's in.
  static bool ownsBorder(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_SlotScope>()?.on ?? false;

  @override
  State<FocusSlotRow> createState() => _FocusSlotRowState();
}

class _FocusSlotRowState extends State<FocusSlotRow> {
  late final ScrollController _own = ScrollController();
  ScrollController get _scroll => widget.controller ?? _own;

  final _row = FocusNode(debugLabel: 'FocusSlotRow', canRequestFocus: false, skipTraversal: true);

  /// The card you're on, while focus is in the row.
  int? _focused;

  /// The row's width, once it's laid out (from the list's own measurements: a LayoutBuilder
  /// here would give the list a build scope of its own, which cards built as it scrolls trip
  /// over).
  double _width = 0;

  bool _onMetrics(ScrollMetricsNotification n) {
    final width = n.metrics.viewportDimension;
    if ((width - _width).abs() >= 0.5) {
      // (Not in the middle of laying out.)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _width = width);
      });
    }
    return false;
  }

  bool get _remote => FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onHighlightMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
    _own.dispose();
    _row.dispose();
    super.dispose();
  }

  void _onHighlightMode(FocusHighlightMode _) {
    if (mounted) setState(() {});
  }

  /// Card [index] got focus: slide the row so it sits in the slot. After this frame, so it
  /// comes after the page's own "keep it on screen" scroll, rather than being undone by it.
  void _onCardFocus(BuildContext card, int index) {
    setState(() => _focused = index);
    if (!_slotted(context)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || !card.mounted) return;
      final box = card.findRenderObject() as RenderBox?;
      final viewport = _scroll.position.context.storageContext.findRenderObject() as RenderBox?;
      if (box == null || viewport == null || !box.attached) return;
      final left = box.localToGlobal(Offset.zero, ancestor: viewport).dx;
      final position = _scroll.position;
      final target = (position.pixels + left - widget.padding.left).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((target - position.pixels).abs() < 0.5) return;
      position.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
    });
  }

  bool _slotted(BuildContext context) => _remote && !ScreenType.of(context).isPhone;

  @override
  Widget build(BuildContext context) {
    final slotted = _slotted(context);
    final padding = slotted
        ? widget.padding.copyWith(
            right: math.max(widget.padding.right, _width - widget.padding.left - widget.itemWidth),
          )
        : widget.padding;
    final focused = _focused;
    final frame = focused == null ? null : widget.frameFor(focused);
    final colors = Theme.of(context).colorScheme;
    return _SlotScope(
      on: slotted,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          FocusRow(
            entersAtStart: slotted,
            child: Focus(
              focusNode: _row,
              onFocusChange: (inside) {
                if (!inside) setState(() => _focused = null);
              },
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: _onMetrics,
                child: ListView.separated(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  clipBehavior: widget.clipBehavior,
                  padding: padding,
                  itemCount: widget.itemCount,
                  separatorBuilder: widget.separatorBuilder,
                  itemBuilder: (context, i) => Builder(
                    builder: (card) => Focus(
                      // Doesn't take focus itself: notices the card getting it.
                      canRequestFocus: false,
                      skipTraversal: true,
                      onFocusChange: (focused) {
                        if (focused) _onCardFocus(card, i);
                      },
                      child: widget.itemBuilder(context, i),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // The border, fixed over the slot.
          if (slotted && frame != null)
            Positioned(
              left: widget.padding.left + frame.left - frame.width * (frame.scale - 1) / 2,
              top: widget.padding.top + frame.top - frame.height * (frame.scale - 1) / 2,
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: frame.width * frame.scale,
                  height: frame.height * frame.scale,
                  decoration: BoxDecoration(
                    shape: frame.circle ? BoxShape.circle : BoxShape.rectangle,
                    borderRadius: frame.circle ? null : BorderRadius.circular(frame.radius * frame.scale),
                    border: Border.all(color: colors.primary, width: frame.borderWidth),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SlotScope extends InheritedWidget {
  const _SlotScope({required this.on, required super.child});

  final bool on;

  @override
  bool updateShouldNotify(_SlotScope old) => old.on != on;
}
