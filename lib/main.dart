import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/settings.dart';
import 'theme/theme.dart';
import 'utils/theme_controller.dart';
import 'utils/theme_presets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  themeController = await ThemeController.load();
  runApp(const Application());
}

// Router configuration
final GoRouter _router = GoRouter(
  initialLocation: '/settings',
  routes: [
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);

class Application extends StatelessWidget {
  const Application({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemePreset>(
    valueListenable: themeController,
    builder: (context, preset, _) {
      final light = buildTheme(preset.light);
      final dark = buildTheme(preset.dark);

      return MaterialApp.router(
        debugShowCheckedModeBanner: false,
        supportedLocales: const [
          Locale('en', 'US'),
          ...FLocalizations.supportedLocales,
        ],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: light.toApproximateMaterialTheme(),
        darkTheme: dark.toApproximateMaterialTheme(),
        builder: (context, child) => FTheme(
          data: Theme.brightnessOf(context) == Brightness.light ? light : dark,
          child: FToaster(
            child: FTooltipGroup(child: child!),
          ),
        ),
        routerConfig: _router,
      );
    },
  );
}