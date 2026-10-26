import 'dart:async';
import 'dart:math' as math;

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/format/format.dart';
import '../../core/jellyfin/jellyfin_controller.dart';
import '../player/playback_settings.dart';

// Previews: after a moment on a card (or the featured banner), a little of the title plays over
// its artwork, and then the artwork comes back. Trailers play only from the Trailer button on the
// title's page; these are for a glance.
//
// What plays, first that it has:
//  - a video of its own on the server: a theme video (Jellyfin's preview or backdrop videos),
//    or a local trailer. Silent, up to [_videoMost].
//  - a stretch of it as a quick flip-book: its trickplay thumbnails (Jellyfin's scrubbing
//    frames) in order, from a quarter of the way in (past any opening credits, usually before an
//    intro). A show's are its pilot's (season 1, episode 1).
// Without either, nothing: the card stays as it is.

/// What a title's preview plays.
sealed class _Preview {
  const _Preview();
}

/// A video file on the server, with the flip-book to fall back on if it won't play.
class _VideoPreview extends _Preview {
  const _VideoPreview(this.itemId, {this.fallback});
  final String itemId;
  final _FramesPreview? fallback;
}

/// Trickplay thumbnails, in order.
class _FramesPreview extends _Preview {
  const _FramesPreview(this.frames);
  final List<_TileFrame> frames;
}

/// One thumbnail on a trickplay sheet: [col] and [row] on it, each thumbnail [pixelWidth]
/// pixels wide and [aspect] wide to tall.
class _TileFrame {
  const _TileFrame({required this.url, required this.col, required this.row, required this.pixelWidth, required this.aspect});
  final String url;
  final int col, row;
  final int pixelWidth;
  final double aspect;
}

/// How many frames a flip-book shows, and for how long each (crossfading into the next):
/// fifteen come to about nine seconds.
const _count = 15;
const _frameTime = Duration(milliseconds: 600);
const _crossfade = Duration(milliseconds: 180);

/// How far in the frames start.
const _startAt = 0.25;

/// The longest a video preview plays.
const _videoMost = Duration(seconds: 30);

/// The preview fading in over the artwork, and back out.
const _fade = Duration(milliseconds: 400);

/// Each title's preview, looked up once per run (null: it has none).
final _previews = <String, Future<_Preview?>>{};

Future<_Preview?> _previewFor(JellyfinItem item) => _previews[item.id] ??= _lookUp(item);

Future<_Preview?> _lookUp(JellyfinItem item) async {
  final client = jellyfin.client;
  final base = client?.baseUrl;
  if (client == null || base == null) return null;
  try {
    // Its trickplay (a show's pilot's): the flip-book, or what a video falls back to.
    final source = item.type == JellyfinItemKind.series ? await _pilotOf(client, item.id) : item;
    final full = source == null ? null : await client.items.byId(source.id); // lists leave trickplay out
    final frames = switch (full == null ? null : _trickplay(full, base)) {
      final frames? => _FramesPreview(frames),
      null => null,
    };

    // A video of its own first: a theme video, or a local trailer.
    final themes = await client.library.themeVideos(itemId: item.id).then((r) => r.items, onError: (Object _) => const <JellyfinItem>[]);
    if (themes.firstOrNull case final video?) return _VideoPreview(video.id, fallback: frames);
    if (((item.raw['LocalTrailerCount'] as int?) ?? 1) > 0) {
      final trailers = await client.items.localTrailers(item.id).catchError((Object _) => const <JellyfinItem>[]);
      if (trailers.firstOrNull case final trailer?) return _VideoPreview(trailer.id, fallback: frames);
    }
    return frames;
  } catch (e) {
    debugPrint('Preview for ${item.id}: $e');
    _previews.remove(item.id); // try again next time
  }
  return null;
}

/// A show's pilot: season 1's first episode (or the first season's, without a season 1).
Future<JellyfinItem?> _pilotOf(JellyfinClient client, String seriesId) async {
  final seasons = (await client.tvShows.seasons(seriesId: seriesId)).items;
  final season =
      seasons.where((s) => s.raw['IndexNumber'] == 1).firstOrNull ??
      seasons.where((s) => ((s.raw['IndexNumber'] as int?) ?? 0) > 0).firstOrNull ??
      seasons.firstOrNull;
  if (season == null) return null;
  final episodes = (await client.tvShows.episodes(seriesId: seriesId, seasonId: season.id)).items;
  return episodes.where((e) => e.raw['IndexNumber'] == 1).firstOrNull ?? episodes.firstOrNull;
}

