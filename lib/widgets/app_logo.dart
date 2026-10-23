import 'package:material_ui/material_ui.dart';

import '../theme/theme_controller.dart';
import '../theme/theme_presets.dart';
import '../theme/theme.dart';

/// Which version of the logo to show.
enum AppLogoVariant {
  /// Full color on the Prism theme, the theme-colored gradient on all others.
  auto,

  /// Always the theme-colored gradient.
  gradient,

  /// Always the full-color logo (falls back to the gradient if there's no color asset).
  color,
}

/// The app logo, in full color or as a theme-colored gradient (see [AppLogoVariant]).
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.asset = 'assets/images/logo.svg',
    this.colorAsset = 'assets/images/logo_color.svg',
    this.height = 32,
    this.variant = AppLogoVariant.auto,
  });

  /// Single-color version, filled with the gradient.
  final String asset;

  /// Full-color version. Pass null if there isn't one for this logo.
  final String? colorAsset;

  final double height;

  final AppLogoVariant variant;

  /// [svgAsset] drawn from its PNG copy beside it (rendered from the SVG at 480 pixels tall).
  /// Not the SVG itself: on GPUs without multisampling, which many TVs have, Flutter draws a
  /// vector's edges jagged, while a picture is smoothed as it's scaled. [tint] fills it with
  /// one color.
  static Widget picture(String svgAsset, {double? width, double? height, Color? tint}) => Image.asset(
    svgAsset.replaceFirst(RegExp(r'\.svg$'), '.png'),
    width: width,
    height: height,
    filterQuality: FilterQuality.medium, // smooth when scaled down (mipmaps)
    color: tint,
    colorBlendMode: tint == null ? null : BlendMode.srcIn,
  );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemePreset>(
    valueListenable: themeController,
    builder: (context, preset, _) {
      final showColor =
          colorAsset != null &&
          switch (variant) {
            AppLogoVariant.color => true,
            AppLogoVariant.gradient => false,
            AppLogoVariant.auto => preset.id == 'default',
          };

      if (showColor) {
        // The logo's own colors, no gradient.
        return picture(colorAsset!, height: height);
      }

      return ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          colors: [
            context.colors.primary,
            context.colors.outlineVariant,
          ],
        ).createShader(bounds),
        child: picture(asset, height: height),
      );
    },
  );
}
