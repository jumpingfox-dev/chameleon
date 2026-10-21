import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'playback_engine.dart';

/// ExoPlayer, on Android (see ExoEngine.kt): the engine for Dolby Vision, which it plays through
/// Android's own Dolby Vision decoder, and the fallback when mpv can't open a file.
///
/// Track ids are "a:group:track" and "s:group:track" (ExoPlayer's own numbering); a subtitle
/// file added from the server keeps its address as its id, as with mpv.
class ExoEngine implements PlaybackEngine {
  ExoEngine._();

  static const _channel = MethodChannel('chameleon/exo');
  static final _events = const EventChannel('chameleon/exo/events').receiveBroadcastStream();

  /// What the device can do for ExoPlayer, asked once.
  static Future<ExoSupport> support() => _support ??= () async {
    if (kIsWeb || !Platform.isAndroid) return const ExoSupport(dolbyVision: false, audio: {});
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('support') ?? const {};
      return ExoSupport(
        dolbyVision: map['dolbyVision'] == true,
        audio: {...((map['audio'] as List?) ?? const []).cast<String>()},
      );
    } catch (e) {
      debugPrint('ExoPlayer support: $e');
      return const ExoSupport(dolbyVision: false, audio: {});
    }
  }();
  static Future<ExoSupport>? _support;

  /// Starts ExoPlayer. [passthrough]: send surround sound on untouched where the output takes it.
  static Future<ExoEngine> create({required bool passthrough}) async {
    final engine = ExoEngine._();
    engine._listening = _events.listen(engine._onEvent);
    await _channel.invokeMethod('create', {'passthrough': passthrough});
    return engine;
  }

  StreamSubscription<Object?>? _listening;
  PlayerState _state = const PlayerState();

  final _playing = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _buffer = StreamController<Duration>.broadcast();
  final _videoParams = StreamController<VideoParams>.broadcast();
  final _track = StreamController<Track>.broadcast();
  final _tracks = StreamController<Tracks>.broadcast();
  final _subtitle = StreamController<List<String>>.broadcast();
  final _error = StreamController<String>.broadcast();

  @override
  PlayerState get state => _state;

  @override
  late final PlayerStream stream = PlayerStream(
    const Stream.empty(),
    _playing.stream,
    _completed.stream,
    _position.stream,
    _duration.stream,
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    _buffering.stream,
    const Stream.empty(),
    _buffer.stream,
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    _videoParams.stream,
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    _track.stream,
    _tracks.stream,
    const Stream.empty(),
    const Stream.empty(),
    _subtitle.stream,
    const Stream.empty(),
    _error.stream,
  );

  void _onEvent(Object? event) {
    if (event is! Map) return;
    var s = _state;
    if (event['position'] case final int ms) {
      s = s.copyWith(position: Duration(milliseconds: ms));
      _position.add(s.position);
    }
    if (event['buffer'] case final int ms) {
      s = s.copyWith(buffer: Duration(milliseconds: ms));
      _buffer.add(s.buffer);
    }
    if (event.containsKey('duration')) {
      final ms = event['duration'] as int?;
      final duration = ms == null ? Duration.zero : Duration(milliseconds: ms);
      if (duration != s.duration) {
        s = s.copyWith(duration: duration);
        _duration.add(duration);
      }
    }
    if (event['playing'] case final bool playing) {
      s = s.copyWith(playing: playing);
      _playing.add(playing);
    }
    if (event['buffering'] case final bool buffering) {
      s = s.copyWith(buffering: buffering);
      _buffering.add(buffering);
    }
    if (event['completed'] case final bool completed when completed != s.completed) {
      s = s.copyWith(completed: completed);
      _completed.add(completed);
    }
    if (event['video'] case final Map video) {
      final width = video['width'] as int, height = video['height'] as int;
      final ratio = (video['pixelRatio'] as num?)?.toDouble() ?? 1;
      final params = VideoParams(w: width, h: height, dw: (width * ratio).round(), dh: height, par: ratio);
      s = s.copyWith(videoParams: params, width: params.dw, height: params.dh);
      _videoParams.add(params);
    }
    if (event['subtitle'] case final List lines) {
      s = s.copyWith(subtitle: lines.cast<String>());
      _subtitle.add(s.subtitle);
    }
    if (event['tracks'] case final List list) {
      final (tracks, track) = _readTracks(list.cast<Map>());
      s = s.copyWith(tracks: tracks, track: track);
      _tracks.add(tracks);
      _track.add(track);
    }
    _state = s;
    if (event['error'] case final String message) _error.add(message);
  }

  (Tracks, Track) _readTracks(List<Map> list) {
    final video = <VideoTrack>[], audio = <AudioTrack>[], subtitles = <SubtitleTrack>[];
    VideoTrack? selectedVideo;
    AudioTrack? selectedAudio;
    SubtitleTrack? selectedSubtitle;
    for (final t in list) {
      final title = t['title'] as String?, language = t['language'] as String?;
      final codec = t['codec'] as String?;
      final isDefault = t['default'] as bool?;
      final position = '${t['group']}:${t['track']}';
      final selected = t['selected'] == true;
      switch (t['type']) {
        case 'video':
          final track = VideoTrack('v:$position', title, language, codec: codec, isDefault: isDefault);
          video.add(track);
          if (selected) selectedVideo = track;
        case 'audio':
          final track = AudioTrack(
            'a:$position',
            title,
            language,
            codec: codec,
            isDefault: isDefault,
            channelscount: t['channels'] as int?,
          );
          audio.add(track);
          if (selected) selectedAudio = track;
        case 'subtitle':
          final url = t['url'] as String?;
          final track = SubtitleTrack(
            url ?? 's:$position',
            title,
            language,
            codec: codec,
            isDefault: isDefault,
            uri: url != null,
          );
          subtitles.add(track);
          if (selected) selectedSubtitle = track;
      }
    }
    return (
      Tracks(
        video: [VideoTrack.auto(), VideoTrack.no(), ...video],
        audio: [AudioTrack.auto(), AudioTrack.no(), ...audio],
        subtitle: [SubtitleTrack.auto(), SubtitleTrack.no(), ...subtitles],
      ),
      Track(
        video: selectedVideo ?? VideoTrack.auto(),
        audio: selectedAudio ?? AudioTrack.auto(),
        subtitle: selectedSubtitle ?? SubtitleTrack.no(),
      ),
    );
  }

  /// "a:2:0" → (2, 0).
  static (int, int)? _place(String id) {
    final parts = id.split(':');
    if (parts.length != 3) return null;
    final group = int.tryParse(parts[1]), track = int.tryParse(parts[2]);
    return group == null || track == null ? null : (group, track);
  }

  @override
  Future<void> open(Media media, {bool play = true}) async {
    _state = const PlayerState();
    _completed.add(false);
    await _channel.invokeMethod('open', {
      'uri': media.uri,
      'headers': media.httpHeaders ?? const <String, String>{},
      'start': media.start?.inMilliseconds ?? 0,
      'play': play,
    });
  }

  @override
  Future<void> play() => _channel.invokeMethod('play');

  @override
  Future<void> pause() => _channel.invokeMethod('pause');

  @override
  Future<void> playOrPause() => _state.playing ? pause() : play();

  @override
  Future<void> seek(Duration position) {
    _state = _state.copyWith(position: position);
    _position.add(position);
    return _channel.invokeMethod('seek', {'position': position.inMilliseconds});
  }

  @override
  Future<void> stop() => _channel.invokeMethod('stop');

  @override
  Future<void> setAudioTrack(AudioTrack track) async {
    final place = _place(track.id);
    if (place == null) return; // "auto" and "no" mean nothing here
    await _channel.invokeMethod('selectTrack', {'type': 'audio', 'group': place.$1, 'track': place.$2});
  }

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    if (track.id == 'no') {
      await _channel.invokeMethod('disableSubtitles');
      _subtitle.add(const []);
      return;
    }
    if (track.uri || track.id.startsWith('http')) {
      await _channel.invokeMethod('addSubtitle', {'uri': track.id, 'language': track.language, 'title': track.title});
      return;
    }
    final place = _place(track.id);
    if (place == null) return;
    await _channel.invokeMethod('selectTrack', {'type': 'text', 'group': place.$1, 'track': place.$2});
  }

  @override
  Future<void> dispose() async {
    await _listening?.cancel();
    await _channel.invokeMethod('dispose');
    for (final c in [
      _playing, _completed, _position, _duration, _buffering, _buffer, //
      _videoParams, _track, _tracks, _subtitle, _error,
    ]) {
      await c.close();
    }
  }
}