/// [_count] thumbnails in a row, from a quarter of the way in: a short stretch of the title.
List<_TileFrame>? _trickplay(JellyfinItem item, String base) {
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
  final first = math.min((count * _startAt).floor(), count - _count);
  return [
    for (var index = first; index < first + _count; index++)
      _TileFrame(
        url: '$base/Videos/${item.id}/Trickplay/$width/${index ~/ perSheet}.jpg?MediaSourceId=${source.key}',
        col: (index % perSheet) % perRow,
        row: (index % perSheet) ~/ perRow,
        pixelWidth: width,
        aspect: width / height,
      ),
  ];
}

/// The one player for video previews, shared: only one plays at a time. Silent.
///
/// It plays a light copy the server makes (H.264, 1280 wide at most, about 4 Mbps): a card
/// doesn't need a 4K original, which a TV may not decode quickly enough (or at all) in a
/// preview. The server's copying stops when the preview does.
class _SharedPlayer {
  static Player? _player;
  static VideoController? _video;
  static Object? _owner;
  static String? _session; // the server's copying for the preview playing

  static const _deviceId = 'chameleon-preview';

  static Player get player => _player ??= Player(
    configuration: const PlayerConfiguration(bufferSize: 16 * 1024 * 1024),
  );

  static VideoController get video => _video ??= VideoController(player);

  /// Plays [itemId]'s file for [owner], and returns once it's moving (true), or false if
  /// another card took over or [owner] stopped it meanwhile.
  static Future<bool> play(Object owner, String itemId) async {
    final client = jellyfin.client;
    if (client == null) return false;
    video; // both made
    _owner = owner;
    await _endSession();
    final session = _session = randomHexId();
    final url = Uri.parse('${client.baseUrl}/Videos/$itemId/master.m3u8').replace(
      queryParameters: {
        'MediaSourceId': itemId,
        'DeviceId': _deviceId,
        'PlaySessionId': session,
        'api_key': client.token ?? '',
        'VideoCodec': 'h264',
        'AudioCodec': 'aac',
        'MaxWidth': '1280',
        'VideoBitrate': '4000000',
        'MaxStreamingBitrate': '4200000',
        'AllowVideoStreamCopy': 'true', // a file that already fits is sent as it is
        'AllowAudioStreamCopy': 'true',
        'SegmentContainer': 'ts',
        'BreakOnNonKeyFrames': 'true',
      },
    );
    await player.setVolume(0);
    await player.open(Media(url.toString(), httpHeaders: jellyfin.authHeaders));
    if (_owner != owner) return false;
    await player.stream.position.firstWhere((p) => p > Duration.zero).timeout(const Duration(seconds: 15));
    return _owner == owner;
  }

  /// Stops, if [owner] is still the one playing.
  static Future<void> stop(Object owner) async {
    if (_owner != owner) return;
    _owner = null;
    await _player?.stop();
    await _endSession();
  }

  /// Stops the server copying the last preview.
  static Future<void> _endSession() async {
    final session = _session;
    final base = jellyfin.client?.baseUrl;
    _session = null;
    if (session == null || base == null) return;
    try {
      await http
          .delete(
            Uri.parse('$base/Videos/ActiveEncodings').replace(
              queryParameters: {'deviceId': _deviceId, 'playSessionId': session},
            ),
            headers: jellyfin.authHeaders,
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // The server ends abandoned copies by itself after a while.
    }
  }
}

/// The title's preview over its artwork: a video of its own, or a stretch of it as a flip-book
/// (see the top of this file). Starts once [active] (the card or banner focused or hovered) has
/// held for the delay from Settings; plays once, then fades away, until [active] goes and comes
/// back. Shows nothing until it's actually playing, so a title without one looks just as before.
/// Fills the space, cropping what doesn't fit.
class FramesPreview extends StatefulWidget {
  const FramesPreview({super.key, required this.item, required this.active, this.onShowing, this.onFinished});

  final JellyfinItem item;
  final bool active;

  /// Told when the preview appears (true) and goes (false).
  final ValueChanged<bool>? onShowing;

  /// Told once it has played through.
  final VoidCallback? onFinished;

  /// Titles that can have one.
  static bool supports(JellyfinItem item) =>
      item.type == JellyfinItemKind.movie || item.type == JellyfinItemKind.series;

  @override
  State<FramesPreview> createState() => _FramesPreviewState();
}

class _FramesPreviewState extends State<FramesPreview> {
  Timer? _wait;
  Timer? _step;
  _Preview? _playing; // what's showing, or null
  int _index = 0; // the frame showing, in a flip-book
  bool _played = false; // played through on this visit

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
    unawaited(_SharedPlayer.stop(this));
    super.dispose();
  }

