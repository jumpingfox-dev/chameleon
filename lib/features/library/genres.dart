import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/focus/scroll_into_view.dart';
import '../../core/jellyfin/jellyfin_controller.dart';
import '../../theme/app_icons.dart';
import '../../theme/theme.dart';
import '../../core/platform/page_insets.dart';
import '../../core/platform/screen_type.dart';

IconData _iconFor(String genre) {
  final name = genre.toLowerCase();
  for (final (keyword, icon) in appIcons.genreIcons) {
    if (name.contains(keyword)) return icon;
  }
  return appIcons.genres; // anything without a match, in the current icon style
}

class GenresScreen extends StatelessWidget {
  const GenresScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Padding(
      padding: pageSides(context, extra: 12),
      child: ListenableBuilder(
      listenable: jellyfin,
      builder: (context, _) {
        final genres = jellyfin.genres;
        if (genres.isEmpty) {
          return Center(
            child: Text(
              'No genres found',
              style: context.text.bodyLarge,
            ),
          );
        }

        return GridView.builder(
          // Room after the last row, so it can come up off the bottom edge like the rest.
          padding: EdgeInsets.only(top: pageTop(context), bottom: pageBottom(context, 64)),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent:
                200, // tile width; more columns on wider screens
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 16 / 9,
          ),
          itemCount: genres.length,
          itemBuilder: (context, i) {
            // With the remote, the focused tile keeps some room from the screen's edges.
            return KeepClearOfEdges(child: GenreTile(genre: genres[i]));
          },
        );
      },
    ),
    ),
  );
}

/// A genre tile's width in a row (Home's Genres section).
double genreTileWidth(BuildContext context) => ScreenType.of(context).isPhone ? 150.0 : 200.0;

/// A genre's tile: its icon and name, opening the genre's titles. (The Genres page, and Home's
/// Genres section.)
class GenreTile extends StatelessWidget {
  const GenreTile({super.key, required this.genre});

  final String genre;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: genreButtonStyle(context.colors),
    // On top of where you are, so Back returns to it.
    onPressed: () => context.push('/home/genre/${Uri.encodeComponent(genre)}'),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        Icon(_iconFor(genre), size: 32, color: context.colors.primary, fill: 1),
        Text(genre, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}
