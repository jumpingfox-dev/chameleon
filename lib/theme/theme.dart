import 'package:forui/forui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:forui_phosphor/forui_phosphor.dart';

import '../utils/theme_parser.dart';
import '../utils/theme_presets.dart';

part 'colors.dart';
part 'typography.dart';
part 'style.dart';
part 'icons.dart';

FThemeData buildTheme(FColors colors) {
  // Change this to false to use the desktop variant of this theme.
  const touch = false;

  final typography = _typography(colors: colors, touch: touch);

  final icons = _icons();

  final style = _style(colors: colors, typography: typography, touch: touch);

  return FThemeData(
    colors: colors,
    typography: typography,
    icons: icons,
    style: style,
    touch: touch,
  );
}
