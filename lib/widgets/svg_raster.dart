import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

/// SVGs drawn as pictures, rendered at the size they're shown.
///
/// Not drawn as vectors: on GPUs without multisampling, which many TVs have, Flutter draws a
/// vector's edges jagged. Rendered here at twice the size needed and smoothed as it's scaled
/// down, a picture's edges come out smooth everywhere.
abstract final class SvgRaster {
  /// How much bigger than needed it's rendered, for smoothing.
  static const _oversample = 2.0;

  static final _cache = <(String, int, int), Future<ui.Image?>>{};

  /// [svg] as an image [width] by [height] pixels (one of them may be null: from its shape), or
  /// null if it can't be read.
  static Future<ui.Image?> render(String svg, {double? width, double? height}) async {
    try {
      final info = await vg.loadPicture(SvgStringLoader(svg), null);
      final size = info.size;
      if (size.isEmpty) {
        info.picture.dispose();
        return null;
      }
      final scale = width != null ? width / size.width : (height ?? size.height) / size.height;
      final w = (size.width * scale).ceil(), h = (size.height * scale).ceil();
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..scale(scale)
        ..drawPicture(info.picture);
      final image = await recorder.endRecording().toImage(w, h);
      info.picture.dispose();
      return image;
    } catch (e) {
      debugPrint('SVG: $e');
      return null;
    }
  }

  /// [svg] as a PNG [width] pixels wide (as tall as its shape makes it), or null if it can't be
  /// read. For SVG pictures in a server's theme, saved as pictures.
  static Future<Uint8List?> toPng(String svg, {required double width}) async {
    final image = await render(svg, width: width);
    if (image == null) return null;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return png?.buffer.asUint8List();
  }

  /// Whether [bytes] look like an SVG.
  static bool looksLikeSvg(Uint8List bytes) {
    final head = String.fromCharCodes(bytes.take(512)).trimLeft().toLowerCase();
    return head.startsWith('<svg') || (head.startsWith('<?xml') && head.contains('<svg')) || head.contains('<svg');
  }

  /// The SVG asset [asset], rendered for [width] by [height] logical pixels at [ratio] device
  /// pixels each, kept for next time.
  static Future<ui.Image?> asset(String asset, {double? width, double? height, required double ratio}) {
    final w = ((width ?? 0) * ratio * _oversample).round(), h = ((height ?? 0) * ratio * _oversample).round();
    return _cache[(asset, w, h)] ??= rootBundle
        .loadString(asset)
        .then((svg) => render(svg, width: w == 0 ? null : w.toDouble(), height: h == 0 ? null : h.toDouble()));
  }
}

/// The SVG asset [asset], drawn from a picture rendered at this size (see [SvgRaster]); [tint]
/// fills it with one color. [placeholder] shows until it's ready.
class SvgAssetImage extends StatefulWidget {
  const SvgAssetImage(this.asset, {super.key, this.width, this.height, this.tint, required this.placeholder});

  final String asset;
  final double? width;
  final double? height;
  final Color? tint;
  final Widget placeholder;

  @override
  State<SvgAssetImage> createState() => _SvgAssetImageState();
}

class _SvgAssetImageState extends State<SvgAssetImage> {
  ui.Image? _image;
  Object? _for; // what it was rendered for

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(SvgAssetImage old) {
    super.didUpdateWidget(old);
    _load();
  }

  void _load() {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final key = (widget.asset, widget.width, widget.height, ratio);
    if (key == _for) return;
    _for = key;
    SvgRaster.asset(widget.asset, width: widget.width, height: widget.height, ratio: ratio).then((image) {
      if (mounted && key == _for) setState(() => _image = image);
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return widget.placeholder;
    // Its shape from the picture, for whichever of width and height isn't given.
    final aspect = image.width / image.height;
    final width = widget.width ?? (widget.height == null ? null : widget.height! * aspect);
    final height = widget.height ?? (widget.width == null ? null : widget.width! / aspect);
    return RawImage(
      image: image,
      width: width,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high, // smooth as it's scaled down
      color: widget.tint,
      colorBlendMode: widget.tint == null ? null : BlendMode.srcIn,
    );
  }
}
