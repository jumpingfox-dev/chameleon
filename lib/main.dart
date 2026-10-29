import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:media_kit/media_kit.dart';

import 'app/router.dart';
import 'app/splash.dart';
import 'app/ui_scaler.dart';
import 'core/cast/cast_controller.dart';
import 'core/cast/sync_play_controller.dart';
import 'core/downloads/downloads.dart';
import 'core/focus/focus_rows.dart';
import 'core/jellyfin/jellyfin_controller.dart';
import 'core/platform/orientation.dart';
import 'core/platform/screen_type.dart';
import 'core/storage/app_cache.dart';
import 'core/storage/storage.dart';
import 'features/home/home_layout.dart';
import 'features/player/playback_settings.dart';
import 'features/screensaver/screensaver.dart';
import 'features/screensaver/screensaver_settings.dart';
import 'theme/app_icons.dart';
import 'theme/font_controller.dart';
import 'theme/theme.dart';
import 'theme/theme_controller.dart';
import 'core/storage/app_defaults.dart';
import 'features/library/genres.dart';
import 'core/theming/server_themes.dart';
import 'app/bottom_bar_tabs.dart';
import 'features/home/section_settings.dart';

Future<void> main() async {
  _quietMediaKit();
  // Keeps the system splash up while everything below loads, instead of a blank first frame.
  FlutterNativeSplash.preserve(widgetsBinding: WidgetsFlutterBinding.ensureInitialized());
  await ScreenType.detect(); // before the first frame, which already picks phone or TV layout
  if (ScreenType.isTvDevice) {
    // No touchscreen, so always show where focus is. (Flutter otherwise waits for a key it's
    // sure came from a hardware keyboard, and some remotes don't look like one.)
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    // A TV's system splash is just the background (Android 12+ only fits a small icon), so
    // show the full wordmark while loading.
    runApp(const TvSplash());
    FlutterNativeSplash.remove();
  }
  MediaKit.ensureInitialized();
  // Keep more posters in memory so scrolling back doesn't re-download them.
  PaintingBinding.instance.imageCache
    ..maximumSize = 1500
    ..maximumSizeBytes = 200 << 20; // 200 MB (the default is 100 MB)
  storage = await Storage.open(); // before anything that reads a setting
  await appDefaults.load(); // assets/defaults.json: what each setting starts as
  unawaited(storage.pruneCache(DateTime.now().subtract(AppCache.keepFor)));
  // The server's own themes, as saved for it last time, so one of them can be in use from the
  // first frame (see docs/themes.md). Fetched again once signed in.
  serverThemes = await ServerThemes.load(storage.getString('jf_token') == null ? null : storage.getString('jf_server'));
  themeController = await ThemeController.load();
  fontController = await FontController.load();
  iconController = await IconController.load();
  playbackSettings = await PlaybackSettings.load();
  screensaverSettings = await ScreensaverSettings.load();
  homeLayout = await HomeLayoutController.load();
  genreCards = GenreCardsController();
  sectionSettings = SectionSettings();
  // Everyone has their own settings: load theirs whenever someone else signs in, and again when
  // the server's defaults change (its own, from its Custom CSS: see docs/themes.md).
  void reloadSettings() {
    themeController.reload();
    fontController.reload();
    iconController.reload();
    playbackSettings.reload();
    screensaverSettings.reload();
    homeLayout.reload();
    genreCards.reload();
    sectionSettings.reload();
    bottomBarTabs.defaultsChanged();
  }

  storage.user.addListener(reloadSettings);
  serverThemes.sheetChanged.addListener(reloadSettings);

  jellyfin = JellyfinController();
  await jellyfin.load();
  serverThemes.follow(); // the signed-in server's themes, fetched again

  // Downloads for offline viewing: picks up any that carried on while the app was closed, then
  // tells the server where you got to in them while offline (if it can be reached now).
  unawaited(downloads.init().then((_) => downloads.syncPositions()));

  // Chromecast: finds Chromecasts on the network so the player can offer a cast button.
  // Does nothing where casting isn't available (desktop, or devices without Play services).
  await castController.init();

  // Clean up in the background so it doesn't delay startup. Everyone's fonts stay cached,
  // not just those of whoever is signed in now.
  unawaited(
    pruneFontCache({
      fontController.display,
      fontController.body,
      playbackSettings.subtitleFont,
      ...storage.everyonesValues('font_display'),
      ...storage.everyonesValues('font_body'),
      for (final saved in storage.everyonesValues(PlaybackSettings.storageKey))
        ?PlaybackSettings.subtitleFontIn(saved),
    }),
  );

  syncPlay.openPlayer = (itemId) => appRouter.push('/play/$itemId?syncplay=1');

  runApp(const Application());
  FlutterNativeSplash.remove();
  WidgetsBinding.instance.addPostFrameCallback((_) => AppOrientation.init());
}

class Application extends StatelessWidget {
  const Application({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([themeController, fontController, iconController]),
    builder: (context, _) {
      final theme = buildTheme(
        themeController.value.colors,
        displayFont: fontController.display,
        bodyFont: fontController.body,
      );

      return MaterialApp.router(
        debugShowCheckedModeBanner: false,
        // Select, Enter and Space press a button once, when they go down, not again for every
        // repeat while held: holding Select opens a title's menu (see Tappable), and a remote
        // keeps repeating Select while it's held, which would otherwise press the menu's first
        // option straight away.
        shortcuts: _shortcutsWithoutRepeats,
        scrollBehavior: const MaterialScrollBehavior().copyWith(scrollbars: false),
        theme: theme,
        // No tooltips anywhere (Flutter's own buttons have some): pop-up labels on hover or a
        // long press aren't wanted in this app.
        builder: (context, child) => TooltipVisibility(
          visible: false,
          child: TextFieldArrowEscape(
            child: RowFocusNavigation(child: UiScaler(child: ScreensaverHost(child: child!))),
          ),
        ),
        routerConfig: appRouter,
      );
    },
  );
}

/// The app's default shortcuts, with the keys that press buttons (Select, Enter, Space, a
/// gamepad's A) doing so once per press, not on every repeat while held.
final Map<ShortcutActivator, Intent> _shortcutsWithoutRepeats = {
  for (final MapEntry(:key, :value) in WidgetsApp.defaultShortcuts.entries)
    if (key is SingleActivator && key.includeRepeats && _pressKeys.contains(key.trigger))
      SingleActivator(
        key.trigger,
        control: key.control,
        shift: key.shift,
        alt: key.alt,
        meta: key.meta,
        includeRepeats: false,
      ): value
    else
      key: value,
};

final _pressKeys = {
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.space,
  LogicalKeyboardKey.gameButtonA,
};

/// media_kit logs every video output change it makes ("VideoOutput.Resize" and the like).
/// Drops those, so the log only has the app's own messages.
void _quietMediaKit() {
  final print = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    final m = message ?? '';
    final chatter = m.startsWith('media_kit:') ||
        m.startsWith('VideoOutput.') ||
        m.startsWith('NativeVideoController:') ||
        m.startsWith('AndroidVideoController:') ||
        (m.startsWith('{') && m.contains('handle')) ||
        RegExp(r'^\d+$').hasMatch(m); // a video output's handle on its own
    if (!chatter) print(message, wrapWidth: wrapWidth);
  };
}
