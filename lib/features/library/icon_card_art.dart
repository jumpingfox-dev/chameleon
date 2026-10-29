import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

/// An icon card's color and big faint icon (see IconCard), drawn once as a picture at the size
/// it's shown, and saved: drawing the icon from its font for every card, every frame, made
/// rows of them slow on TVs. Each is kept in memory, and on disk for the next launch.
abstract final class IconCardArt {
  /// Bumped when the drawing changes, so older pictures are drawn again.
  static const _version = 1;

  static final _memory = <String, Future<ui.Image?>>{};
  static Future<Directory?>? _dir;

  static Future<Directory?> get _folder => _dir ??= () async {
    try {
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/icon_cards');
      await dir.create(recursive: true);
      return dir;
    } catch (_) {
      return null; // drawn every launch instead
    }
  }();

  /// The card for [name] with [icon], [width] by [height] pixels.
  static Future<ui.Image?> of(String name, IconData icon, int width, int height) {
    final key = 'v${_version}_${_safe(name)}_${icon.codePoint}_${_safe(icon.fontFamily ?? '')}_${width}x$height';
    return _memory[key] ??= _load(key, name, icon, width, height);
  }

  static String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9]'), '-');

  static Future<ui.Image?> _load(String key, String name, IconData icon, int width, int height) async {
    final dir = await _folder;
    final file = dir == null ? null : File('${dir.path}/$key.png');
    if (file != null && file.existsSync()) {
      try {
        final codec = await ui.instantiateImageCodec(await file.readAsBytes());
        return (await codec.getNextFrame()).image;
      } catch (_) {
        // Unreadable: drawn again.
      }
    }
    final image = await _draw(name, icon, width, height);
    if (image != null && file != null) {
      unawaited(() async {
        try {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          if (png != null) await file.writeAsBytes(png.buffer.asUint8List());
        } catch (e) {
          debugPrint('Icon card: $e');
        }
      }());
    }
    return image;
  }

  /// A hue picked from the name, so each keeps its color.
  static double hueOf(String name) {
    var h = 0;
    for (final c in name.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return (h % 360).toDouble();
  }

  /// Its gradient's colors (also shown while the picture's being made).
  static List<Color> colorsOf(String name) {
    final hue = hueOf(name);
    return [
      HSLColor.fromAHSL(1, hue, 0.45, 0.36).toColor(),
      HSLColor.fromAHSL(1, (hue + 25) % 360, 0.5, 0.16).toColor(),
    ];
  }

  /// From its top left corner to its bottom right.
  static LinearGradient gradientOf(String name) =>
      LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colorsOf(name));

  static Future<ui.Image?> _draw(String name, IconData icon, int width, int height) async {
    try {
      final w = width.toDouble(), h = height.toDouble();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        Offset.zero & Size(w, h),
        Paint()..shader = gradientOf(name).createShader(Offset.zero & Size(w, h)),
      );
      // The icon: 85% of the height, hanging off the bottom right corner, tilted.
      final size = h * 0.85;
      final glyph = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: size,
            height: 1,
            color: const Color(0x33FFFFFF),
            fontVariations: const [FontVariation('FILL', 1)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final box = Rect.fromLTWH(w + h * 0.12 - size, h + h * 0.12 - size, size, size);
      canvas
        ..save()
        ..translate(box.center.dx, box.center.dy)
        ..rotate(-0.2)
        ..translate(-glyph.width / 2, -glyph.height / 2);
      glyph.paint(canvas, Offset.zero);
      canvas.restore();
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      picture.dispose();
      return image;
    } catch (e) {
      debugPrint('Icon card: $e');
      return null;
    }
  }
}
