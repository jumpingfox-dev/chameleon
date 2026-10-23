import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../../core/jellyfin/jellyfin_controller.dart';
import '../player/playback_settings.dart';

// Frame previews: after a moment on a card (or the featured banner), five stills from across
// the title play one after another, and then the artwork comes back. Trailers play only from the
// Trailer button on the title's page.
//
// The stills, best first: the movie's chapter images (full size, so sharp even across the banner),
// otherwise its trickplay thumbnails (Jellyfin's scrubbing frames, small), otherwise the title's
// own backdrops if it has a few (shows keep chapters and trickplay on their episodes).

/// One still to show.
sealed class _Frame {
  const _Frame();
}

/// A whole image, asked for at a given width in pixels.
class _ImageFrame extends _Frame {
  const _ImageFrame(this.url);
  final String Function(int width) url;
}

/// One thumbnail on a trickplay sheet ([cols] × [rows] thumbnails, each [aspect] wide to tall).
class _TileFrame extends _Frame {
  const _TileFrame({required this.url, required this.col, required this.row, required this.cols, required this.rows, required this.aspect});
  final String url;
  final int col, row, cols, rows;
  final double aspect;
}

/// How many stills a preview shows, and how: each fades in, holds, and fades to black before
/// the next, like the Backdrop screensaver. Five of them come to ten seconds.
const _count = 5;
const _hold = Duration(milliseconds: 1200);
const _fade = Duration(milliseconds: 400);

/// Each title's stills, looked up once per run.
final _frames = <String, Future<List<_Frame>>>{};

Future<List<_Frame>> _framesFor(JellyfinItem item) => _frames[item.id] ??= _lookUp(item);

Future<List<_Frame>> _lookUp(JellyfinItem item) async {
  final client = jellyfin.client;
  if (client == null) return const [];
  try {
    final full = await client.items.byId(item.id); // lists leave chapters and trickplay out
    if (full == null) return const [];
    final base = client.baseUrl;
    if (base == null) return const [];
    final id = item.id;

    // Chapter images, without the first and last (studio logos, end credits) when there are enough.
    final chapters = [
      for (final (i, c) in ((full.raw['Chapters'] as List?) ?? const []).indexed)
        if (c is Map && c['ImageTag'] is String) (index: i, tag: c['ImageTag'] as String),
    ];
    final usable = chapters.length > 4 ? chapters.sublist(1, chapters.length - 1) : chapters;
    // Jellyfin saves chapter images at very different quality, and many are dim or blank frames:
    // a few more than needed are looked at, and only clean, detailed ones kept.
    final candidates = _spread(usable, _count + 3);
    final good = await Future.wait([
      for (final c in candidates) _isGoodStill('$base/Items/$id/Images/Chapter/${c.index}?tag=${c.tag}'),
    ]);
    final kept = [for (final (i, c) in candidates.indexed) if (good[i]) c];
    if (kept.length >= 3) {
      return [
        for (final c in _spread(kept, _count))
          _ImageFrame((w) => '$base/Items/$id/Images/Chapter/${c.index}?tag=${c.tag}&fillWidth=$w&quality=85'),
      ];
    }

    if (_trickplay(full, base) case final frames?) return frames;

    final backdrops = ((full.raw['BackdropImageTags'] as List?) ?? const []).whereType<String>().toList();
    if (backdrops.length >= 2) {
      return [
        for (final (i, tag) in backdrops.indexed.take(_count))
          _ImageFrame((w) => '$base/Items/$id/Images/Backdrop/$i?tag=$tag&fillWidth=$w&quality=85'),
      ];
    }
  } catch (e) {
    debugPrint('Preview frames for ${item.id}: $e');
    _frames.remove(item.id); // try again next time
  }
  return const [];
}

/// Whether the image at [url] (as saved, not re-encoded) is worth showing: compressed no harder
/// than about JPEG quality 70, and with some detail in it (a dim or blank frame comes out tiny).
Future<bool> _isGoodStill(String url) async {
  try {
    final res = await http.get(Uri.parse(url), headers: jellyfin.authHeaders).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return false;
    final jpeg = readJpegInfo(res.bodyBytes);
    if (jpeg == null) return true; // not a JPEG: nothing to judge by
    final megapixels = jpeg.width * jpeg.height / 1e6;
    final kilobytesPerMegapixel = res.bodyBytes.length / 1024 / math.max(megapixels, 0.1);
    return jpeg.quantization <= 30 && kilobytesPerMegapixel >= 8;
  } catch (_) {
    return false;
  }
}

