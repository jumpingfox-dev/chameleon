import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../theme/app_icons.dart';
import '../../core/focus/scroll_into_view.dart';
import '../../theme/theme.dart';
import '../../widgets/tappable.dart';

/// Text that's cut off after [limit] characters, with a "Read more" link to show the rest.
/// Expanded text can be read with a keyboard or remote (see [KeyboardReadable]).
///
/// [ExpandableText.fill]: as many lines as fit in the height it's given, rather than a number
/// of characters; expanded, the rest scrolls in that same space, with a scrollbar.
class ExpandableText extends StatefulWidget {
  const ExpandableText(this.text, {super.key, this.limit = 250, this.style}) : fill = false;

  const ExpandableText.fill(this.text, {super.key, this.style}) : limit = 0, fill = true;

  final String text;
  final int limit;
  final TextStyle? style;

  /// See [ExpandableText.fill].
  final bool fill;

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _expanded = false;
  final _textFocus = FocusNode(); // the text itself, while reading
  final _linkFocus = FocusNode(); // the "Read more" / "Show less" link
  final _scroll = ScrollController(); // the expanded text, in fill mode

  @override
  void dispose() {
    _textFocus.dispose();
    _linkFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The text up to [length], cut at the last space so words aren't split.
  String _cut(int length) {
    final cut = widget.text.substring(0, length);
    final lastSpace = cut.lastIndexOf(' ');
    return '${(lastSpace > 0 ? cut.substring(0, lastSpace) : cut).trimRight()}…';
  }

  void _toggle() {
    final expanding = !_expanded;
    setState(() => _expanded = expanding);
    if (!expanding && _scroll.hasClients) _scroll.jumpTo(0);

    // With a keyboard or remote, start reading at the top of the full text.
    if (expanding &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _textFocus.requestFocus();
      });
    }
  }

  TextStyle _linkStyle(TextStyle style, Color color, {bool active = false}) => style.copyWith(
    color: color,
    fontWeight: FontWeight.w600,
    decoration: active ? TextDecoration.underline : TextDecoration.none,
    decorationColor: color,
  );

  /// In fill mode, collapsed: the most of the text that fits in [lines] lines of [width] with
  /// "… Read more" after it; null if all of it fits, link and all not needed.
  String? _fitted(BuildContext context, TextStyle style, double width, int lines) {
    final scaler = MediaQuery.textScalerOf(context);
    // The link as it's drawn (see [_text]): its words, a gap, and its icon, sitting on the line's
    // baseline. Measured, so it's never pushed onto a line past the room.
    final words = TextPainter(
      text: TextSpan(text: 'Read more', style: _linkStyle(style, const Color(0xFF000000))),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final iconSize = (style.fontSize ?? 14) * 0.9;
    final link = PlaceholderDimensions(
      size: Size(words.width + 4 + iconSize, math.max(words.height, iconSize)),
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      baselineOffset: words.computeDistanceToActualBaseline(TextBaseline.alphabetic),
    );

    bool fits(String text, {bool withLink = true}) {
      final painter = TextPainter(
        text: TextSpan(
          style: style,
          children: [
            TextSpan(text: text),
            if (withLink) ...[
              const TextSpan(text: ' '),
              const WidgetSpan(child: SizedBox.shrink()),
            ],
          ],
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: lines,
      );
      if (withLink) painter.setPlaceholderDimensions([link]);
      painter.layout(maxWidth: width);
      return !painter.didExceedMaxLines;
    }

    if (fits(widget.text, withLink: false)) return null;
    var low = 0, high = widget.text.length;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (fits(_cut(mid))) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return _cut(math.max(1, low));
  }

  @override
  Widget build(BuildContext context) {
    // As the text is drawn: over the default style (its line height too), for measuring it.
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    if (widget.fill) return _filled(context, style);
    final isLong = widget.text.length > widget.limit;
    return _text(context, style, shown: isLong && !_expanded ? _cut(widget.limit) : widget.text, link: isLong);
  }

  /// Fill mode: as many lines as the height allows; expanded, all of it, scrolling in that room.
  Widget _filled(BuildContext context, TextStyle style) => LayoutBuilder(
    builder: (context, constraints) {
      final lines = math.max(1, (constraints.maxHeight / lineHeightOf(context, style)).floor());
      final fitted = _fitted(context, style, constraints.maxWidth, lines);
      if (fitted == null) return _text(context, style, shown: widget.text, link: false);
      if (!_expanded) return _text(context, style, shown: fitted, link: true);
      return SizedBox(
        height: constraints.maxHeight,
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.only(right: 16), // clear of the scrollbar
            child: _text(context, style, shown: widget.text, link: true),
          ),
        ),
      );
    },
  );

  Widget _text(BuildContext context, TextStyle style, {required String shown, required bool link}) => KeyboardReadable(
    focusNode: _textFocus,
    enabled: link && _expanded,
    onEnd: _linkFocus.requestFocus, // finished reading: ↓ lands on "Show less"
    child: Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: shown),
          if (link) ...[
            const TextSpan(text: ' '),
            // Inline with the text, but still a focusable, tappable link.
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              // Landing on it, kept clear of the screen's top and bottom edges.
              child: KeepClearOfEdges(
                child: Tappable(
                  focusNode: _linkFocus,
                  onPress: _toggle,
                  builder: (context, states, _) {
                    final color = context.colors.primary;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 4,
                      children: [
                        Text(
                          _expanded ? 'Show less' : 'Read more',
                          // The same size as the text it follows.
                          style: _linkStyle(style, color, active: isHighlighted(states)),
                        ),
                        Icon(
                          _expanded ? appIcons.collapse : appIcons.expand,
                          size: (style.fontSize ?? 14) * 0.9,
                          color: color,
                          fill: 1,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
