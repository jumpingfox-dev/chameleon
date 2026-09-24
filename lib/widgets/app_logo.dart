import 'package:flutter_svg/flutter_svg.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

/// The app logo, filled with a gradient from the current theme.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.asset = 'assets/images/logo.svg', this.height = 32});

  final String asset;
  final double height;

  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.srcIn, // keep the logo's shape, fill it with the gradient
    shaderCallback: (bounds) => LinearGradient(
      colors: [
        context.theme.colors.primary,
        context.theme.colors.secondary,
      ],
    ).createShader(bounds),
    child: SvgPicture.asset(asset, height: height),
  );
}