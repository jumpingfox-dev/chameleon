import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:dart_jellyfin/dart_jellyfin.dart';

import '../../core/platform/screen_type.dart';
import '../../core/storage/storage.dart';
import '../../core/storage/app_defaults.dart';

// ─── Choices ─────────────────────────────────────────────────────────────────

/// What the screensaver shows.
enum ScreensaverStyle {
  off('Off', 'No screensaver: the screen dims instead'),
  backdrops('Backdrops', 'Artwork from your libraries, one at a time'),
  posters('Poster wall', 'Rows of posters drifting across the screen'),
  clock('Clock', 'A large clock that moves now and then'),
  logo('Floating logo', 'The Chameleon logo gliding around the screen');

  const ScreensaverStyle(this.label, this.description);
  final String label;
  final String description;
}

/// Which titles the artwork comes from.
enum ScreensaverContent {
  all('Movies and shows', [JellyfinItemKind.movie, JellyfinItemKind.series]),
  movies('Movies', [JellyfinItemKind.movie]),
  shows('Shows', [JellyfinItemKind.series]);

  const ScreensaverContent(this.label, this.itemTypes);
  final String label;
  final List<String> itemTypes;
}

enum ScreensaverSpeed {
  slow('Slow', 0.5),
  medium('Medium', 1.0),
  fast('Fast', 2.0);

  const ScreensaverSpeed(this.label, this.factor);
  final String label;
  final double factor;
}

enum ScreensaverSize {
  small('Small', 0.7),
  medium('Medium', 1.0),
  large('Large', 1.35);

  const ScreensaverSize(this.label, this.scale);
  final String label;
  final double scale;
}

enum ClockFormat {
  device('Same as the device'),
  twelve('12-hour (3:45 pm)'),
  twentyFour('24-hour (15:45)');

  const ClockFormat(this.label);
  final String label;
}

enum ScreensaverColor {
  theme('Theme color'),
  white('White'),
  changing('Changing colors');

  const ScreensaverColor(this.label);
  final String label;
}

/// Minutes without a button press before the screensaver starts.
const screensaverStartOptions = [1, 2, 3, 5, 10, 15, 30];

/// With the screensaver off: minutes before the screen dims. 0 means never.
const screensaverDimAfterOptions = [0, 1, 2, 3, 5, 10, 15, 30];

/// Minutes the screensaver keeps the screen on before letting the device sleep as usual.
const screensaverAwakeOptions = [15, 30, 60, 120, 240];

const backdropSecondsOptions = [8, 15, 30, 60];

/// How much darker the screensaver is drawn, in percent.
const screensaverDimOptions = [0, 10, 20, 30, 40, 50, 60];

// ─── The settings ────────────────────────────────────────────────────────────

/// Screensaver preferences, saved per profile like the other settings.
///
/// Change them through [change], which saves and tells listeners:
/// `screensaverSettings.change((s) => s.style = ScreensaverStyle.clock);`
class ScreensaverSettings extends ChangeNotifier {
  ScreensaverSettings._();

  static const _key = 'screensaver_settings';

  // General. On by default on TVs, which sit on one screen for a long time; phones and tablets
  // turn their screens off instead.
  ScreensaverStyle style = ScreenType.isTvDevice ? ScreensaverStyle.logo : ScreensaverStyle.off;
  int startAfter = 3; // minutes
  int dimAfter = 5; // minutes, with the screensaver off; 0 = never
  int awakeFor = 60; // minutes
  bool turnOff = false; // then turn the screen off (and the TV, over HDMI-CEC)
  int dim = 0; // percent darker, one of screensaverDimOptions

  // Backdrops
  ScreensaverContent backdropContent = ScreensaverContent.all;
  int backdropSeconds = 15;
  bool backdropMotion = true;
  bool backdropDetails = true;
  bool backdropClock = true;

  // Poster wall
  ScreensaverContent posterContent = ScreensaverContent.all;
  int posterRows = 3;
  ScreensaverSpeed posterSpeed = ScreensaverSpeed.slow;
  bool posterClock = false;

  // Clock
  ClockFormat clockFormat = ClockFormat.device;
  bool clockDate = true;
  ScreensaverSize clockSize = ScreensaverSize.large;
  ScreensaverColor clockColor = ScreensaverColor.white;
  bool clockArtwork = false;

