import 'package:flutter/services.dart';

import 'screen_type.dart';

/// Which ways the screen may turn.
///
/// * Phones: the app stays upright, except the player, which turns with the phone
///   (following the phone's own rotation lock).
/// * Tablets, TVs and desktops: anything goes, everywhere.
abstract final class AppOrientation {
  static bool get _isPhone => ScreenType.current.isPhone;

  /// Call once at startup.
  static Future<void> init() => menus();

  /// Everything outside the player: upright on phones, with the status and navigation bars.
  /// TVs have no use for system bars, so they stay hidden there, as in other TV apps.
  static Future<void> menus() async {
    await SystemChrome.setEnabledSystemUIMode(
      ScreenType.isTvDevice ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    await SystemChrome.setPreferredOrientations(
      _isPhone ? const [DeviceOrientation.portraitUp] : const [],
    );
  }

  /// Sideways, either way round.
  static const landscape = [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight];

  /// Upright.
  static const portrait = [DeviceOrientation.portraitUp];

  /// The player: full screen, held to [only] (e.g. [landscape]). Left empty, it's free to turn
  /// with the phone, following the phone's own rotation lock. Tablets and TVs always turn freely.
  static Future<void> player({List<DeviceOrientation> only = const []}) async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(_isPhone ? only : const []);
  }
}