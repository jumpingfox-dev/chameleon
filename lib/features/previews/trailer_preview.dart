import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../core/jellyfin/jellyfin_controller.dart';
import '../player/playback_settings.dart';

// Trailer previews: after a card has been focused (or hovered) for a moment, its artwork turns
// into the title's trailer, playing on a loop until focus moves on. A trailer on the server
// comes first; without one, the YouTube trailer Jellyfin knows of (Android only).

/// Where a title's trailer comes from.
sealed class Trailer {
  const Trailer();
}

/// A trailer stored on the server, as an item of its own.
class ServerTrailer extends Trailer {
  const ServerTrailer(this.itemId);
  final String itemId;
  String get url => jellyfin.streamUrl(itemId);
}

/// The YouTube trailer Jellyfin found online.
class YouTubeTrailer extends Trailer {
  const YouTubeTrailer(this.videoId);
  final String videoId;
  String get watchUrl => 'https://www.youtube.com/watch?v=$videoId';
}

/// Each title's trailer, looked up once per run.
final _trailers = <String, Future<Trailer?>>{};

/// [item]'s trailer: one on the server first, otherwise its YouTube trailer, or null.
Future<Trailer?> trailerFor(JellyfinItem item) => _trailers[item.id] ??= _lookUp(item);

Future<Trailer?> _lookUp(JellyfinItem item) async {
  final client = jellyfin.client;
  if (client == null) return null;
  try {
    final local = await jellyfin.getJson(
      '/Items/${item.id}/LocalTrailers',
      query: {'userId': client.userId!},
      timeout: const Duration(seconds: 5),
    );
    if (local is List && local.isNotEmpty && local.first is Map && local.first['Id'] is String) {
      return ServerTrailer(local.first['Id'] as String);
    }
    // The full item, for the trailers Jellyfin found online (lists leave them out).
    final full = await client.items.byId(item.id);
    for (final trailer in (full?.raw['RemoteTrailers'] as List?) ?? const []) {
      final id = trailer is Map ? youTubeId(trailer['Url'] as String?) : null;
      if (id != null) return YouTubeTrailer(id);
    }
  } catch (e) {
    debugPrint('Trailer for ${item.id}: $e');
    _trailers.remove(item.id); // try again next time
  }
  return null;
}

/// The video id in a YouTube address (youtube.com/watch?v=…, youtu.be/…, /embed/…, /shorts/…),
/// or null if it isn't one.
@visibleForTesting
String? youTubeId(String? url) {
  final uri = url == null ? null : Uri.tryParse(url.trim());
  if (uri == null) return null;
  final host = uri.host.toLowerCase().replaceFirst('www.', '').replaceFirst('m.', '');
  String? id;
  if (host == 'youtu.be') {
    id = uri.pathSegments.firstOrNull;
  } else if (host.endsWith('youtube.com') || host.endsWith('youtube-nocookie.com')) {
    final segments = uri.pathSegments;
    id = uri.queryParameters['v'] ??
        (segments.length >= 2 && const {'embed', 'shorts', 'v'}.contains(segments.first) ? segments[1] : null);
  }
  return id != null && RegExp(r'^[A-Za-z0-9_-]{6,20}$').hasMatch(id) ? id : null;
}

/// The one player for trailers on the server, shared by every card: only one previews at a time.
class _SharedPlayer {
  static Player? _player;
  static VideoController? _video;
  static Object? _owner;

  /// Tells whose trailer just played to the end (and started over).
  static final finished = StreamController<Object>.broadcast();
  static Duration _last = Duration.zero;

  static VideoController get video {
    if (_player == null) {
      _player = Player(configuration: const PlayerConfiguration(bufferSize: 16 * 1024 * 1024))
        ..setPlaylistMode(PlaylistMode.single); // loops
      // Looping back to the start: it's played through once.
      _player!.stream.position.listen((position) {
        final owner = _owner;
        if (owner != null && _last > const Duration(seconds: 2) && position < _last - const Duration(seconds: 2)) {
          finished.add(owner);
        }
        _last = position;
      });
    }
    return _video ??= VideoController(_player!);
  }

  /// Plays [url] for [owner], and returns once it's moving (true), or false if another card
  /// took over or [owner] stopped it meanwhile.
  static Future<bool> play(Object owner, String url, {required bool sound}) async {
    video; // make sure both exist
    final player = _player!;
    _owner = owner;
    _last = Duration.zero;
    await player.setVolume(sound ? 100 : 0);
    await player.open(Media(url, httpHeaders: jellyfin.authHeaders));
    if (_owner != owner) return false; // stopped while it was opening
    // Moving: its own frames are coming, not the last trailer's.
    await player.stream.position.firstWhere((p) => p > Duration.zero).timeout(const Duration(seconds: 15));
    return _owner == owner;
  }

