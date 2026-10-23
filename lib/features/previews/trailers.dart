import 'dart:async';

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../core/jellyfin/jellyfin_controller.dart';

// Trailers, for the Trailer button on a title's page: one on the server first; without one, the
// YouTube trailer Jellyfin knows of, in YouTube's own player (YouTubeTrailerScreen).

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
