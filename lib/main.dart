import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/settings.dart';
import 'theme/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  Widget build(BuildContext context) => MaterialApp.router(
    debugShowCheckedModeBanner: false,
    supportedLocales: const [
      Locale('en', 'US'),
      ...FLocalizations.supportedLocales,
    ],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: lightTheme.toApproximateMaterialTheme(),
    darkTheme: darkTheme.toApproximateMaterialTheme(),
    builder: (context, child) => FTheme(
      data: Theme.brightnessOf(context) == Brightness.light
          ? lightTheme
          : darkTheme,
      child: FToaster(
        child: FTooltipGroup(child: child!),
      ),
    ),

    // 3. Router Configuration
    routerConfig: _router,
  );
}