/// What ExoPlayer can play on this device: whether there's a Dolby Vision decoder, and the
/// audio formats with decoders (mime types, e.g. "audio/eac3").
class ExoSupport {
  const ExoSupport({required this.dolbyVision, required this.audio});

  final bool dolbyVision;
  final Set<String> audio;

  /// Whether ExoPlayer can play audio in Jellyfin's [codec] ("eac3", "truehd" …), decoded here
  /// or passed on untouched ([passthrough]: the formats the output takes, in mpv's names).
  bool playsAudio(String? codec, Set<String> passthrough) {
    final c = codec?.toLowerCase();
    if (c == null) return true;
    if (const {'aac', 'mp3', 'mp2', 'opus', 'flac', 'vorbis', 'alac'}.contains(c) || c.startsWith('pcm')) return true;
    final (mime, mpvName) = switch (c) {
      'ac3' => ('audio/ac3', 'ac3'),
      'eac3' => ('audio/eac3', 'eac3'),
      'truehd' => ('audio/true-hd', 'truehd'),
      'dts' => ('audio/vnd.dts', 'dts'),
      'dtshd' || 'dts-hd' => ('audio/vnd.dts.hd', 'dts-hd'),
      _ => (null, null),
    };
    if (mime == null) return false;
    return audio.contains(mime) || passthrough.contains(mpvName);
  }
}