  void _schedule() {
    final s = playbackSettings;
    if (!s.previews || _played || !FramesPreview.supports(widget.item)) return;
    final preview = _previewFor(widget.item); // looked up meanwhile
    _wait = Timer(Duration(seconds: s.previewDelay), () async {
      final found = await preview;
      if (!mounted || !widget.active || found == null) return;
      switch (found) {
        case _VideoPreview(:final itemId):
          bool moving;
          try {
            moving = await _SharedPlayer.play(this, itemId);
          } catch (_) {
            moving = false;
          }
          if (!mounted || !widget.active) return;
          // It won't play here: the flip-book instead, if there is one.
          if (!moving) {
            await _SharedPlayer.stop(this);
            if (found.fallback case final frames?) await _playFrames(frames);
            return;
          }
          setState(() {
            _playing = found;
            _visible = true;
          });
          // Until it ends, or [_videoMost].
          final ended = _SharedPlayer.player.stream.completed.firstWhere((done) => done);
          _step = Timer(_videoMost, () => _finish(found));
          unawaited(ended.then((_) => _finish(found), onError: (Object _) {}));
        case _FramesPreview():
          await _playFrames(found);
      }
    });
  }

  Future<void> _playFrames(_FramesPreview preview) async {
    await _load(preview.frames.first); // shown whole, not drawn in as it loads
    if (!mounted || !widget.active) return;
    setState(() {
      _playing = preview;
      _index = 0;
      _visible = true;
    });
    _next();
  }

  /// Shows each frame for [_frameTime], crossfading into the next (loaded meanwhile). After the
  /// last, the artwork fades back.
  void _next() {
    final preview = _playing;
    if (preview is! _FramesPreview) return;
    final frames = preview.frames;
    final last = _index + 1 >= frames.length;
    if (!last) unawaited(_load(frames[_index + 1]));
    _step = Timer(_frameTime, () {
      if (!mounted || _playing != preview) return;
      if (last) return _finish(preview);
      setState(() => _index++);
      _next();
    });
  }

  /// Played through: the artwork comes back, until the card's left and come back to.
  void _finish(_Preview preview) {
    if (!mounted || _playing != preview || _played) return;
    _played = true;
    widget.onFinished?.call();
    _stop();
  }

  Future<void> _load(_TileFrame frame) async {
    try {
      await precacheImage(NetworkImage(frame.url, headers: jellyfin.authHeaders), context);
    } catch (_) {} // shows what it can
  }

  void _stop() {
    _wait?.cancel();
    _wait = null;
    _step?.cancel();
    _step = null;
    unawaited(_SharedPlayer.stop(this));
    if (!_shown) {
      if (_playing != null) setState(() => _playing = null);
      return;
    }
    // Fades out over what's showing, then lets it go.
    final preview = _playing;
    setState(() => _visible = false);
    _step = Timer(_fade, () {
      if (mounted && _playing == preview && !_shown) setState(() => _playing = null);
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final preview = _playing;
      return IgnorePointer(
        child: AnimatedOpacity(
          opacity: _shown ? 1 : 0,
          duration: _fade,
          child: switch (preview) {
            null => const SizedBox.expand(),
            _VideoPreview() => Video(
              controller: _SharedPlayer.video,
              controls: NoVideoControls,
              fit: BoxFit.cover,
              fill: const Color(0xFF000000),
              wakelock: false,
              subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
            ),
            _FramesPreview(:final frames) => ColoredBox(
              color: const Color(0xFF000000),
              // Each frame crossfades into the next.
              child: AnimatedSwitcher(
                duration: _crossfade,
                layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
                child: KeyedSubtree(
                  key: ValueKey(_index),
                  child: _Tile(frame: frames[_index], area: constraints.biggest),
                ),
              ),
            ),
          },
        ),
      );
    },
  );
}

/// One thumbnail of a trickplay sheet, covering [area]. The sheet is drawn at its own size,
/// scaled so one thumbnail is as big as it should show, slid so that thumbnail sits in view,
/// and clipped. Sized from the thumbnail's own pixels, so a sheet only partly filled (the last
/// one, or a short episode's) is never stretched to fit.
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
                  // At its natural size, [scale] making one thumbnail [w] across.
                  child: Image.network(
                    frame.url,
                    headers: jellyfin.authHeaders,
                    scale: frame.pixelWidth / w,
                    filterQuality: FilterQuality.medium,
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
