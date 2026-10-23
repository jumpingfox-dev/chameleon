import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Turning the screen off when the screensaver's time is up (Android: ScreenOff.kt). Apps can't
/// power a TV off; turning the screen off lets a TV that follows its source over HDMI-CEC go
/// to standby. Needs the person's OK once ([enable]).
abstract final class ScreenOff {
  static const _channel = MethodChannel('chameleon/screen_off');

  /// Only Android can do this.
  static bool get supported => !kIsWeb && Platform.isAndroid;

  static Future<bool> isEnabled() async => supported && await _call<bool>('isEnabled') == true;

  /// Asks for the OK (Android shows its own screen for it); true if given.
  static Future<bool> enable() async => supported && await _call<bool>('enable') == true;

  /// Gives the OK back, so nothing is left over (Android won't uninstall an app holding it).
  static Future<void> disable() async {
    if (supported) await _call<void>('disable');
  }

  /// Turns the screen off now, if allowed; false if it isn't.
  static Future<bool> turnOff() async => supported && await _call<bool>('turnOff') == true;

  static Future<T?> _call<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } catch (e) {
      debugPrint('ScreenOff.$method: $e');
      return null;
    }
  }
}
