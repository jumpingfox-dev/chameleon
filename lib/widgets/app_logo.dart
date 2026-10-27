import 'package:material_ui/material_ui.dart';

import '../core/theming/server_themes.dart';
import '../theme/theme_controller.dart';
import 'layered_image.dart';
import 'server_backdrop.dart';
import 'svg_raster.dart';
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

  /// [svgAsset], rendered from the SVG at the size it's shown (see [SvgRaster]): smooth edges
  /// everywhere, TVs included (drawn as a vector, a TV without multisampling would draw it
  /// jagged). Its PNG copy beside it shows for the moment it takes. [tint] fills it with one
  /// color.
  static Widget picture(String svgAsset, {double? width, double? height, Color? tint}) => SvgAssetImage(
    svgAsset,
    width: width,
    height: height,
    tint: tint,
    placeholder: Image.asset(
      svgAsset.replaceFirst(RegExp(r'\.svg$'), '.png'),
      width: width,
      height: height,
      filterQuality: FilterQuality.medium,
      color: tint,
      colorBlendMode: tint == null ? null : BlendMode.srcIn,
    ),
  );

  /// The "chameleon" wordmark, which a server's theme can replace with its own logo.
  bool get _isWordmark => asset.contains('text_logo');

  @override
  Widget build(BuildContext context) {
    final own = _own();
    if (!_isWordmark) return own;
    // On a server's sign-in pages: that server's logo, already loaded (see ServerBranding).
    if (SignInBrandingScope.maybeOf(context) case final branding?) {
      if (branding.logo.isEmpty) return own;
      return LayeredImage(pictures: branding.logo, height: height, fallback: own);
    }
    // A server's logo (its theme's, or its default) in place of the wordmark, when it has one
    // that loads; else the wordmark (see docs/themes.md).
    return ListenableBuilder(
      listenable: Listenable.merge([serverThemes, themeController]),
      builder: (context, _) {
        final pictures = serverThemes.logo;
        if (pictures.isEmpty) return own;
        return LayeredImage(pictures: pictures, height: height, alignment: Alignment.centerLeft, fallback: own);
      },
    );
  }

  Widget _own() => ValueListenableBuilder<ThemePreset>(
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
