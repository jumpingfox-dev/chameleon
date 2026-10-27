import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_jellyfin/dart_jellyfin.dart' show JellyfinItem, JellyfinItemKind;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:http/http.dart' as http;

import '../../features/player/playback_settings.dart';
import '../format/format.dart';
import '../jellyfin/jellyfin_controller.dart';

/// Chromecast support, on Android and iOS phones and tablets.
///
/// Videos are cast to Google's standard receiver as an HLS stream from Jellyfin, at the best
/// quality the Chromecast takes ([CastQuality]): 4K first for a file bigger than 1080p (its
/// HEVC or H.264 passed straight through), then 1080p, then 720p, both H.264. If the Chromecast
/// can't play one (it says so, or hasn't started in a while), the next one down is tried from
/// the same spot. Jellyfin only converts what it has to; the sound is AAC.
///
/// Text subtitles are sent alongside as WebVTT and can be switched instantly, styled like the
/// app's (see [castSubtitleStyle]); picture subtitles (PGS, DVD) are drawn into the video by
/// Jellyfin, which means reloading.
///
/// While casting, this reports playback to Jellyfin itself, so "Continue watching" and
/// watched status stay right.
class CastController extends ChangeNotifier {
  /// Whether this device can cast at all (Android or iOS, with the Cast SDK set up).
  bool supported = false;

  /// Chromecasts found on the network. The cast button only appears when there's one.
  List<GoogleCastDevice> devices = const [];

  GoogleCastSession? _session;
  bool get isConnected => _session?.connectionState == GoogleCastConnectState.connected;
  bool get isConnecting => _session?.connectionState == GoogleCastConnectState.connecting;
  String? get deviceName => _session?.device?.friendlyName;

  /// What's playing on the Chromecast, if it came from this app.
  CastNowPlaying? nowPlaying;

  /// Playing, paused, buffering… as the Chromecast reports it.
  CastMediaPlayerState playerState = CastMediaPlayerState.unknown;

  /// The last position the Chromecast reported for [nowPlaying]. Kept after casting stops,
  /// so the phone can carry on from the same spot.
  Duration lastPosition = Duration.zero;
  bool get isPlaying =>
      playerState == CastMediaPlayerState.playing || playerState == CastMediaPlayerState.buffering;

  final _subscriptions = <StreamSubscription<Object?>>[];
  Timer? _progressTimer;

  /// Call once at startup, before runApp. Does nothing on platforms without Cast.
  Future<void> init() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      const appId = GoogleCastDiscoveryCriteria.kDefaultApplicationId; // Google's standard receiver
      final options = Platform.isIOS
          ? IOSGoogleCastOptions(
              GoogleCastDiscoveryCriteriaInitialize.initWithApplicationID(appId),
              stopCastingOnAppTerminated: false, // keep playing on the TV if the app closes
            )
          : GoogleCastOptionsAndroid(appId: appId, stopCastingOnAppTerminated: false);
      await GoogleCastContext.instance.setSharedInstanceWithOptions(options);

