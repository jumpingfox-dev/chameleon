import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every Google Fonts family, alphabetical.
final allFonts = GoogleFonts.asMap().keys.toList()..sort();

/// Shown when the search box is empty.
const suggestedFonts = [
  'Instrument Sans',
  'Space Grotesk',
  'Inter',
  'DM Sans',
  'Manrope',
  'Outfit',
  'Sora',
  'Poppins',
  'Montserrat',
  'Nunito',
  'Work Sans',
  'IBM Plex Sans',
  'Playfair Display',
  'Lora',
  'JetBrains Mono',
];

/// Search: names starting with the query first, then names containing it.
Future<Iterable<String>> searchFonts(String query, {int limit = 40}) async {
  if (query.trim().isEmpty) return suggestedFonts;
  final q = query.trim().toLowerCase();
  final starts = <String>[];
  final contains = <String>[];
  for (final font in allFonts) {
    final name = font.toLowerCase();
    if (name.startsWith(q)) {
      starts.add(font);
    } else if (name.contains(q)) {
      contains.add(font);
    }
  }
  return [...starts, ...contains].take(limit);
}

class FontController extends ChangeNotifier {
  FontController._(this._display, this._body);

  static const defaultDisplay = 'Space Grotesk';
  static const defaultBody = 'Instrument Sans';
  static const _displayKey = 'font_display';
  static const _bodyKey = 'font_body';

  String _display;
  String _body;

  String get display => _display;
  String get body => _body;

  static Future<FontController> load() async {
    final prefs = await SharedPreferences.getInstance();
    String pick(String? saved, String fallback) =>
        saved != null && GoogleFonts.asMap().containsKey(saved) ? saved : fallback;
    return FontController._(
      pick(prefs.getString(_displayKey), defaultDisplay),
      pick(prefs.getString(_bodyKey), defaultBody),
    );
  }

  Future<void> setDisplay(String font) async {
    _display = font;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayKey, font);
  }

  Future<void> setBody(String font) async {
    _body = font;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bodyKey, font);
  }
}

late final FontController fontController;