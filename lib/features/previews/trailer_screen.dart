import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../core/platform/keep_awake.dart';
import '../../core/platform/orientation.dart';
import '../../core/platform/screen_type.dart';
import '../../theme/theme.dart';
import '../screensaver/screensaver.dart';
import 'trailers.dart' show YouTubeView, hideYouTubeCaptions, youTubeParams;

/// A YouTube trailer, filling the screen, in YouTube's own player (youtube_player_iframe) with
/// its branding and no captions. Touch screens get YouTube's controls. With a remote or keyboard there are none:
/// OK or Play/Pause pauses and plays, ←/→ jump 10 seconds, and Back (or the trailer ending)
/// closes it. A slim progress bar shows over the bottom while it's paused and for a moment after
/// a key.
class YouTubeTrailerScreen extends StatefulWidget {
  const YouTubeTrailerScreen({super.key, required this.videoId});

  final String videoId;

  /// Opens [videoId]'s trailer over everything else.
  static Future<void> open(BuildContext context, String videoId) => Navigator.of(context, rootNavigator: true)
      .push(MaterialPageRoute(builder: (_) => YouTubeTrailerScreen(videoId: videoId)));

  @override
  State<YouTubeTrailerScreen> createState() => _YouTubeTrailerScreenState();
}

class _YouTubeTrailerScreenState extends State<YouTubeTrailerScreen> with WidgetsBindingObserver {
  YoutubePlayerController? _player;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _awake = KeepAwake();

  /// Where it's up to: seconds in, seconds long, and whether it's playing.
  double _time = 0;
  double _length = 0;
  bool _playing = true;

  /// Shows the progress bar for a moment after a key.
  Timer? _barTimer;
  bool _barAfterKey = false;

  @override
  void initState() {
    super.initState();
    screensaverBlocks.value++;
    WidgetsBinding.instance.addObserver(this);
    _awake.hold();
    AppOrientation.player(); // full screen, and free to turn on phones
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_player != null) return;
    // Touch screens need YouTube's controls; a remote has its keys.
    final player = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: youTubeParams(controls: ScreenType.of(context).isTouch, mute: false),
    );
    _player = player;
    _subscriptions
      ..add(player.listen((value) {
        if (!mounted) return;
        if (value.playerState == PlayerState.playing) hideYouTubeCaptions(player);
        if (value.playerState == PlayerState.ended) {
          Navigator.of(context).maybePop();
          return;
        }
        setState(() {
          _playing = value.playerState == PlayerState.playing;
          final length = value.metaData.duration.inMilliseconds / 1000;
          if (length > 0) _length = length;
        });
      }))
      ..add(player.videoStateStream.listen((state) {
        if (mounted) setState(() => _time = state.position.inMilliseconds / 1000);
      }));
  }

  @override
  void dispose() {
    _barTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    unawaited(_player?.close());
    screensaverBlocks.value--;
    WidgetsBinding.instance.removeObserver(this);
    _awake.release();
    AppOrientation.menus();
    super.dispose();
  }

  /// Leaving the app pauses the trailer; it stays paused on coming back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || state == AppLifecycleState.inactive) return;
    unawaited(_player?.pauseVideo());
  }

  Future<void> _seekBy(double seconds) async {
    final player = _player!;
    final now = await player.currentTime;
    await player.seekTo(seconds: (now + seconds).clamp(0, _length > 0 ? _length : double.infinity), allowSeekAhead: true);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final player = _player;
    if (player == null || (event is! KeyDownEvent && event is! KeyRepeatEvent)) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      unawaited(_playing ? player.pauseVideo() : player.playVideo());
    } else if (key == LogicalKeyboardKey.mediaPlay) {
      unawaited(player.playVideo());
    } else if (key == LogicalKeyboardKey.mediaPause) {
      unawaited(player.pauseVideo());
    } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.mediaRewind) {
      unawaited(_seekBy(-10));
    } else if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.mediaFastForward) {
      unawaited(_seekBy(10));
    } else {
      return KeyEventResult.ignored; // Back and the rest as usual
    }
    _showBar();
    return KeyEventResult.handled;
  }

  void _showBar() {
    _barTimer?.cancel();
    setState(() => _barAfterKey = true);
    _barTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _barAfterKey = false);
    });
  }

  static String _clock(double seconds) {
    final s = seconds.isFinite ? seconds.floor() : 0;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final touch = ScreenType.of(context).isTouch;
    final showBar = !touch && _length > 0 && (!_playing || _barAfterKey);
    const white = Color(0xFFFFFFFF);
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The whole screen, edge to edge (black bars only where the shapes differ).
            Center(
              // With a remote, YouTube's player isn't touched or focused: the keys above drive it.
              child: IgnorePointer(
                ignoring: !touch,
                child: AspectRatio(aspectRatio: 16 / 9, child: YouTubeView(controller: _player!)),
              ),
            ),
            // With a remote or keyboard: over the bottom of the video, for a moment after a key
            // and while paused.
            if (!touch)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: showBar ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xCC000000), Color(0x00000000)],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(48, 48, 48, 32),
                        child: Row(
                          spacing: 16,
                          children: [
                            Icon(_playing ? Icons.play_arrow_rounded : Icons.pause_rounded, color: white),
                            Text(_clock(_time), style: context.text.bodyMedium?.copyWith(color: white)),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: _length > 0 ? (_time / _length).clamp(0.0, 1.0) : 0,
                                  minHeight: 4,
                                  color: white,
                                  backgroundColor: const Color(0x40FFFFFF),
                                ),
                              ),
                            ),
                            Text(_clock(_length), style: context.text.bodyMedium?.copyWith(color: white)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
