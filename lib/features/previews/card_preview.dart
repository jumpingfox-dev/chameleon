import 'dart:math' as math;

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:material_ui/material_ui.dart';

import '../../theme/theme.dart';
import '../library/poster_card.dart';
import 'frames_preview.dart';

/// A card's preview: stills from the title, just inside the card's focus border, which frames
/// them. Home's rows widen a poster to 16:9 while they play ([onShowing]).
///
/// [widen] (a poster in a grid, which can't make room): the stills play in a 16:9 panel the
/// card's height instead, over its neighbours, centered on the card and kept on screen, so a
/// poster grows to a thumbnail's shape there too.
///
/// Fill the card's area with it; it draws nothing there until the stills play.
class CardPreview extends StatefulWidget {
  const CardPreview({super.key, required this.item, required this.active, this.onShowing, this.widen = false});

  final JellyfinItem item;

  /// The card is focused or hovered.
  final bool active;

  /// The stills started or stopped showing.
  final ValueChanged<bool>? onShowing;

  /// Plays in a wider panel over the card rather than in it.
  final bool widen;

  @override
  State<CardPreview> createState() => _CardPreviewState();
}

class _CardPreviewState extends State<CardPreview> {
  final _portal = OverlayPortalController();
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    if (widget.widen && widget.active) _portal.show();
  }

  @override
  void didUpdateWidget(CardPreview old) {
    super.didUpdateWidget(old);
    if (!widget.widen) return;
    if (widget.active && !_portal.isShowing) {
      _portal.show();
    } else if (!widget.active && _portal.isShowing) {
      _portal.hide();
      _showing = false;
    }
  }

  Widget _frames() => FramesPreview(
    item: widget.item,
    active: widget.active,
    onShowing: (showing) {
      if (mounted) setState(() => _showing = showing);
      widget.onShowing?.call(showing);
    },
  );

  /// Where the panel goes in the overlay: the card's height, 16:9, around the card's middle,
  /// as far over as it takes to stay on screen.
  Rect? _panelRect(BuildContext overlayContext) {
    final card = context.findRenderObject();
    final overlay = overlayContext.findRenderObject();
    if (card is! RenderBox || overlay is! RenderBox || !card.hasSize || !overlay.hasSize) return null;
    final rect = MatrixUtils.transformRect(card.getTransformTo(overlay), Offset.zero & card.size);
    final width = math.max(rect.width, rect.height * 16 / 9);
    const margin = 16.0;
    final left = (rect.center.dx - width / 2).clamp(margin, math.max(margin, overlay.size.width - width - margin));
    return Rect.fromLTWH(left.toDouble(), rect.top, width, rect.height);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.widen) {
      return ExcludeFocus(
        child: Padding(
          padding: const EdgeInsets.all(PosterCard.borderWidth),
          child: ClipRRect(borderRadius: BorderRadius.circular(6), child: _frames()),
        ),
      );
    }
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (overlayContext) {
        final rect = _panelRect(Overlay.of(overlayContext).context);
        if (rect == null) return const SizedBox.shrink();
        return Positioned.fromRect(
          rect: rect,
          // Not touched or focused: the card underneath keeps the mouse and the remote.
          child: IgnorePointer(
            child: ExcludeFocus(
              child: AnimatedOpacity(
                opacity: _showing ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF000000),
                    border: Border.all(color: context.colors.primary, width: PosterCard.borderWidth),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 8))],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(PosterCard.borderWidth),
                    child: ClipRRect(borderRadius: BorderRadius.circular(6), child: _frames()),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: const SizedBox.expand(),
    );
  }
}