  /// Stops, if [owner] is still the one playing (another card may have taken over).
  static Future<void> stop(Object owner) async {
    if (_owner != owner) return;
    _owner = null;
    await _player?.stop();
  }

}

/// A card's trailer preview, laid over its artwork. Starts once [active] (the card focused or
/// hovered) has held for the delay from Settings, and stops as soon as it's not. Shows nothing
/// until the trailer is actually playing, so a card without one looks just as before.
class TrailerPreview extends StatefulWidget {
  const TrailerPreview({
    super.key,
    required this.item,
    required this.active,
    this.fill = false,
    this.onShowing,
    this.onFinished,
  });

  final JellyfinItem item;
  final bool active;

  /// True: the trailer fills the space, cropping what doesn't fit (the carousel). False: it
  /// fits inside whole, letterboxed in black (cards, which are often posters).
  final bool fill;

  /// Told when the trailer appears (true) and goes (false).
  final ValueChanged<bool>? onShowing;

  /// Told once the trailer has played all the way through (it then starts over).
  final VoidCallback? onFinished;

  /// Titles that can have trailers.
  static bool supports(JellyfinItem item) =>
      item.type == JellyfinItemKind.movie || item.type == JellyfinItemKind.series;

  @override
  State<TrailerPreview> createState() => _TrailerPreviewState();
}

class _TrailerPreviewState extends State<TrailerPreview> with WidgetsBindingObserver {
  Timer? _wait;
  Trailer? _trailer; // the one showing (or about to)
  bool _shown = false;
  bool get _visible => _shown;
  set _visible(bool value) {
    if (value == _shown) return;
    _shown = value;
    // After this frame: this can change while the parent is building (see didUpdateWidget).
    final onShowing = widget.onShowing;
    if (onShowing != null) WidgetsBinding.instance.addPostFrameCallback((_) => onShowing(value));
  }

  /// Whether [TrailerPreview.onFinished] has been called for the trailer showing now.
  bool _toldFinished = false;
  StreamSubscription<Object>? _serverFinished;

  /// It's played through once: says so, the first time.
  void _finished() {
    if (_toldFinished || !mounted) return;
    _toldFinished = true;
    widget.onFinished?.call();
  }