/// A JPEG's size, and its average brightness quantization step (bigger = more compressed:
/// about 11 at quality 90, 29 at 75, 58 at 50), read from its headers.
@visibleForTesting
({int width, int height, double quantization})? readJpegInfo(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  int? width, height;
  double? quantization;
  var i = 2;
  while (i + 4 <= b.length) {
    if (b[i] != 0xFF) return null;
    final marker = b[i + 1];
    final length = (b[i + 2] << 8) | b[i + 3];
    final start = i + 4, end = i + 2 + length;
    if (end > b.length) break;
    if (marker == 0xDB) {
      // One or more tables: a byte of precision and id, then 64 steps of 1 or 2 bytes each.
      var j = start;
      while (j < end) {
        final precision = b[j] >> 4, id = b[j] & 0x0F;
        final size = precision == 0 ? 1 : 2;
        if (id == 0 && quantization == null) {
          var sum = 0;
          for (var k = 0; k < 64; k++) {
            final at = j + 1 + k * size;
            sum += size == 1 ? b[at] : (b[at] << 8) | b[at + 1];
          }
          quantization = sum / 64;
        }
        j += 1 + 64 * size;
      }
    } else if (marker >= 0xC0 && marker <= 0xC3) {
      height = (b[start + 1] << 8) | b[start + 2];
      width = (b[start + 3] << 8) | b[start + 4];
    } else if (marker == 0xDA) {
      break; // the image data: the headers are done
    }
    i = end;
  }
  if (width == null || height == null || quantization == null) return null;
  return (width: width, height: height, quantization: quantization);
}

/// [count] of [all], evenly spread from first to last.
List<T> _spread<T>(List<T> all, int count) {
  if (all.length <= count) return all;
  return [for (var i = 0; i < count; i++) all[(i * (all.length - 1) / (count - 1)).round()]];
}

/// Thumbnails from 8% to 85% of the way through (past the opening logos, before the credits).
List<_Frame>? _trickplay(JellyfinItem item, String base) {
  final all = item.raw['Trickplay'];
  if (all is! Map || all.isEmpty) return null;
  final source = all.entries.first; // by media source, then by thumbnail width
  final sizes = source.value;
  if (sizes is! Map || sizes.isEmpty) return null;
  final info = sizes.values.whereType<Map>().reduce((a, b) => (a['Width'] as int) >= (b['Width'] as int) ? a : b);
  final width = info['Width'] as int, height = info['Height'] as int;
  final perRow = info['TileWidth'] as int, perColumn = info['TileHeight'] as int;
  final count = info['ThumbnailCount'] as int;
  if (count < _count || width <= 0 || height <= 0) return null;
  final perSheet = perRow * perColumn;
  return [
    for (var i = 0; i < _count; i++)
      () {
        final index = (count * (0.08 + 0.77 * i / (_count - 1))).floor();
        final sheet = index ~/ perSheet, inSheet = index % perSheet;
        final onSheet = math.min(perSheet, count - sheet * perSheet);
        return _TileFrame(
          url: '$base/Videos/${item.id}/Trickplay/$width/$sheet.jpg?MediaSourceId=${source.key}',
          col: inSheet % perRow,
          row: inSheet ~/ perRow,
          cols: math.min(perRow, onSheet),
          rows: (onSheet / perRow).ceil(),
          aspect: width / height,
        );
      }(),
  ];
}

/// A title's stills, one after another with a fade to black between, over its artwork: once
/// [active] (the card or banner focused or hovered) has held for the delay from Settings. Plays
/// once (ten seconds at most), then fades away, until [active] goes and comes back. Shows nothing until the first still is in, so a title without
/// any looks just as before. Fills the space, cropping what doesn't fit.
class FramesPreview extends StatefulWidget {
  const FramesPreview({super.key, required this.item, required this.active, this.onShowing, this.onFinished});

  final JellyfinItem item;
  final bool active;

  /// Told when the stills appear (true) and go (false).
  final ValueChanged<bool>? onShowing;

  /// Told once the last still has shown.
  final VoidCallback? onFinished;

  /// Titles that can have stills.
  static bool supports(JellyfinItem item) =>
      item.type == JellyfinItemKind.movie || item.type == JellyfinItemKind.series;

  @override
  State<FramesPreview> createState() => _FramesPreviewState();
}

class _FramesPreviewState extends State<FramesPreview> {
  Timer? _wait;
  Timer? _step;
  List<_Frame>? _playing; // the stills showing, or null
  int _index = 0;
  bool _lit = false; // the still is in view, not faded to black
  bool _played = false; // played through on this visit
  int _width = 640; // pixels to ask for: what the space covers on screen

  bool _shown = false;
  set _visible(bool value) {
    if (value == _shown) return;
    _shown = value;
    // After this frame: this can change while the parent is building.
    final onShowing = widget.onShowing;
    if (onShowing != null) WidgetsBinding.instance.addPostFrameCallback((_) => onShowing(value));
  }