      _subscriptions
        ..add(
          GoogleCastDiscoveryManager.instance.devicesStream.listen((found) {
            devices = found;
            notifyListeners();
          }),
        )
        ..add(GoogleCastSessionManager.instance.currentSessionStream.listen(_onSession))
        ..add(GoogleCastRemoteMediaClient.instance.mediaStatusStream.listen(_onStatus))
        ..add(
          GoogleCastRemoteMediaClient.instance.playerPositionStream.listen((p) {
            if (nowPlaying != null && p > Duration.zero) lastPosition = p;
          }),
        );
      // Look for Chromecasts on the network. (iOS starts looking by itself; Android only once
      // asked, so without this a phone never finds one and never shows the cast button.)
      unawaited(GoogleCastDiscoveryManager.instance.startDiscovery().catchError((Object _) {}));
      supported = true;
      notifyListeners();
    } catch (_) {
      // Unavailable, e.g. no Google Play services: there's just no cast button.
    }
  }

  void _onSession(GoogleCastSession? session) {
    final wasConnected = isConnected;
    _session = session;
    if (wasConnected && !isConnected) _finishReporting();
    notifyListeners();
  }

  void _onStatus(GoggleCastMediaStatus? status) {
    final state = status?.playerState ?? CastMediaPlayerState.unknown;
    if (state == playerState) return;
    playerState = state;
    if ((state == CastMediaPlayerState.playing || state == CastMediaPlayerState.paused) && !_playing) {
      _playing = true;
      _sendSubtitleStyle(); // the Chromecast takes a style once the video's loaded
    }
    // Finished, or stopped from the TV's own remote. ("Interrupted" is just a reload,
    // e.g. after changing audio, so it doesn't count.)
    final reason = status?.idleReason;
    final ended = reason == GoogleCastMediaIdleReason.finished ||
        reason == GoogleCastMediaIdleReason.cancelled ||
        reason == GoogleCastMediaIdleReason.error;
    // Only once this video has actually played: a Chromecast reports idle for a moment while
    // it loads, and that isn't the end.
    if (state == CastMediaPlayerState.idle && ended && nowPlaying != null && _playing) {
      _finishReporting();
    } else if (state == CastMediaPlayerState.idle && reason == GoogleCastMediaIdleReason.error && !_playing) {
      _couldNotPlay();
    }
    if (_playing) _startTimer?.cancel();
    notifyListeners();
  }

  /// The Chromecast couldn't play the stream it was sent: the next quality down, from the same
  /// spot; or, with none left, the player goes back to playing here and says why.
  void _couldNotPlay() {
    _startTimer?.cancel();
    final attempt = _attempt;
    if (attempt == null) return;
    final lower = attempt.quality.lower;
    if (lower != null) {
      debugPrint('Cast: ${attempt.quality.name} didn\'t play, trying ${lower.name}');
      unawaited(_stopConverting(attempt.playSessionId));
      unawaited(_load(attempt.item, attempt.start, attempt.audioStreamIndex, attempt.subtitleStreamIndex, lower));
      return;
    }
    error = "The Chromecast couldn't play this. Make sure it can reach your server.";
    _finishReporting();
    notifyListeners();
  }

  /// Changing the subtitle settings while casting restyles them on the Chromecast too.
  bool _followingSubtitleStyle = false;

  /// Sets the subtitle style on the Chromecast: through the app's own native code (see
  /// CastStyle.kt and AppDelegate.swift), as flutter_chrome_cast 1.5 doesn't pass styles on;
  /// and through the plugin too, for when a version of it does.
  void _sendSubtitleStyle() {
    if (nowPlaying == null || !isConnected) return;
    final s = playbackSettings;
    unawaited(
      _styleChannel
          .invokeMethod<bool>('set', {
            'edge': switch (s.subtitleBackground) {
              SubtitleBackground.shadow => 'dropShadow',
              SubtitleBackground.outline => 'outline',
              SubtitleBackground.box => 'none',
            },
            'edgeColor': 0xFF000000,
            'foreground': s.subtitleColor.color.toARGB32(),
            'background': s.subtitleBackground == SubtitleBackground.box ? 0xB3000000 : 0x00000000,
            'scale': s.subtitleSize.scale,
            'font': castFontFamilyOf(s.subtitleFont).name,
          })
          .catchError((Object e) {
            debugPrint('Cast subtitle style: $e');
            return false;
          }),
    );
    unawaited(
      GoogleCastRemoteMediaClient.instance
          .setTextTrackStyle(castSubtitleStyle(s))
          .catchError((Object _) {}), // not on Android or iOS yet (see above)
    );
  }

  static const _styleChannel = MethodChannel('chameleon/cast_style');

  /// What was last sent to the Chromecast, to try again at a lower quality.
  _CastAttempt? _attempt;

  /// Gives a stream a while to start playing before trying a lower quality.
  Timer? _startTimer;

  /// Stops the server converting a stream the Chromecast won't play.
  Future<void> _stopConverting(String playSessionId) async {
    final base = jellyfin.client?.baseUrl;
    if (base == null) return;
    try {
      await http
          .delete(
            Uri.parse('$base/Videos/ActiveEncodings').replace(
              queryParameters: {'deviceId': _deviceId, 'playSessionId': playSessionId},
            ),
            headers: jellyfin.authHeaders,
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // The server ends abandoned conversions by itself after a while.
    }
  }

  static const _deviceId = 'chameleon-cast';

  /// This video has started playing on the Chromecast (since [load]).
  bool _playing = false;

  /// Why the last video couldn't be played on the Chromecast, for the player to show. Cleared
  /// on the next [load].
  String? error;

  /// The server's address as a Chromecast can use it. A Chromecast usually can't look up
  /// `.local` names (nas.local), so for those it's the server's own local address instead, as
  /// the server reports it.
  Future<String> _castBase(String base) async {
    final host = Uri.tryParse(base)?.host ?? '';
    if (!host.endsWith('.local')) return base;
    if (_castBaseFor case (final from, final to) when from == base) return to;
    try {
      final info = await jellyfin.getJson('/System/Info/Public', auth: false);
      final local = (info as Map)['LocalAddress'] as String?;
      if (local != null && local.isNotEmpty) {
        final resolved = local.replaceAll(RegExp(r'/+$'), '');
        _castBaseFor = (base, resolved);
        return resolved;
      }
    } catch (_) {
      // Couldn't ask: try the address as it is.
    }
    return base;
  }

  (String, String)? _castBaseFor;

  // ─── Connecting ──────────────────────────────────────────────────────────

  Future<void> connect(GoogleCastDevice device) async {
    await GoogleCastSessionManager.instance.startSessionWithDevice(device);
  }

  /// Stops casting and disconnects. Playback on the TV stops too.
  Future<void> disconnect() async {
    await _finishReporting();
    await GoogleCastSessionManager.instance.endSessionAndStopCasting();
  }

  // ─── Playing ─────────────────────────────────────────────────────────────

  /// Where the Chromecast is in the video.
  Stream<Duration> get positionStream => GoogleCastRemoteMediaClient.instance.playerPositionStream;
  Duration get position => GoogleCastRemoteMediaClient.instance.playerPosition;

  /// Starts [item] on the connected Chromecast at [start], with the given Jellyfin stream
  /// indexes (null audio = the file's default; null subtitles = off).
  Future<void> load(
    JellyfinItem item, {
    Duration start = Duration.zero,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) {
    // The same video again (other sound or subtitles): the quality that's playing. Otherwise
    // the best there is: 4K for a file bigger than 1080p, unless picture subtitles are to be
    // drawn in (which would mean converting all of it at 4K).
    final now = _attempt;
    final CastQuality quality;
    if (now != null && now.item.id == item.id && _playing) {
      quality = now.quality;
    } else {
      final source = (item.raw['MediaSources'] as List?)?.firstOrNull as Map?;
      final streams = (source?['MediaStreams'] as List?) ?? (item.raw['MediaStreams'] as List?) ?? const [];
      final video = streams.whereType<Map>().where((s) => s['Type'] == 'Video').firstOrNull;
      final picture = subtitleStreamIndex != null &&
          streams.whereType<Map>().any((s) => s['Index'] == subtitleStreamIndex && s['IsTextSubtitleStream'] == false);
      final big = ((video?['Width'] as int?) ?? 0) > 1920 || ((video?['Height'] as int?) ?? 0) > 1080;
      quality = big && !picture ? CastQuality.uhd : CastQuality.fullHd;
    }
    return _load(item, start, audioStreamIndex, subtitleStreamIndex, quality);
  }

  Future<void> _load(
    JellyfinItem item,
    Duration start,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    CastQuality quality,
  ) async {
    final client = jellyfin.client;
    final serverBase = client?.baseUrl;
    final token = client?.token;
    if (!isConnected || serverBase == null || token == null) return;
    final base = await _castBase(serverBase); // what the Chromecast fetches from
    error = null;
    _playing = false;

    final previous = nowPlaying;
    if (previous != null && previous.itemId != item.id) await _finishReporting();

    final source = (item.raw['MediaSources'] as List?)?.firstOrNull as Map?;
    final mediaSourceId = (source?['Id'] as String?) ?? item.id;
    final streams = [
      for (final s in (source?['MediaStreams'] as List?) ?? (item.raw['MediaStreams'] as List?) ?? const [])
        if (s is Map<String, dynamic>) s,
    ];
    final subtitle = subtitleStreamIndex == null
        ? null
        : streams.where((s) => s['Type'] == 'Subtitle' && s['Index'] == subtitleStreamIndex).firstOrNull;
    final textSubtitle = subtitle != null && subtitle['IsTextSubtitleStream'] != false;
    // The same stream again (other sound or subtitles) keeps its session; a new video, or another
    // quality (whose failed conversion is being stopped), gets its own.
    final sameStream = previous?.itemId == item.id && _attempt?.quality == quality;
    final playSessionId = sameStream ? previous!.playSessionId : randomHexId();

    // ── The stream: HLS at [quality], AAC sound, picture subtitles burned in ──
    final url = Uri.parse('$base/Videos/${item.id}/master.m3u8').replace(
      queryParameters: {
        'MediaSourceId': mediaSourceId,
        'DeviceId': _deviceId,
        'PlaySessionId': playSessionId,
        ...tokenQuery(token),
        'VideoCodec': quality.videoCodecs,
        'AudioCodec': 'aac,mp3',
        'AllowVideoStreamCopy': 'true',
        'AllowAudioStreamCopy': 'true',
        'TranscodingMaxAudioChannels': '2',
        'MaxStreamingBitrate': '${quality.maxBitrate}',
        // What anything converted is made at: the file's own rate within the limit (left out,
        // the server converts at a very low rate).
        'VideoBitrate': '${transcodeVideoBitrate(item, limit: quality.maxBitrate)}',
        'AudioBitrate': '192000',
        'MaxWidth': '${quality.maxWidth}',
        'MaxHeight': '${quality.maxHeight}',
        if (quality.profile case final profile?) ...{'Profile': profile, 'Level': '41'},
        'SegmentContainer': quality.fmp4 ? 'mp4' : 'ts',
        'BreakOnNonKeyFrames': 'true',
        if (audioStreamIndex != null) 'AudioStreamIndex': '$audioStreamIndex',
        if (subtitle != null && !textSubtitle) ...{
          'SubtitleStreamIndex': '$subtitleStreamIndex',
          'SubtitleMethod': 'Encode',
        },
      },
    );

    // ── Text subtitles, sent alongside so they can be switched without reloading ──
    final tracks = [
      for (final s in streams)
        if (s['Type'] == 'Subtitle' && s['IsTextSubtitleStream'] != false && s['Index'] is int)
          GoogleCastMediaTrack(
            trackId: _trackId(s['Index'] as int),
            type: TrackType.text,
            subtype: TextTrackType.subtitles,
            trackContentType: 'text/vtt',
            trackContentId:
                Uri.parse('$base/Videos/${item.id}/$mediaSourceId/Subtitles/${s['Index']}/0/Stream.vtt')
                    .replace(queryParameters: tokenQuery(token))
                    .toString(),
            name: (s['DisplayTitle'] as String?) ?? (s['Language'] as String?) ?? 'Subtitles',
          ),
    ];

    final isEpisode = item.type == JellyfinItemKind.episode;
    final title = isEpisode
        ? [
            (item.raw['SeriesName'] as String?) ?? '',
            if (item.raw['ParentIndexNumber'] != null && item.raw['IndexNumber'] != null)
              'S${item.raw['ParentIndexNumber']}:E${item.raw['IndexNumber']}',
            item.name,
          ].where((p) => p.isNotEmpty).join(' · ')
        : item.name;
    final imageTag = item.imageTags['Primary'];

    nowPlaying = CastNowPlaying(
      itemId: item.id,
      title: title,
      mediaSourceId: mediaSourceId,
      playSessionId: playSessionId,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      subtitleTextOnly: subtitle == null || textSubtitle,
      runtime: item.raw['RunTimeTicks'] is int
          ? Duration(microseconds: (item.raw['RunTimeTicks'] as int) ~/ 10)
          : null,
      started: sameStream && previous!.started,
    );
    lastPosition = start; // until the Chromecast reports in
    if (!_followingSubtitleStyle) {
      _followingSubtitleStyle = true;
      playbackSettings.addListener(_sendSubtitleStyle);
    }
    _attempt = _CastAttempt(
      item: item,
      start: start,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      quality: quality,
      playSessionId: playSessionId,
    );
    notifyListeners();

    // Not playing in a while (a Chromecast that can't keep up can sit loading): a lower quality.
    _startTimer?.cancel();
    _startTimer = Timer(const Duration(seconds: 45), () {
      if (!_playing && _attempt?.playSessionId == playSessionId && _attempt?.quality == quality) _couldNotPlay();
    });

    try {
      await _send(url, title, item, base, imageTag, tracks, start, subtitle, textSubtitle, subtitleStreamIndex, quality);
    } catch (e) {
      debugPrint('Cast load failed: $e');
      _couldNotPlay();
      return;
    }

    await _startReporting(start);
  }

  Future<void> _send(
    Uri url,
    String title,
    JellyfinItem item,
    String base,
    String? imageTag,
    List<GoogleCastMediaTrack> tracks,
    Duration start,
    Map<String, dynamic>? subtitle,
    bool textSubtitle,
    int? subtitleStreamIndex,
    CastQuality quality,
  ) async {
    await GoogleCastRemoteMediaClient.instance.loadMedia(
      GoogleCastMediaInformation(
        contentId: url.toString(),
        contentUrl: url,
        streamType: CastMediaStreamType.buffered,
        contentType: 'application/x-mpegURL',
        textTrackStyle: castSubtitleStyle(playbackSettings),
        // 4K comes in MP4 pieces (HEVC needs them), which the Chromecast has to be told.
        hlsSegmentFormat: quality.fmp4 ? CastHlsSegmentFormat.fmp4 : null,
        hlsVideoSegmentFormat: quality.fmp4 ? HlsVideoSegmentFormat.fmp4 : null,
        metadata: GoogleCastMovieMediaMetadata(
          title: title,
          images: [
            if (imageTag != null)
              GoogleCastImage(
                url: Uri.parse('$base/Items/${item.id}/Images/Primary?maxWidth=600&tag=$imageTag'),
              ),
          ],
        ),
        tracks: tracks,
      ),
      autoPlay: true,
      playPosition: start,
      activeTrackIds: [
        if (subtitle != null && textSubtitle) _trackId(subtitleStreamIndex!),
      ],
    );
  }

  /// Text subtitles switch instantly; anything else (picture subtitles, audio) reloads
  /// the stream from the current position.
  Future<void> setSubtitles(JellyfinItem item, int? streamIndex, {required bool isText}) async {
    final now = nowPlaying;
    if (now == null) return;
    // Switching between text subtitles (or to off) is instant, unless picture subtitles are
    // burned into the current stream, which needs a clean stream without them.
    if ((streamIndex == null || isText) && now.subtitleTextOnly) {
      await GoogleCastRemoteMediaClient.instance.setActiveTrackIDs([
        if (streamIndex != null) _trackId(streamIndex),
      ]);
      nowPlaying = now.copyWith(subtitleStreamIndex: streamIndex, clearSubtitle: streamIndex == null, subtitleTextOnly: true);
      notifyListeners();
      return;
    }
    await load(item, start: position, audioStreamIndex: now.audioStreamIndex, subtitleStreamIndex: streamIndex);
  }

  Future<void> setAudio(JellyfinItem item, int streamIndex) async {
    final now = nowPlaying;
    if (now == null) return;
    await load(item, start: position, audioStreamIndex: streamIndex, subtitleStreamIndex: now.subtitleStreamIndex);
  }

  Future<void> play() => GoogleCastRemoteMediaClient.instance.play();
  Future<void> pause() => GoogleCastRemoteMediaClient.instance.pause();
  Future<void> playOrPause() => isPlaying ? pause() : play();

  Future<void> seek(Duration to) =>
      GoogleCastRemoteMediaClient.instance.seek(GoogleCastMediaSeekOption(position: to < Duration.zero ? Duration.zero : to));

  // Text subtitle track ids: the Jellyfin stream index + 1 (Cast track ids start at 1).
  static int _trackId(int streamIndex) => streamIndex + 1;

  // ─── Telling Jellyfin what's playing ─────────────────────────────────────

  Future<void> _report(String path, {bool paused = false}) async {
    final now = nowPlaying;
    final base = jellyfin.client?.baseUrl;
    if (now == null || base == null || !jellyfin.isConnected) return;
    try {
      await http.post(
        Uri.parse('$base$path'),
        headers: {...jellyfin.authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'ItemId': now.itemId,
          'MediaSourceId': now.mediaSourceId,
          'PlaySessionId': now.playSessionId,
          'PositionTicks': position.inMicroseconds * 10,
          'IsPaused': paused,
          'PlayMethod': 'Transcode',
          'CanSeek': true,
          if (now.audioStreamIndex != null) 'AudioStreamIndex': now.audioStreamIndex,
          if (now.subtitleStreamIndex != null) 'SubtitleStreamIndex': now.subtitleStreamIndex,
        }),
      );
    } catch (e) {
      debugPrint('Cast progress report failed: $e'); // offline: try again next time
    }
  }

  Future<void> _startReporting(Duration start) async {
    final now = nowPlaying;
    if (now == null) return;
    if (!now.started) {
      nowPlaying = now.copyWith(started: true);
      await _report('/Sessions/Playing');
    }
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _report('/Sessions/Playing/Progress', paused: playerState == CastMediaPlayerState.paused);
    });
  }

  Future<void> _finishReporting() async {
    _progressTimer?.cancel();
    _progressTimer = null;
    final now = nowPlaying;
    if (now == null) return;
    await _report('/Sessions/Playing/Stopped');
    nowPlaying = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _progressTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }
}

