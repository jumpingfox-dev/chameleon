import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on while any [KeepAwake] is held: the video player while it plays, the
/// screensaver while it shows. Counted, so one letting go doesn't turn off another's.
class KeepAwake {
  bool _held = false;

  static int _count = 0;

  void hold() {
    if (_held) return;
    _held = true;
    if (_count++ == 0) _apply(true);
  }

  void release() {
    if (!_held) return;
    _held = false;
    if (--_count == 0) _apply(false);
  }

  static void _apply(bool on) =>
      (on ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((Object e) => debugPrint('Keep awake: $e'));
}
