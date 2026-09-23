import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import 'screens/login.dart';
import 'widgets/app_shell.dart';
import 'theme/theme.dart';
import 'utils/theme_controller.dart';
import 'utils/font_controller.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  themeController = await ThemeController.load();
  fontController = await FontController.load();

  // Clean up in the background so it doesn't delay startup.
  unawaited(pruneFontCache([fontController.display, fontController.body]));

  runApp(const Application());
}

// Router configuration
final GoRouter _router = GoRouter(
  initialLocation: '/home',
  routes: [
    // Outside the shell: no nav bar on the login screen.
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),

    // Inside the shell: every page here gets the nav bar.
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
      branches: [
        for (final d in destinations)
          StatefulShellBranch(
            routes: [GoRoute(path: d.path, builder: (context, state) => d.screen())],
          ),
      ],
    ),
  ],
);

class Application extends StatelessWidget {
  const Application({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([themeController, fontController]),
    builder: (context, _) {
      final theme = buildTheme(
        themeController.value.colors,
        displayFont: fontController.display,
        bodyFont: fontController.body,
      );

      return MaterialApp.router(
        debugShowCheckedModeBanner: false,
        supportedLocales: const [
          Locale('en', 'US'),
          ...FLocalizations.supportedLocales,
        ],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: theme.toApproximateMaterialTheme(),
        builder: (context, child) => FTheme(
          data: theme,
          child: FToaster(
            child: FTooltipGroup(child: child!),
          ),
        ),
        routerConfig: _router,
      );
    },
  );
}