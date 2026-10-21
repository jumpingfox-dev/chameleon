import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';

import '../playback/playback_engine.dart';
import 'keep_awake.dart';

/// The video's own Android surface, behind the Flutter view, which the hardware decoder draws on
/// directly (mpv's mediacodec_embed, or ExoPlayer). Unlike media_kit's `Video` widget, which draws frames as a
/// Flutter texture in SDR, the display gets them as they are, so HDR plays as HDR.
///
/// [VideoSurfaceView] marks where the video goes and leaves that part of the screen see-through.
/// See android/.../VideoSurface.kt for the native half.
class VideoSurface {
  VideoSurface._(this._player);

  static const _channel = MethodChannel('chameleon/video_surface');

  /// The one showing now. There's only ever one player.
  static VideoSurface? _current;

  /// mpv, when it's mpv drawing here; null for ExoPlayer, which looks after the surface itself.
  final Player? _player;
  NativePlayer get _mpv => _player!.platform as NativePlayer;
  bool _released = false;
  Rect? _placed;
  StreamSubscription<VideoParams>? _params;

  /// mpv's handle to the surface, or 0 while there's none (in the background, say).
  int _surface = 0;

  /// Whether mpv has opened a video and knows its size.
  bool _sized = false;

  /// The surface handle mpv draws on now, or 0.
  int _connected = 0;

  /// Connecting runs one step at a time, in order.
  Future<void> _steps = Future.value();

  /// Puts a surface behind the Flutter view and has [player] draw its video there, with the
  /// hardware decoder. Let go of along with [player], when it's disposed.
  static Future<VideoSurface> attach(Player player) async {
    final surface = VideoSurface._(player);
    _current = surface;
    _channel.setMethodCallHandler(_onCall);
    player.platform?.release.add(surface._release);
    // Decoding, with nowhere to draw yet: the surface is connected once the video's open.
    await surface._set({'vo': 'null', 'hwdec': 'mediacodec', 'vid': 'auto'});
    surface._params = player.stream.videoParams.listen((params) {
      if ((params.dw ?? 0) > 0 && !surface._sized) {
        surface._sized = true;
        surface._update();
      }
    });
    // Usually 0: the surface turns up a moment later, as a "surface" call.
    surface._surface = await _channel.invokeMethod<int>('attach') ?? 0;
    surface._update();
    return surface;
  }

  /// Puts a surface behind the Flutter view for ExoPlayer (see ExoEngine.kt) to draw on.
  /// Let go of with [release].
  static Future<VideoSurface> attachForExo() async {
    final surface = VideoSurface._(null);
    _current = surface;
    _channel.setMethodCallHandler(_onCall);
    await _channel.invokeMethod<int>('attach');
    return surface;
  }

  static Future<void> _onCall(MethodCall call) async {
    final surface = _current;
    if (call.method != 'surface' || surface == null) return;
    surface._surface = call.arguments as int;
    surface._update();
  }

  void _update() => _steps = _steps.then((_) => _connect());

  /// Points mpv at the surface once there is one and the video is open, or away from it when
  /// the surface goes (the app went to the background). In the order media_kit's own Android
  /// output uses, which hardware decoders are known to cope with: connecting before the file
  /// is open can leave the decoder stuck after the jump to where the video resumes.
  Future<void> _connect() async {
    if (_released || _player == null) return;
    final target = _sized ? _surface : 0;
    if (target == _connected) return;
    // vo off before wid changes.
    await _set({'vo': 'null'});
    _connected = target;
    if (target == 0) {
      await _set({'wid': '0', if (_surface == 0) 'vid': 'no'});
      return;
    }
    final player = _player;
    final params = player.state.videoParams;
    await _set({
      'android-surface-size': '${params.dw ?? 1}x${params.dh ?? 1}',
      'wid': '$target',
      'vo': 'mediacodec_embed',
      'vid': 'auto',
    });
    // Picks the picture up where it is, rather than waiting for the next keyframe.
    await player.seek(player.state.position);
  }

