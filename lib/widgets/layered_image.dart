import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

/// The first of [pictures] that loads; if none do (or there are none), [fallback]. A server
/// theme's picture, then the server's default, then the app's own (see docs/themes.md).
class LayeredImage extends StatefulWidget {
  const LayeredImage({
    super.key,
    required this.pictures,
    required this.fallback,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.width,
    this.height,
  });

  final List<ImageProvider> pictures;
  final Widget fallback;
  final BoxFit fit;
  final Alignment alignment;
  final double? width;
  final double? height;

  @override
  State<LayeredImage> createState() => _LayeredImageState();
}

class _LayeredImageState extends State<LayeredImage> {
  int _tried = 0; // how many have failed

  /// Whether a picture has shown. A new one (the same logo fetched again, say) then loads behind
  /// it, rather than the fallback flashing up while it does.
  bool _shown = false;

  @override
  void didUpdateWidget(LayeredImage old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.pictures, widget.pictures)) _tried = 0;
  }

  @override
  Widget build(BuildContext context) {
    if (_tried >= widget.pictures.length) return widget.fallback;
    return Image(
      key: ValueKey(_tried),
      image: widget.pictures[_tried],
      fit: widget.fit,
      alignment: widget.alignment,
      width: widget.width,
      height: widget.height,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true, // the last picture stays up while a new one loads
      // Until the first is in: the next thing down, so nothing pops in empty.
      frameBuilder: (context, child, frame, loaded) {
        if (loaded || frame != null) _shown = true;
        return _shown ? child : widget.fallback;
      },
      errorBuilder: (context, _, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _tried++;
              _shown = false; // (what showed was the one that failed)
            });
          }
        });
        return widget.fallback;
      },
    );
  }
}