/// The app's subtitle settings as Cast's text track style: the font (the nearest of the
/// families a Chromecast has, with the font's own name for one that knows it), drop shadow,
/// outline or dark box, color and size. (Where they sit can't be set: the Chromecast decides.)
///
/// Note: flutter_chrome_cast 1.5 doesn't pass styles on to the Chromecast (its native code leaves
/// them out); the app sets them itself (see _sendSubtitleStyle). This is sent as well, for when
/// a version of it does.
TextTrackStyle castSubtitleStyle(PlaybackSettings s) => _CastSubtitleStyle(
  fontFamily: s.subtitleFont,
  fontGenericFamily: castFontFamilyOf(s.subtitleFont),
  edge: switch (s.subtitleBackground) {
    SubtitleBackground.shadow => TextTrackEdgeType.dropShadow,
    SubtitleBackground.outline => TextTrackEdgeType.outline,
    SubtitleBackground.box => TextTrackEdgeType.none,
  },
  edgeColor: const Color(0xFF000000),
  backgroundColor: s.subtitleBackground == SubtitleBackground.box ? const Color(0xB3000000) : const Color(0x00000000),
  foregroundColor: s.subtitleColor.color,
  scale: s.subtitleSize.scale,
);

/// The Cast font family nearest a Google Font, by its name.
@visibleForTesting
TextTrackFontGenericFamily castFontFamilyOf(String font) {
  final name = font.toLowerCase();
  bool any(List<String> words) => words.any(name.contains);
  if (any(['mono', 'code', 'courier', 'consol'])) {
    return name.contains('serif') && !name.contains('sans')
        ? TextTrackFontGenericFamily.monospacedSerif
        : TextTrackFontGenericFamily.monospacedSansSerif;
  }
  if (any(['small caps', 'smallcaps']) || RegExp(r'\bsc\b').hasMatch(name)) {
    return TextTrackFontGenericFamily.smallCapitals;
  }
  if (any(['script', 'pacifico', 'vibes', 'satisfy', 'cursive', 'dancing', 'handwriting', 'allura'])) {
    return TextTrackFontGenericFamily.cursive;
  }
  if (any(['comic', 'caveat', 'indie', 'marker', 'patrick', 'gloria', 'kalam', 'casual'])) {
    return TextTrackFontGenericFamily.casual;
  }
  const serifs = ['merriweather', 'lora', 'playfair', 'garamond', 'georgia', 'baskerville', 'crimson', 'caslon', 'slab', 'bitter', 'domine', 'spectral', 'cormorant', 'times'];
  if (any(serifs) || (name.contains('serif') && !name.contains('sans'))) return TextTrackFontGenericFamily.serif;
  return TextTrackFontGenericFamily.sansSerif;
}

