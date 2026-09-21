import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

String displayFont = 'Space Grotesk';
String bodyFont = 'Instrument Sans';

// Color parseHexColor(String hexString, {Color fallback = Colors.black}) {
//   try {
//     String hex = hexString.replaceAll('#', '').trim();
//     if (hex.length == 6) {
//       hex = 'FF$hex';
//     }
//     return Color(int.parse(hex, radix: 16));
//   } catch (_) {
//     return fallback;
//   }
// }

// FThemeData parseThemeFromJson(String jsonString, FThemeData baseTheme) {
//   final Map<String, dynamic> data = jsonDecode(jsonString);
//
//   final updatedColorScheme = baseTheme.colors.copyWith(
//     background: data['background'] != null
//         ? parseHexColor(data['background'])
//         : baseTheme.colors.background,
//     primary: data['primary'] != null
//         ? parseHexColor(data['primary'])
//         : baseTheme.colors.primary,
//     foreground: data['foreground'] != null
//         ? parseHexColor(data['foreground'])
//         : baseTheme.colors.foreground,
//     muted: data['muted'] != null
//         ? parseHexColor(data['muted'])
//         : baseTheme.colors.muted,
//   );
//
//   // Pass colorScheme to copyWith
//   return baseTheme.copyWith(colors: updatedColorScheme);
// }