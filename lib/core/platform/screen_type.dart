import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// What kind of screen the app is on. Decided here and nowhere else: widgets ask
/// [ScreenType.of] instead of comparing widths themselves.
///
/// * [tv]: an Android TV or Google TV, known from the device itself rather than its size. A
///   1080p TV reports 960 × 540, which is phone-sized, and needs the remote-first layout anyway.
/// * [phone]: the screen's shorter side is under [compactBreakpoint] (Material's compact
///   window class). The shorter side rather than the width, so turning a phone sideways (or the
///   moment of landscape while leaving the player) never switches it to the tablet layout.
/// * [desktop]: Linux, macOS or Windows with a window bigger than a phone's.
/// * [tablet]: everything else.
///
/// Every screen has the top bar and the menu; phones (and tablets held upright) get the bottom bar.
/// Inside a widget, size things to their parent with a `LayoutBuilder` rather than by the
/// screen type when only the space matters.
enum ScreenType {
  phone,
  tablet,
  desktop,
  tv;

  /// Material's boundary between compact (phone) and medium (tablet) windows, in dp.
  static const compactBreakpoint = 600.0;

  /// The screen type for [context]'s window. Rebuilds [context] only when the window's size
  /// changes, not on other media query changes like the keyboard opening.
  static ScreenType of(BuildContext context) => forSize(MediaQuery.sizeOf(context));

  /// The screen type for a window of [size] (logical pixels), for code without a context.
  static ScreenType forSize(Size size) {
    if (_tvDevice) return tv;
    if (size.shortestSide < compactBreakpoint) return phone;
    return _desktopOs ? desktop : tablet;
  }

  /// The screen type of the app's window, for code without a context. [tv] before the first
  /// frame on a TV; otherwise needs the window to be up.
  static ScreenType get current {
    if (_tvDevice) return tv;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return _desktopOs ? desktop : tablet;
    final view = views.first;
    return forSize(view.physicalSize / view.devicePixelRatio);
  }

  /// Whether this device is a TV, before there's a window to ask (at startup).
  static bool get isTvDevice => _tvDevice;

  static bool _tvDevice = false;

  static bool get _desktopOs => !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  /// Call once at startup, before the first frame.
  ///
  /// `flutter run --dart-define=TV=true` forces it on, for trying the TV behaviour on an emulator
  /// whose system image isn't a TV one, or on desktop.
  static Future<void> detect() async {
    if (const bool.fromEnvironment('TV')) {
      _tvDevice = true;
      return;
    }
    if (kIsWeb || !Platform.isAndroid) return;
    final info = await DeviceInfoPlugin().androidInfo;
    _tvDevice = info.systemFeatures.contains('android.software.leanback');
  }

  /// The phone layout: bottom bar, touch-sized controls, no scaling.
  bool get isPhone => this == phone;

  /// Driven by a remote: no touch, so focus always shows.
  bool get isTv => this == tv;

  /// Phones and tablets, used by touch. Only they get a Close button on detail popouts: a TV
  /// has the remote's Back, and a desktop has Esc and clicking outside.
  bool get isTouch => this == phone || this == tablet;
}