/// flutter_chrome_cast's style, with the two fields its class can't hold sent as Cast has them:
/// the edge (drop shadow, outline) and a size that isn't a whole number (1.25 times).
class _CastSubtitleStyle extends TextTrackStyle {
  _CastSubtitleStyle({
    required this.edge,
    required this.scale,
    super.fontFamily,
    super.fontGenericFamily,
    super.edgeColor,
    super.backgroundColor,
    super.foregroundColor,
  });

  final TextTrackEdgeType edge;
  final double scale;

  @override
  Map<String, dynamic> toMap() => {...super.toMap(), 'edgeType': edge.name, 'fontScale': scale};
}

/// How good a stream is sent to the Chromecast, best first: each one down is tried when the
/// one before won't play.
enum CastQuality {
  /// Up to 4K, HEVC or H.264 passed straight through (anything else made H.264), in MP4 pieces.
  uhd(maxWidth: 3840, maxHeight: 2160, maxBitrate: 80000000, videoCodecs: 'h264,hevc', fmp4: true),

  /// Up to 1080p H.264 (High profile), which every Chromecast plays.
  fullHd(maxWidth: 1920, maxHeight: 1080, maxBitrate: 18000000, videoCodecs: 'h264', profile: 'high'),

  /// Up to 720p H.264, for a slow network.
  hd(maxWidth: 1280, maxHeight: 720, maxBitrate: 8000000, videoCodecs: 'h264', profile: 'high');