  @override
  void initState() {
    super.initState();
    _serverFinished = _SharedPlayer.finished.stream.listen((owner) {
      if (owner == this) _finished();
    });
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) _schedule();
  }

  /// Leaving the app stops the preview (nothing plays out of sight). Back in the app, it starts
  /// over after the usual moment if the card is still focused.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (widget.active && _wait == null && _trailer == null) _schedule();
    } else if (state != AppLifecycleState.inactive) {
      _stop();
    }
  }

  @override
  void didUpdateWidget(TrailerPreview old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active && widget.item.id == old.item.id) return;
    _stop();
    if (widget.active) _schedule();
  }

  @override
  void dispose() {
    _wait?.cancel();
    _serverFinished?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_SharedPlayer.stop(this));
    super.dispose();
  }

  void _schedule() {
    final s = playbackSettings;
    if (!s.previews || !TrailerPreview.supports(widget.item)) return;
    _wait = Timer(Duration(seconds: s.previewDelay), _start);
  }

  Future<void> _start() async {
    final trailer = await trailerFor(widget.item);
    if (!mounted || !widget.active || trailer == null) return;
    switch (trailer) {
      case ServerTrailer(:final url):
        setState(() => _trailer = trailer);
        try {
          final playing = await _SharedPlayer.play(this, url, sound: playbackSettings.previewSound);
          if (playing && mounted && widget.active) setState(() => _visible = true);
        } catch (e) {
          debugPrint('Trailer preview: $e'); // couldn't play, or never started: the artwork stays
        }
      case YouTubeTrailer():
        // A web page in a card: Android (and iOS) only. Elsewhere, server trailers only.
        if (!playbackSettings.previewYouTube || kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
        setState(() => _trailer = trailer); // shown once it reports it's playing
    }
  }

  void _stop() {
    _wait?.cancel();
    _wait = null;
    _toldFinished = false;
    if (_trailer is ServerTrailer) unawaited(_SharedPlayer.stop(this));
    if (_trailer != null || _visible) {
      setState(() {
        _trailer = null;
        _visible = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final trailer = _trailer;
    if (trailer == null) return const SizedBox.shrink();
    final Widget player = switch (trailer) {
      ServerTrailer() => Video(
        controller: _SharedPlayer.video,
        controls: NoVideoControls,
        fit: widget.fill ? BoxFit.cover : BoxFit.contain,
        fill: const Color(0xFF000000),
        wakelock: false,
        subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
      ),
      YouTubeTrailer(:final videoId) => _YouTubePreview(
        videoId: videoId,
        fill: widget.fill,
        sound: playbackSettings.previewSound,
        onEnded: _finished,
        onPlaying: () {
          if (mounted && widget.active) setState(() => _visible = true);
        },
      ),
    };
    return IgnorePointer(
      child: ExcludeFocus(
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 500),
          child: player,
        ),
      ),
    );
  }
}

/// A YouTube trailer in YouTube's embedded player (youtube_player_iframe), looping, muted unless
/// Settings says otherwise, without controls or captions. YouTube's own title, logo and branding
/// show as YouTube draws them. The player fits whole inside the space, letterboxed in black, or
/// with [fill], covers it. It can't be touched or focused, so the remote never ends up in it.
class _YouTubePreview extends StatefulWidget {
  const _YouTubePreview({
    required this.videoId,
    required this.fill,
    required this.sound,
    required this.onPlaying,
    required this.onEnded,
  });

  final String videoId;
  final bool fill;
  final bool sound;
  final VoidCallback onPlaying;
  final VoidCallback onEnded;

  @override
  State<_YouTubePreview> createState() => _YouTubePreviewState();
}

class _YouTubePreviewState extends State<_YouTubePreview> {
  late final YoutubePlayerController _player;
  StreamSubscription<YoutubePlayerValue>? _states;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _player = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: youTubeParams(controls: false, mute: !widget.sound),
    );
    _states = _player.listen((value) {
      switch (value.playerState) {
        case PlayerState.playing:
          hideYouTubeCaptions(_player);
          if (!_started) {
            _started = true;
            widget.onPlaying();
          }
        case PlayerState.ended:
          widget.onEnded();
          // The player's own loop setting doesn't repeat a single video.
          unawaited(_player.seekTo(seconds: 0, allowSeekAhead: true));
          unawaited(_player.playVideo());
        default:
      }
    });
  }

  @override
  void dispose() {
    _states?.cancel();
    unawaited(_player.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF000000),
    child: LayoutBuilder(
      builder: (context, constraints) {
        // 16:9, as large as fits whole, or (filling) as small as covers the space.
        final area = constraints.biggest;
        final width = widget.fill
            ? math.max(area.width, area.height * 16 / 9)
            : math.min(area.width, area.height * 16 / 9);
        return ClipRect(
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: SizedBox(
              width: width,
              height: width * 9 / 16,
              child: YouTubeView(controller: _player),
            ),
          ),
        );
      },
    ),
  );
}

/// [controller]'s player, drawn right here in the page.
///
/// Not the package's own `YoutubePlayer` widget: on Android and iOS it draws the player in an
/// overlay above the whole page (for its fullscreen handling), so it would cover whatever is
/// meant to sit on top of it (the carousel's text and buttons) and spill past rounded corners.
class YouTubeView extends StatefulWidget {
  const YouTubeView({super.key, required this.controller});

  final YoutubePlayerController controller;

  @override
  State<YouTubeView> createState() => _YouTubeViewState();
}

class _YouTubeViewState extends State<YouTubeView> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.webViewController.setBackgroundColor(const Color(0xFF000000)));
    // Loads the player page, then the video. (The public way in for wrappers like this one.)
    unawaited(widget.controller.initWithParams(params: widget.controller.params));
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: widget.controller.webViewController);
}

/// The settings both trailer players use: no captions, annotations, fullscreen button or
/// suggestions from other channels, and [controls] only where they're needed (touch screens).
YoutubePlayerParams youTubeParams({required bool controls, required bool mute}) => YoutubePlayerParams(
  mute: mute,
  showControls: controls,
  enableKeyboard: controls,
  enableCaption: false,
  showVideoAnnotations: false,
  showFullscreenButton: false,
  strictRelatedVideos: true,
  pointerEvents: controls ? PointerEvents.auto : PointerEvents.none,
  // Who's embedding the player, for YouTube: the app's own address (it isn't a web page).
  origin: 'https://dev.jumpingfox.chameleon',
);

/// YouTube's Terms of Service and Google's Privacy Policy, which apply to the trailers played
/// from YouTube.
const youTubeTermsUrl = 'https://www.youtube.com/t/terms';
const googlePrivacyUrl = 'https://policies.google.com/privacy';

/// Captions can come on by themselves despite the setting (the viewer's region, or the video's
/// own settings), so they're switched off again once it's playing.
void hideYouTubeCaptions(YoutubePlayerController player) => unawaited(
  player.webViewController
      .runJavaScript("try { player.unloadModule('captions'); player.unloadModule('cc'); } catch (e) {}")
      .catchError((Object _) {}),
);