  Future<void> _set(Map<String, String> properties) async {
    try {
      for (final MapEntry(:key, :value) in properties.entries) {
        await _mpv.setProperty(key, value, waitForInitialization: false);
      }
    } catch (e) {
      debugPrint('Video surface: $e'); // the player's already gone
    }
  }

  /// Moves the surface to [rect], in physical pixels of the Flutter view.
  void _place(Rect rect) {
    if (_released || rect == _placed) return;
    _placed = rect;
    unawaited(_channel.invokeMethod('place', {
      'left': rect.left.round(),
      'top': rect.top.round(),
      'width': rect.width.round(),
      'height': rect.height.round(),
    }));
  }

  /// Takes the surface away while mpv carries on (it stops drawing first), for a switch to
  /// ExoPlayer; or, for ExoPlayer's surface, when it's done.
  Future<void> release() async {
    if (_released) return;
    if (_player != null) {
      await _steps;
      await _set({'vo': 'null', 'wid': '0', 'vid': 'no'});
    }
    await _release();
  }

  /// The player is going: take the surface away. mpv has stopped by now.
  Future<void> _release() async {
    if (_released) return;
    _released = true;
    await _params?.cancel();
    if (_current == this) _current = null;
    await _channel.invokeMethod('detach');
  }
}

/// Where [surface]'s video shows: [fit] into this widget's area, like media_kit's `Video`.
/// Paints nothing, so the video behind shows through; whatever's drawn over it (subtitles,
/// controls) shows on top as usual. Like `Video`, keeps the screen on while it plays.
class VideoSurfaceView extends StatefulWidget {
  const VideoSurfaceView({super.key, required this.surface, required this.player, required this.fit});

  final VideoSurface surface;
  final PlaybackEngine player;
  final BoxFit fit;

  @override
  State<VideoSurfaceView> createState() => _VideoSurfaceViewState();
}

class _VideoSurfaceViewState extends State<VideoSurfaceView> {
  final _awake = KeepAwake();
  late final StreamSubscription<bool> _playing;

  @override
  void initState() {
    super.initState();
    if (widget.player.state.playing) _awake.hold();
    _playing = widget.player.stream.playing.listen((playing) => playing ? _awake.hold() : _awake.release());
  }

  @override
  void dispose() {
    _playing.cancel();
    _awake.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<VideoParams>(
    stream: widget.player.stream.videoParams,
    initialData: widget.player.state.videoParams,
    builder: (context, snapshot) {
      final params = snapshot.data;
      // Sideways videos (a phone's portrait clip, say) swap width and height.
      final turned = params?.rotate == 90 || params?.rotate == 270;
      final width = (turned ? params?.dh : params?.dw) ?? 0;
      final height = (turned ? params?.dw : params?.dh) ?? 0;
      return LayoutBuilder(
        builder: (context, constraints) {
          final area = constraints.biggest;
          final fit = widget.fit;
          var video = area;
          if (width > 0 && height > 0) {
            // The whole picture, scaled: when filling the screen it's bigger than [area], and the
            // surface hangs off the edges (only the part on screen shows).
            final size = Size(width.toDouble(), height.toDouble());
            final fitted = applyBoxFit(fit, size, area);
            video = Size(
              size.width * fitted.destination.width / fitted.source.width,
              size.height * fitted.destination.height / fitted.source.height,
            );
          }
          final local = Alignment.center.inscribe(video, Offset.zero & area);
          final ratio = View.of(context).devicePixelRatio;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            final box = context.findRenderObject() as RenderBox?;
            if (box == null || !box.hasSize) return;
            // In the window's own pixels, past any scaling of the app (UiScaler).
            final topLeft = box.localToGlobal(local.topLeft);
            final bottomRight = box.localToGlobal(local.bottomRight);
            widget.surface._place(Rect.fromPoints(topLeft * ratio, bottomRight * ratio));
          });
          return const SizedBox.expand();
        },
      );
    },
  );
}