  // Floating logo
  ScreensaverSize logoSize = ScreensaverSize.medium;
  ScreensaverSpeed logoSpeed = ScreensaverSpeed.medium;
  ScreensaverColor logoColor = ScreensaverColor.changing;

  static Future<ScreensaverSettings> load() async => ScreensaverSettings._().._readSaved();

  void _readSaved() {
    // assets/defaults.json, under anything saved. Its style is one for TVs and one for the rest.
    final defaults = appDefaults.section('screensaver');
    _read({
      ...defaults,
      'style': ?(ScreenType.isTvDevice ? defaults['styleOnTv'] : defaults['styleElsewhere']),
    });
    try {
      final raw = storage.getString(_key);
      if (raw != null) _read(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('ScreensaverSettings.load: $e'); // unreadable: keep the defaults
    }
  }

  /// Loads the settings saved for whoever is signed in now: back to the defaults first, so
  /// nothing carries over from the last person.
  void reload() {
    _read(ScreensaverSettings._()._write());
    _readSaved();
    notifyListeners();
  }

  /// Applies [edit], tells listeners and saves.
  void change(void Function(ScreensaverSettings s) edit) {
    edit(this);
    notifyListeners();
    _save();
  }

  Future<void> _save() async {
    try {
      await storage.setString(_key, jsonEncode(_write()));
    } catch (e) {
      debugPrint('ScreensaverSettings._save: $e');
    }
  }

  Map<String, dynamic> _write() => {
    'style': style.name,
    'startAfter': startAfter,
    'dimAfter': dimAfter,
    'awakeFor': awakeFor,
    'turnOff': turnOff,
    'dim': dim,
    'backdropContent': backdropContent.name,
    'backdropSeconds': backdropSeconds,
    'backdropMotion': backdropMotion,
    'backdropDetails': backdropDetails,
    'backdropClock': backdropClock,
    'posterContent': posterContent.name,
    'posterRows': posterRows,
    'posterSpeed': posterSpeed.name,
    'posterClock': posterClock,
    'clockFormat': clockFormat.name,
    'clockDate': clockDate,
    'clockSize': clockSize.name,
    'clockColor': clockColor.name,
    'clockArtwork': clockArtwork,
    'logoSize': logoSize.name,
    'logoSpeed': logoSpeed.name,
    'logoColor': logoColor.name,
  };

  void _read(Map<String, dynamic> j) {
    // Each value falls back to its default if it's missing or from an older version.
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) => values.asNameMap()[name] ?? fallback;
    bool flag(String key, bool fallback) => j[key] is bool ? j[key] as bool : fallback;
    int number(String key, int fallback) => j[key] is int ? j[key] as int : fallback;

    style = pick(ScreensaverStyle.values, j['style'], style);
    startAfter = number('startAfter', startAfter);
    dimAfter = number('dimAfter', dimAfter);
    awakeFor = number('awakeFor', awakeFor);
    turnOff = flag('turnOff', turnOff);
    dim = number('dim', dim);
    if (!screensaverDimOptions.contains(dim)) dim = 0;
    backdropContent = pick(ScreensaverContent.values, j['backdropContent'], backdropContent);
    backdropSeconds = number('backdropSeconds', backdropSeconds);
    backdropMotion = flag('backdropMotion', backdropMotion);
    backdropDetails = flag('backdropDetails', backdropDetails);
    backdropClock = flag('backdropClock', backdropClock);
    posterContent = pick(ScreensaverContent.values, j['posterContent'], posterContent);
    posterRows = number('posterRows', posterRows).clamp(2, 5);
    posterSpeed = pick(ScreensaverSpeed.values, j['posterSpeed'], posterSpeed);
    posterClock = flag('posterClock', posterClock);
    clockFormat = pick(ClockFormat.values, j['clockFormat'], clockFormat);
    clockDate = flag('clockDate', clockDate);
    clockSize = pick(ScreensaverSize.values, j['clockSize'], clockSize);
    clockColor = pick(ScreensaverColor.values, j['clockColor'], clockColor);
    clockArtwork = flag('clockArtwork', clockArtwork);
    logoSize = pick(ScreensaverSize.values, j['logoSize'], logoSize);
    logoSpeed = pick(ScreensaverSpeed.values, j['logoSpeed'], logoSpeed);
    logoColor = pick(ScreensaverColor.values, j['logoColor'], logoColor);
  }
}

late final ScreensaverSettings screensaverSettings;
