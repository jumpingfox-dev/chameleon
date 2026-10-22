import 'dart:math' as math;

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:material_ui/material_ui.dart';

import '../../theme/theme.dart';
import 'trailer_preview.dart';

/// A card's trailer, once it's playing, with nothing drawn over it (as YouTube requires).
///
/// [inline]: filling the card itself (which drops its focus border while it plays, so nothing
/// covers it). The card has to be tall enough for YouTube's player (see [minCardHeight]); Home's
/// rows are, and widen a poster to 16:9 while its trailer plays ([onShowing]).
///
/// Otherwise (grids, where a card can't widen): a 16:9 panel over the card, centered on it
/// (kept on screen at the edges), as tall as the card or YouTube's minimum, whichever is more.
///
/// Fill the card's area with it; it draws nothing there until the trailer plays.
class CardPreview extends StatefulWidget {
  const CardPreview({super.key, required this.item, required this.active, this.inline = false, this.onShowing});

  final JellyfinItem item;

  /// The card is focused or hovered.
  final bool active;

  /// Plays in the card rather than in a panel over it.
  final bool inline;

  /// The trailer started or stopped showing.
  final ValueChanged<bool>? onShowing;

  /// YouTube's player must be at least 200 × 200 of its own (web page) pixels.
  static const minVideoPixels = 200.0;

  /// The panel's border around the trailer, on each side.
  static const border = 3.0;

  /// The shortest a card playing its trailer inline may be, in the app's units, on any screen
  /// that isn't a phone: the app is never drawn at less than 0.8 of a web pixel per unit (see
  /// UiScaler), so 250 units is at least 200 of YouTube's pixels.
  static const minCardHeight = minVideoPixels / 0.8;

  @override
  State<CardPreview> createState() => _CardPreviewState();
}

class _CardPreviewState extends State<CardPreview> {
  final _portal = OverlayPortalController();

  /// The trailer is playing: it shows.
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    if (widget.active && !widget.inline) _portal.show();
  }

  @override
  void didUpdateWidget(CardPreview old) {
    super.didUpdateWidget(old);
    if (widget.inline) {
      if (!widget.active) _setShowing(false);
      return;
    }
    if (widget.active && !_portal.isShowing) {
      _portal.show();
    } else if (!widget.active && _portal.isShowing) {
      _portal.hide();
      _setShowing(false);
    }
  }

  @override
  void dispose() {
    if (_showing) widget.onShowing?.call(false);
    super.dispose();
  }

  /// Notes whether the trailer shows (called during builds too, so it doesn't rebuild), and
  /// tells [CardPreview.onShowing] after the frame.
  void _setShowing(bool showing) {
    if (_showing == showing) return;
    _showing = showing;
    final onShowing = widget.onShowing;
    if (onShowing != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _showing == showing) onShowing(showing);
      });
    }
  }

  /// Where the panel goes in the overlay: around the card's center, as far over as it takes to
  /// stay on screen.
  Rect? _panelRect(BuildContext overlayContext) {
    final card = context.findRenderObject();
    final overlay = overlayContext.findRenderObject();
    if (card is! RenderBox || overlay is! RenderBox || !card.hasSize || !overlay.hasSize) return null;
    final rect = MatrixUtils.transformRect(card.getTransformTo(overlay), Offset.zero & card.size);
    // Web pixels per app unit: the app is laid out at a virtual size and stretched (UiScaler).
    final view = View.of(context);
    final scale = view.physicalSize.width / view.devicePixelRatio / MediaQuery.sizeOf(context).width;
    // The card's height (or YouTube's minimum, plus the edge), and 16:9 around the trailer.
    const border = CardPreview.border;
    final height = math.max(rect.height, CardPreview.minVideoPixels / scale + 2 * border);
    final size = Size((height - 2 * border) * 16 / 9 + 2 * border, height);
    const margin = 16.0;
    final area = Offset.zero & overlay.size;
    final left = (rect.center.dx - size.width / 2).clamp(margin, math.max(margin, area.width - size.width - margin));
    final top = (rect.center.dy - size.height / 2).clamp(margin, math.max(margin, area.height - size.height - margin));
    return Offset(left.toDouble(), top.toDouble()) & size;
  }

  Widget _trailer({required bool panel}) => AnimatedOpacity(
    opacity: _showing ? 1 : 0,
    duration: const Duration(milliseconds: 250),
    child: DecoratedBox(
      // The panel's border sits outside the trailer, not over it.
      decoration: BoxDecoration(
        color: const Color(0xFF000000),
        border: panel ? Border.all(color: context.colors.primary, width: CardPreview.border) : null,
        borderRadius: panel ? BorderRadius.circular(12) : null,
        boxShadow: panel ? const [BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 8))] : null,
      ),
      child: Padding(
        padding: EdgeInsets.all(panel ? CardPreview.border : 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(panel ? 9 : 0), // in the card: the card's corners
          child: TrailerPreview(
            item: widget.item,
            active: widget.active,
            onShowing: (showing) {
              if (mounted && widget.active) setState(() => _setShowing(showing));
            },
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // Not touched or focused: the card keeps the mouse and the remote.
    if (widget.inline) {
      return IgnorePointer(
        child: ExcludeFocus(child: widget.active ? _trailer(panel: false) : const SizedBox.expand()),
      );
    }
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (overlayContext) {
        final rect = _panelRect(Overlay.of(overlayContext).context);
        if (rect == null) return const SizedBox.shrink();
        return Positioned.fromRect(
          rect: rect,
          child: IgnorePointer(
            child: ExcludeFocus(
              child: AnimatedScale(
                scale: _showing ? 1 : 0.85,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: _trailer(panel: true),
              ),
            ),
          ),
        );
      },
      child: const SizedBox.expand(),
    );
  }
}
