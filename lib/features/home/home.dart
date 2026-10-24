import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../theme/app_icons.dart';
import '../../core/jellyfin/jellyfin_controller.dart';
import 'home_layout.dart';
import '../../core/platform/page_insets.dart';
import 'home_modules.dart';
import '../../theme/theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GoRouter? _router;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_router != null) return; // set up once
    _router = GoRouter.of(context);
    _router!.routerDelegate.addListener(_onNavigate);
  }

  String? _lastPath;

  /// Something was played since Home last showed.
  bool _watched = false;

  /// Leaving Home (to a library, another tab, the player, ...) ends edit mode.
  void _onNavigate() {
    final path = _router!.routerDelegate.currentConfiguration.uri.path;
    final from = _lastPath;
    _lastPath = path;
    if (path.startsWith('/play/')) _watched = true;
    if (homeEditing.value && path != '/home') homeEditing.value = false;
    if (path != '/home' || from == path) return;
    // Back on Home: sections older than 10 minutes may refresh. Not after watching something,
    // though: Home stays as you left it, and only your progress updates (refreshWatchProgress).
    if (_watched) {
      _watched = false;
    } else {
      homeVisible.value++;
    }
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onNavigate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    // No side padding here: each part adds its own (pageSides), so rows can scroll to the edge.
    body: Stack(
      children: [
        ListenableBuilder(
          listenable: Listenable.merge([jellyfin, homeLayout, homeEditing]),
          builder: (context, _) {
            final editing = homeEditing.value;

            return ListView(
              // No side padding: rows scroll edge to edge, everything else adds pageSides.
              padding: EdgeInsets.fromLTRB(0, pageTop(context), 0, pageBottom(context, 8)),
              // While editing, every section is built, off screen too: moving one past the
              // edge would otherwise take it (and the button you're on) away, losing your place.
              scrollCacheExtent: editing ? const ScrollCacheExtent.pixels(100000) : null,
              children: [
                if (editing)
                  Padding(padding: pageSides(context), child: const _EditModeBanner()),

                for (final (i, module) in homeLayout.value.indexed)
                  HomeModuleView(
                    key: ValueKey(
                      module.id,
                    ), // keeps each section's content attached when it moves
                    module: module,
                    editing: editing,
                    isFirst: i == 0,
                    isLast: i == homeLayout.value.length - 1,
                  ),

                if (homeLayout.value.isEmpty && !editing)
                  Padding(
                    padding: pageSides(context).copyWith(top: 48, bottom: 48),
                    child: Center(
                      child: Text(
                        'Your home screen is empty. Select the pencil to add sections.',
                        style: context.text.bodyLarge?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),

                if (editing)
                  Padding(padding: pageSides(context), child: const AddHomeModules()),
              ],
            );
          },
        ),

      ],
    ),
  );
}

/// Shown at the top of the home screen while editing.
class _EditModeBanner extends StatelessWidget {
  const _EditModeBanner();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.primary),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            spacing: 12,
            children: [
              Icon(appIcons.edit, color: colors.primary, fill: 1),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      'Editing your home screen',
                      style: context.text.bodyLarge,
                    ),
                    Text(
                      'Add, remove and rearrange sections. Select Done when you\'re finished.',
                      style: context.text.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}