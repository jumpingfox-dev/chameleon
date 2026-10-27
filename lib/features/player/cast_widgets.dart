import 'dart:io';

import 'package:dart_jellyfin/dart_jellyfin.dart' show JellyfinItem;
import 'package:flutter/foundation.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart' show CastMediaPlayerState;
import 'package:flutter_to_airplay/flutter_to_airplay.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/cast/cast_controller.dart';
import '../../core/format/format.dart';
import '../../core/jellyfin/jellyfin_controller.dart';
import 'playback_settings.dart';
import '../../theme/theme.dart';
import '../../widgets/tappable.dart';

// ─── Choosing where to play: Chromecast and AirPlay ──────────────────────────

/// One menu for both ways of playing on another screen: the Chromecasts on the network
/// (or Stop casting, while casting), and on iPhone and iPad, AirPlay.
Future<void> showCastMenu(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    child: ConstrainedBox(
      // Scrolls when there are more devices than fit (and keeps AirPlay reachable below them).
      constraints: BoxConstraints(maxWidth: 420, maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: const SingleChildScrollView(child: _CastMenuBody()),
    ),
  ),
);

class _CastMenuBody extends StatelessWidget {
  const _CastMenuBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
    );

    return ListenableBuilder(
      listenable: castController,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          spacing: 8,
          children: [
            Text('Play on', style: theme.textTheme.titleLarge),

            // ── Chromecast ──
            if (castController.supported) ...[
              heading('Chromecast'),
              if (castController.isConnected) ...[
                Text('Casting to ${castController.deviceName ?? 'a Chromecast'}', style: theme.textTheme.bodyLarge),
                if (castController.nowPlaying != null) Text(castController.nowPlaying!.title, style: muted),
                FilledButton(
                  autofocus: true,
                  onPressed: () {
                    castController.disconnect();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Stop casting'),
                ),
              ] else if (castController.devices.isEmpty)
                Text('Looking for Chromecasts on your network…', style: muted)
              else
                for (final (i, device) in castController.devices.indexed)
                  ListTile(
                    autofocus: i == 0,
                    shape: const StadiumBorder(),
                    leading: const Icon(Icons.cast_rounded, size: 20), // a Chromecast to pick
                    title: Text(device.friendlyName, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      castController.connect(device);
                      Navigator.of(context).pop();
                    },
                  ),
            ],

            // ── AirPlay ──
            if (AirPlayButton.available) ...[
              heading('AirPlay'),
              const _AirPlayRow(),
            ],

            const SizedBox(height: 4),
            Center(
              child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row that opens Apple's AirPlay picker: Apple's own button, invisible, laid over it, since
/// iOS doesn't let apps list AirPlay devices themselves.
class _AirPlayRow extends StatelessWidget {
  const _AirPlayRow();

  @override
  Widget build(BuildContext context) {
    final muted = context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant);
    return Stack(
      children: [
        ListTile(
          shape: const StadiumBorder(),
          leading: const Icon(Icons.airplay_rounded, size: 20),
          title: const Text('Choose an AirPlay device'),
          subtitle: Text('Plays the sound on an Apple TV, HomePod or speaker. For the picture too, '
              'use Screen Mirroring in Control Center.', style: muted),
        ),
        const Positioned.fill(
          child: AirPlayRoutePickerView(
            prioritizesVideoDevices: true,
            tintColor: Color(0x00000000),
            activeTintColor: Color(0x00000000),
            backgroundColor: Color(0x00000000),
          ),
        ),
      ],
    );
  }
}

/// Whether to offer playing elsewhere: AirPlay on iPhone and iPad; Chromecast only when one is
/// around (or already casting), as Google's guidelines ask, so it never shows on a TV or with
/// no Chromecast at home.
bool get showCastButton =>
    AirPlayButton.available ||
    (castController.supported && (castController.isConnected || castController.devices.isNotEmpty));

/// The cast icon everywhere (top bar, menu, player, casting screen): always Material Icons' own,
/// whatever the icon style, as it's the one people know. Connected while casting.
IconData get castIcon => castController.isConnected ? Icons.cast_connected_rounded : Icons.cast_rounded;

// ─── AirPlay (iPhone and iPad) ───────────────────────────────────────────────

/// Whether AirPlay is available here: iOS only.
///
/// The player plays through mpv rather than Apple's player, so AirPlay carries the sound
/// (to an Apple TV, HomePod or AirPlay speaker); for the picture on an Apple TV, use
/// Screen Mirroring in Control Center.
abstract final class AirPlayButton {
  static bool get available => !kIsWeb && Platform.isIOS;
}

// ─── The remote, while casting ───────────────────────────────────────────────

/// Fills the player while the video plays on a Chromecast: what's playing, where it is,
/// and the controls, which all drive the Chromecast.
class CastRemote extends StatelessWidget {
  const CastRemote({
    super.key,
    required this.item,
    required this.onBack,
    required this.onAudio,
    required this.onSubtitles,
  });

  final JellyfinItem item;
  final VoidCallback onBack; // leaves the player; casting carries on
  final VoidCallback onAudio;
  final VoidCallback onSubtitles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const white = Color(0xFFFFFFFF);
    const dim = Color(0xB3FFFFFF);
    final base = jellyfin.client?.baseUrl;
    // Not wideImageUrl: this one has no poster fallback, and sizes by maxWidth (no crop)
    // rather than fillWidth, since it's just a dimmed-out background here.
    final backdrop = (item.raw['BackdropImageTags'] as List?)?.firstOrNull as String?;
    final backdropId = backdrop != null ? item.id : item.raw['ParentBackdropItemId'] as String?;
    final backdropTag = backdrop ?? ((item.raw['ParentBackdropImageTags'] as List?)?.firstOrNull as String?);

    return ListenableBuilder(
      listenable: castController,
      builder: (context, _) {
        final now = castController.nowPlaying;
        final step = playbackSettings.seekStep; // "Jump by" in Settings
        final buffering = castController.playerState == CastMediaPlayerState.buffering ||
            castController.playerState == CastMediaPlayerState.loading;

        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF000000)),
            if (base != null && backdropId != null && backdropTag != null)
              Opacity(
                opacity: 0.35,
                child: Image.network(
                  '$base/Items/$backdropId/Images/Backdrop?maxWidth=1280&tag=$backdropTag',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: [
                    Row(
                      children: [
                        _RemoteButton(icon: Icons.arrow_back_rounded, label: 'Back', onPress: onBack),
                        const Spacer(),
                        _RemoteButton(icon: Icons.graphic_eq_rounded, label: 'Audio', onPress: onAudio),
                        _RemoteButton(icon: Icons.subtitles_rounded, label: 'Subtitles', onPress: onSubtitles),
                        _RemoteButton(
                          icon: castIcon,
                          label: 'Stop casting',
                          onPress: () => showCastMenu(context),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Icon(castIcon, size: 40, color: dim),
                    const SizedBox(height: 8),
                    Text(
                      'Casting to ${castController.deviceName ?? 'Chromecast'}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: dim),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      now?.title ?? item.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(color: white),
                    ),
                    const Spacer(),
                    StreamBuilder<Duration>(
                      stream: castController.positionStream,
                      initialData: castController.position,
                      builder: (context, snap) => _RemoteSeekBar(
                        position: snap.data ?? Duration.zero,
                        duration: now?.runtime ?? Duration.zero,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: 40,
                      children: [
                        _RemoteButton(
                          icon: _backIcon(step),
                          label: 'Back $step seconds',
                          size: 36,
                          onPress: () => castController.seek(
                            castController.position > Duration(seconds: step)
                                ? castController.position - Duration(seconds: step)
                                : Duration.zero,
                          ),
                        ),
                        buffering
                            ? const SizedBox(width: 64, height: 64, child: Center(child: CircularProgressIndicator()))
                            : _RemoteButton(
                          icon: castController.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          label: castController.isPlaying ? 'Pause' : 'Play',
                          size: 52,
                          onPress: castController.playOrPause,
                        ),
                        _RemoteButton(
                          icon: _forwardIcon(step),
                          label: 'Forward $step seconds',
                          size: 36,
                          onPress: () => castController.seek(castController.position + Duration(seconds: step)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Icons with the number on them, where Material has one (5, 10 and 30 seconds).
IconData _backIcon(int seconds) => switch (seconds) {
  5 => Icons.replay_5_rounded,
  10 => Icons.replay_10_rounded,
  30 => Icons.replay_30_rounded,
  _ => Icons.replay_rounded,
};

IconData _forwardIcon(int seconds) => switch (seconds) {
  5 => Icons.forward_5_rounded,
  10 => Icons.forward_10_rounded,
  30 => Icons.forward_30_rounded,
  _ => Icons.fast_forward_rounded,
};

class _RemoteButton extends StatelessWidget {
  const _RemoteButton({required this.icon, required this.label, required this.onPress, this.size = 26});

  final IconData icon;
  final String label;
  final VoidCallback onPress;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Tappable(
      onPress: onPress,
      builder: (context, states, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isHighlighted(states) ? const Color(0x33FFFFFF) : const Color(0x00FFFFFF),
        ),
        child: Icon(icon, size: size, color: const Color(0xFFFFFFFF)),
      ),
    ),
  );
}

/// A simple slider for the Chromecast's position; drag to seek.
class _RemoteSeekBar extends StatefulWidget {
  const _RemoteSeekBar({required this.position, required this.duration});

  final Duration position;
  final Duration duration;

  @override
  State<_RemoteSeekBar> createState() => _RemoteSeekBarState();
}

class _RemoteSeekBarState extends State<_RemoteSeekBar> {
  double? _dragging; // 0..1 while the thumb is held

  @override
  Widget build(BuildContext context) {
    final total = widget.duration.inMilliseconds;
    final fraction = _dragging ?? (total <= 0 ? 0.0 : (widget.position.inMilliseconds / total).clamp(0.0, 1.0));
    final shown = _dragging == null ? widget.position : widget.duration * fraction;
    const dim = Color(0xB3FFFFFF);
    final timeStyle = context.text.bodyMedium?.copyWith(color: dim);

    return Column(
      mainAxisSize: .min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: context.colors.primary,
            inactiveTrackColor: const Color(0x4DFFFFFF),
            thumbColor: const Color(0xFFFFFFFF),
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(
            value: fraction,
            onChanged: total <= 0 ? null : (v) => setState(() => _dragging = v),
            onChangeEnd: (v) {
              castController.seek(widget.duration * v);
              setState(() => _dragging = null);
            },
          ),
        ),
        Row(
          children: [
            Text(formatDuration(shown), style: timeStyle),
            const Spacer(),
            Text(formatDuration(widget.duration), style: timeStyle),
          ],
        ),
      ],
    );
  }
}