  @override
  void initState() {
    super.initState();
    if (widget.active) _schedule();
  }

  @override
  void didUpdateWidget(FramesPreview old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active && widget.item.id == old.item.id) return;
    _stop();
    _played = false;
    if (widget.active) _schedule();
  }

  @override
  void dispose() {
    _wait?.cancel();
    _step?.cancel();
    super.dispose();
  }

  void _schedule() {
    final s = playbackSettings;
    if (!s.previews || _played || !FramesPreview.supports(widget.item)) return;
    final frames = _framesFor(widget.item); // looked up meanwhile
    _wait = Timer(Duration(seconds: s.previewDelay), () async {
      final list = await frames;
      if (!mounted || !widget.active || list.isEmpty) return;
      await _load(list.first); // shown whole, not drawn in as it loads
      if (!mounted || !widget.active) return;
      setState(() {
        _playing = list;
        _index = 0;
        _lit = true;
        _visible = true; // the first still comes in straight over the artwork
      });
      _next();
    });
  }

  /// Holds this still while loading the next, then fades to black and brings the next in.
  /// After the last, the artwork fades back.
  void _next() {
    final list = _playing;
    if (list == null) return;
    final last = _index + 1 >= list.length;
    if (!last) unawaited(_load(list[_index + 1]));
    _step = Timer(_fade + _hold, () {
      if (!mounted || _playing != list) return;
      if (last) {
        _played = true;
        widget.onFinished?.call();
        _stop();
        return;
      }
      setState(() => _lit = false);
      _step = Timer(_fade, () {
        if (!mounted || _playing != list) return;
        setState(() {
          _index++;
          _lit = true;
        });
        _next();
      });
    });
  }

  Future<void> _load(_Frame frame) async {
    final provider = switch (frame) {
      _ImageFrame(:final url) => NetworkImage(url(_width), headers: jellyfin.authHeaders),
      _TileFrame(:final url) => NetworkImage(url, headers: jellyfin.authHeaders),
    };
    try {
      await precacheImage(provider, context);
    } catch (_) {} // shows what it can
  }

  void _stop() {
    _wait?.cancel();
    _wait = null;
    _step?.cancel();
    _step = null;
    if (!_shown) {
      if (_playing != null) setState(() => _playing = null);
      return;
    }
    // Fades out over the still showing, then lets it go.
    final list = _playing;
    setState(() => _visible = false);
    _step = Timer(_fade, () {
      if (mounted && _playing == list && !_shown) setState(() => _playing = null);
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Pixels on screen per layout unit (the app is laid out at a virtual size and scaled).
      final pixels = View.of(context).physicalSize.width / MediaQuery.sizeOf(context).width;
      _width = ((constraints.maxWidth * pixels / 320).ceil() * 320).clamp(320, 1920);
      final list = _playing;
      return IgnorePointer(
        child: AnimatedOpacity(
          opacity: _shown ? 1 : 0,
          duration: _fade,
          child: list == null
              ? const SizedBox.expand()
              : ColoredBox(
                  color: const Color(0xFF000000),
                  child: AnimatedOpacity(
                    opacity: _lit ? 1 : 0,
                    duration: _fade,
                    child: KeyedSubtree(
                      key: ValueKey(_index),
                      child: _still(list[_index], constraints.biggest),
                    ),
                  ),
                ),
        ),
      );
    },
  );

  Widget _still(_Frame frame, Size area) => switch (frame) {
    _ImageFrame(:final url) => Image.network(
      url(_width),
      headers: jellyfin.authHeaders,
      fit: BoxFit.cover,
      width: area.width,
      height: area.height,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF000000)),
    ),
    _TileFrame() => _Tile(frame: frame, area: area),
  };
}

/// One thumbnail of a trickplay sheet, covering [area]: the whole sheet is drawn so that one
/// thumbnail is the size it should show at, slid so that thumbnail sits in view, and clipped.
class _Tile extends StatelessWidget {
  const _Tile({required this.frame, required this.area});

  final _TileFrame frame;
  final Size area;

  @override
  Widget build(BuildContext context) {
    final w = math.max(area.width, area.height * frame.aspect);
    final h = w / frame.aspect;
    return ClipRect(
      child: SizedBox.fromSize(
        size: area,
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(
            width: w,
            height: h,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: Transform.translate(
                  offset: Offset(-frame.col * w, -frame.row * h),
                  child: Image.network(
                    frame.url,
                    headers: jellyfin.authHeaders,
                    width: w * frame.cols,
                    height: h * frame.rows,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF000000)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
