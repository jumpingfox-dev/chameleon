import 'package:forui/forui.dart';
import 'package:forui_phosphor/forui_phosphor.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../screens/home.dart';
import '../screens/search.dart';
import '../screens/settings.dart';

/// Every page in the nav bar. Add a line here to add a page.
typedef AppDestination = ({String label, IconData icon, String path, Widget Function() screen});

final destinations = <AppDestination>[
  (label: 'Home', icon: FPhosphorIcons.house, path: '/home', screen: () => const HomeScreen()),
  (label: 'Search', icon: FPhosphorIcons.magnifyingGlass, path: '/search', screen: () => const SearchScreen()),
  (label: 'Settings', icon: FPhosphorIcons.gear, path: '/settings', screen: () => const SettingsScreen()),
  //(label: 'Example', icon: FPhosphorIcons.books, path: '/example', screen: () => const ExampleScreen()),
];

/// Below this width, the nav bar moves to the bottom.
const _phoneBreakpoint = 600.0;

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _go(int index) => navigationShell.goBranch(
    index,
    // Tapping the current tab again returns to that tab's first page.
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < _phoneBreakpoint;

    return FScaffold(
      childPad: false,
      header: isPhone
          ? null
          : SafeArea(
        bottom: false, // only pad the top (status bar / camera)
        child: _TopNavBar(currentIndex: navigationShell.currentIndex, onSelect: _go),
      ),
      footer: isPhone
          ? SafeArea(
        top: false, // only pad the bottom (home / back / app switcher buttons)
        child: FBottomNavigationBar(
          index: navigationShell.currentIndex,
          onChange: _go,
          children: [
            for (final d in destinations)
              FBottomNavigationBarItem(icon: Icon(d.icon), label: Text(d.label)),
          ],
        ),
      )
          : null,
      child: SafeArea(
        // Phone: no top bar, so the page itself must avoid the camera; the bottom bar handles the bottom.
        // Wider screens: the top bar handles the top, so the page only avoids the bottom.
        top: isPhone,
        bottom: !isPhone,
        child: navigationShell,
      ),
    );
  }
}

class _TopNavBar extends StatelessWidget {
  const _TopNavBar({required this.currentIndex, required this.onSelect});

  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.theme.colors.border)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SvgPicture.asset(
            'assets/images/text_logo.svg',
            height: 28,
            colorFilter: ColorFilter.mode(context.theme.colors.primary, BlendMode.srcIn)
          ),
          const SizedBox(width: 12),
          Expanded(
            // Scrolls sideways if there are more pages than fit.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 4,
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    FButton(
                      variant: i == currentIndex ? .secondary : .ghost,
                      size: .sm,
                      mainAxisSize: .min,
                      onPress: () => onSelect(i),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 6,
                        children: [
                          Icon(destinations[i].icon, size: 16),
                          Text(destinations[i].label),
                        ],
                      ),
                    ),
                  FAvatar(image: const AssetImage('')),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}