  const CastQuality({
    required this.maxWidth,
    required this.maxHeight,
    required this.maxBitrate,
    required this.videoCodecs,
    this.fmp4 = false,
    this.profile,
  });

  final int maxWidth;
  final int maxHeight;
  final int maxBitrate; // bits per second
  final String videoCodecs; // the first is what anything else is converted to
  final bool fmp4;
  final String? profile; // H.264's, for what's converted

  /// The next quality down, or null at the bottom.
  CastQuality? get lower => index + 1 < values.length ? values[index + 1] : null;
}

/// What was sent to the Chromecast last, and at what quality.
class _CastAttempt {
  const _CastAttempt({
    required this.item,
    required this.start,
    required this.audioStreamIndex,
    required this.subtitleStreamIndex,
    required this.quality,
    required this.playSessionId,
  });

  final JellyfinItem item;
  final Duration start;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final CastQuality quality;
  final String playSessionId;
}

/// The video this app sent to the Chromecast.
class CastNowPlaying {
  const CastNowPlaying({
    required this.itemId,
    required this.title,
    required this.mediaSourceId,
    required this.playSessionId,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
    this.subtitleTextOnly = true,
    this.runtime,
    this.started = false,
  });

  final String itemId;
  final String title;
  final String mediaSourceId;
  final String playSessionId;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final bool subtitleTextOnly; // false when picture subtitles are burned into the stream
  final Duration? runtime;
  final bool started; // Jellyfin has been told playback started

  CastNowPlaying copyWith({
    int? subtitleStreamIndex,
    bool clearSubtitle = false,
    bool? subtitleTextOnly,
    bool? started,
  }) => CastNowPlaying(
    itemId: itemId,
    title: title,
    mediaSourceId: mediaSourceId,
    playSessionId: playSessionId,
    audioStreamIndex: audioStreamIndex,
    subtitleStreamIndex: clearSubtitle ? null : (subtitleStreamIndex ?? this.subtitleStreamIndex),
    subtitleTextOnly: subtitleTextOnly ?? this.subtitleTextOnly,
    runtime: runtime,
    started: started ?? this.started,
  );
}

final castController = CastController();
