import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'exo_engine.dart';

export 'package:media_kit/media_kit.dart'
    show AudioTrack, Media, PlayerState, PlayerStream, SubtitleTrack, Track, Tracks, VideoParams, VideoTrack;

/// Something that plays a video: mpv ([MpvEngine], through media_kit) or ExoPlayer
/// ([ExoEngine], Android only). The player talks to [Playback], which passes everything on to
/// whichever of the two is in use. Both describe themselves in media_kit's terms ([PlayerState],
/// [PlayerStream], [Tracks]), so the player needn't know which it has.
abstract interface class PlaybackEngine {
  PlayerState get state;
  PlayerStream get stream;

  /// Opens [media] (its address, headers and start position) and starts it unless [play] is false.
  Future<void> open(Media media, {bool play = true});
  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> setAudioTrack(AudioTrack track);
  Future<void> setSubtitleTrack(SubtitleTrack track);
  Future<void> dispose();
}

/// mpv, the main engine: plays nearly anything, and is where the audio settings (passthrough,
/// downmix, night mode) apply.
class MpvEngine implements PlaybackEngine {
  MpvEngine(this.player);

  /// media_kit's player, for what only mpv has: its video output, and its own properties.
  final Player player;

  @override
  PlayerState get state => player.state;
  @override
  PlayerStream get stream => player.stream;
  @override
  Future<void> open(Media media, {bool play = true}) => player.open(media, play: play);
  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> playOrPause() => player.playOrPause();
  @override
  Future<void> seek(Duration position) => player.seek(position);
  @override
  Future<void> stop() => player.stop();
  @override
  Future<void> setAudioTrack(AudioTrack track) => player.setAudioTrack(track);
  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) => player.setSubtitleTrack(track);
  @override
  Future<void> dispose() => player.dispose();
}

/// The player's engine: mpv to begin with, and ExoPlayer after [useExo]. Its [stream] carries
/// on across a switch, so whatever is listening keeps hearing from the engine in use.
class Playback implements PlaybackEngine {
  Playback(Player player) : mpv = MpvEngine(player) {
    _forward(mpv);
  }

  final MpvEngine mpv;
  ExoEngine? _exo;
  late PlaybackEngine _active = mpv;

  /// Whether ExoPlayer is playing, rather than mpv.
  bool get usingExo => _active == _exo && _exo != null;

  final _subscriptions = <StreamSubscription<Object?>>[];
  final _playing = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _rate = StreamController<double>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _buffer = StreamController<Duration>.broadcast();
  final _videoParams = StreamController<VideoParams>.broadcast();
  final _track = StreamController<Track>.broadcast();
  final _tracks = StreamController<Tracks>.broadcast();
  final _subtitle = StreamController<List<String>>.broadcast();
  final _error = StreamController<String>.broadcast();

  @override
  late final PlayerStream stream = () {
    final m = mpv.player.stream;
    return PlayerStream(
      m.playlist,
      _playing.stream,
      _completed.stream,
      _position.stream,
      _duration.stream,
      m.volume,
      _rate.stream,
      m.pitch,
      _buffering.stream,
      m.bufferingPercentage,
      _buffer.stream,
      m.playlistMode,
      m.shuffle,
      m.audioParams,
      _videoParams.stream,
      m.audioBitrate,
      m.audioDevice,
      m.audioDevices,
      _track.stream,
      _tracks.stream,
      m.width,
      m.height,
      _subtitle.stream,
      m.log,
      _error.stream,
    );
  }();

  void _forward(PlaybackEngine engine) {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    final s = engine.stream;
    void pipe<T>(Stream<T> from, StreamController<T> to) => _subscriptions.add(from.listen(to.add));
    pipe(s.playing, _playing);
    pipe(s.completed, _completed);
    pipe(s.position, _position);
    pipe(s.duration, _duration);
    pipe(s.rate, _rate);
    pipe(s.buffering, _buffering);
    pipe(s.buffer, _buffer);
    pipe(s.videoParams, _videoParams);
    pipe(s.track, _track);
    pipe(s.tracks, _tracks);
    pipe(s.subtitle, _subtitle);
    pipe(s.error, _error);
  }

  /// Plays with ExoPlayer from now on. mpv stops. [passthrough] is the Settings choice.
  Future<void> useExo({required bool passthrough}) async {
    if (usingExo) return;
    await mpv.stop();
    final exo = _exo ??= await ExoEngine.create(passthrough: passthrough);
    _active = exo;
    _forward(exo);
    // Listeners start over from ExoPlayer's (empty) state.
    final s = exo.state;
    _playing.add(s.playing);
    _position.add(s.position);
    _duration.add(s.duration);
    _videoParams.add(s.videoParams);
    _tracks.add(s.tracks);
    _track.add(s.track);
  }

  /// Back to mpv, after ExoPlayer couldn't play something. ExoPlayer is let go of entirely,
  /// so its decoders and audio output are free for mpv.
  Future<void> useMpv() async {
    final exo = _exo;
    if (!usingExo || exo == null) return;
    _active = mpv;
    _forward(mpv);
    _exo = null;
    await exo.dispose();
  }

  @override
  PlayerState get state => _active.state;
  @override
  Future<void> open(Media media, {bool play = true}) => _active.open(media, play: play);
  @override
  Future<void> play() => _active.play();
  @override
  Future<void> pause() => _active.pause();
  @override
  Future<void> playOrPause() => _active.playOrPause();
  @override
  Future<void> seek(Duration position) => _active.seek(position);
  @override
  Future<void> stop() => _active.stop();
  @override
  Future<void> setAudioTrack(AudioTrack track) => _active.setAudioTrack(track);
  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) => _active.setSubtitleTrack(track);

  @override
  Future<void> dispose() async {
    for (final s in _subscriptions) {
      s.cancel();
    }
    await _exo?.dispose();
    await mpv.dispose();
    for (final c in [
      _playing, _completed, _position, _duration, _rate, _buffering, _buffer, //
      _videoParams, _track, _tracks, _subtitle, _error,
    ]) {
      await c.close();
    }
  }
}
