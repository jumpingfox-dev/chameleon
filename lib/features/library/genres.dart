import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/focus/scroll_into_view.dart';
import '../../core/jellyfin/jellyfin_controller.dart';
import '../../core/theming/server_themes.dart';
import '../../widgets/layered_image.dart';
import '../../core/storage/app_defaults.dart';
import '../../core/storage/storage.dart';
import '../../theme/app_icons.dart';
import '../../theme/theme.dart';
import '../../core/platform/page_insets.dart';
import '../../widgets/tappable.dart';
import 'poster_card.dart';

IconData _iconFor(String genre) {
  final name = genre.toLowerCase();
  for (final (keyword, icon) in appIcons.genreIcons) {
    if (name.contains(keyword)) return icon;
  }
  return appIcons.genres; // anything without a match, in the current icon style
}

// ─── The setting ─────────────────────────────────────────────────────────────

/// How genre cards look (Settings › Appearance › Genre cards).
enum GenreCardStyle {
  icons('Icons'),
  pictures('Jellyfin pictures'),
  /// The server's theme's (see docs/themes.md).
  theme('Theme pictures');

  const GenreCardStyle(this.label);
  final String label;
}

/// The genre card style, saved per person (see Storage.user).
class GenreCardsController extends ValueNotifier<GenreCardStyle> {
  GenreCardsController() : super(_saved());

  static const _key = 'genre_cards';

  static GenreCardStyle _saved() =>
      GenreCardStyle.values.asNameMap()[storage.getString(_key) ?? appDefaults.appearance('genreCards')] ??
      GenreCardStyle.icons;

  /// Loads the style saved for whoever is signed in now.
  void reload() => value = _saved();

  Future<void> select(GenreCardStyle style) async {
    value = style;
    await storage.setString(_key, style.name);
  }
}

late final GenreCardsController genreCards;

// ─── Sizes ───────────────────────────────────────────────────────────────────

/// The room between genre cards.
const genreCardGap = 12.0;

/// A genre card's width: a library thumbnail's, as the Genres page lays them out across the
/// page. Home's Genres section uses the same.
double genreCardWidth(BuildContext context) =>
    libraryCardWidth(
      MediaQuery.sizeOf(context).width - pageSides(context, extra: 12).horizontal,
      LibraryView.thumbnail,
      spacing: genreCardGap,
    );

/// A genre card's width over its height: a thumbnail's 16:9 for icons; for Jellyfin's pictures,
/// theirs (most often square), so they show whole.
double genreCardAspect() {
  if (genreCards.value != GenreCardStyle.pictures) return 16 / 9; // a theme's pictures fill a thumbnail
  final ratios = [
    for (final genre in jellyfin.genres)
      if ((jellyfin.genreItem(genre)?.raw['PrimaryImageAspectRatio'] as num?) case final ratio? when ratio > 0)
        ratio.toDouble(),
  ]..sort();
  return ratios.isEmpty ? 16 / 9 : ratios[ratios.length ~/ 2]; // the usual one
}

// ─── The Genres page ─────────────────────────────────────────────────────────

class GenresScreen extends StatelessWidget {
  const GenresScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Padding(
      padding: pageSides(context, extra: 12),
      child: ListenableBuilder(
        listenable: Listenable.merge([jellyfin, genreCards, serverThemes]),
        builder: (context, _) {
          final genres = jellyfin.genres;
          if (genres.isEmpty) {
            return Center(child: Text('No genres found', style: context.text.bodyLarge));
          }

          return GridView.builder(
            // Room after the last row, so it can come up off the bottom edge like the rest.
            padding: EdgeInsets.only(top: pageTop(context), bottom: pageBottom(context, 64)),
            // As many across as a library's thumbnails.
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: libraryCardMaxWidth(LibraryView.thumbnail),
              mainAxisSpacing: genreCardGap,
              crossAxisSpacing: genreCardGap,
              childAspectRatio: genreCardAspect(),
            ),
            itemCount: genres.length,
            // With the remote, the focused card keeps some room from the screen's edges.
            itemBuilder: (context, i) => KeepClearOfEdges(child: GenreTile(genre: genres[i])),
          );
        },
      ),
    ),
  );
}

// ─── A genre's card ──────────────────────────────────────────────────────────

/// A genre's card, opening the genre's titles: its icon on a color of its own, or the picture
/// Jellyfin has for it (see [genreCards]), with its name. The Genres page and Home's Genres
/// section. It fills the room it's given.
class GenreTile extends StatelessWidget {
  const GenreTile({super.key, required this.genre});

  final String genre;

  @override
  Widget build(BuildContext context) {
    final item = jellyfin.genreItem(genre);
    final tag = item?.imageTags['Primary'];
    final style = genreCards.value;
    final picture = style == GenreCardStyle.pictures && item != null && tag != null;
    // A server theme's pictures: its own, then the server's default, then the icon card.
    final themePictures = style == GenreCardStyle.theme ? serverThemes.genrePicture(genre) : const <ImageProvider>[];
    final colors = context.colors;
    return Tappable(
      // On top of where you are, so Back returns to it.
      onPress: () => context.push('/home/genre/${Uri.encodeComponent(genre)}'),
      semanticsLabel: genre,
      builder: (context, states, child) {
        final active = isHighlighted(states);
        return AnimatedScale(
          scale: active ? 1.04 : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: active ? colors.primary : const Color(0x00000000), width: 3),
            ),
            child: child,
          ),
        );
      },
      child: picture
          ? _PictureCard(genre: genre, item: item, tag: tag)
          : themePictures.isNotEmpty
          ? _ThemePictureCard(genre: genre, pictures: themePictures)
          : _IconCard(genre: genre),
    );
  }
}

/// The name, at the card's bottom left over a fade (so it reads over anything).
class _GenreName extends StatelessWidget {
  const _GenreName(this.genre);

  final String genre;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomLeft,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Text(
        genre,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: context.text.titleMedium?.copyWith(
          color: const Color(0xFFFFFFFF),
          fontWeight: FontWeight.w700,
          shadows: const [Shadow(blurRadius: 6, color: Color(0x80000000))],
        ),
      ),
    ),
  );
}

/// Icons: a deep color of the genre's own (the same every time), its icon large and faint at the
/// right, and its name.
class _IconCard extends StatelessWidget {
  const _IconCard({required this.genre});

  final String genre;

  /// A hue picked from the name, so each genre keeps its color.
  static double _hue(String genre) {
    var h = 0;
    for (final c in genre.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return (h % 360).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final hue = _hue(genre);
    final light = HSLColor.fromAHSL(1, hue, 0.45, 0.36).toColor();
    final dark = HSLColor.fromAHSL(1, (hue + 25) % 360, 0.5, 0.16).toColor();
    return LayoutBuilder(
      builder: (context, constraints) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [light, dark]),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              right: -constraints.maxHeight * 0.12,
              bottom: -constraints.maxHeight * 0.12,
              child: Transform.rotate(
                angle: -0.2,
                child: Icon(
                  _iconFor(genre),
                  size: constraints.maxHeight * 0.85,
                  color: const Color(0x33FFFFFF),
                  fill: 1,
                ),
              ),
            ),
            _GenreName(genre),
          ],
        ),
      ),
    );
  }
}

/// A server theme's picture for the genre, filling the card, with the name over a fade.
class _ThemePictureCard extends StatelessWidget {
  const _ThemePictureCard({required this.genre, required this.pictures});

  final String genre;
  final List<ImageProvider> pictures;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      LayeredImage(pictures: pictures, fit: BoxFit.cover, fallback: _IconCard(genre: genre)),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.5, 1],
            colors: [Color(0x00000000), Color(0xCC000000)],
          ),
        ),
      ),
      _GenreName(genre),
    ],
  );
}

/// Jellyfin's picture for the genre, whole, with the name over a fade at the bottom. Its icon
/// card's color shows until it's in.
class _PictureCard extends StatelessWidget {
  const _PictureCard({required this.genre, required this.item, required this.tag});

  final String genre;
  final JellyfinItem item;
  final String tag;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          jellyfin.client!.images.url(
            itemId: item.id,
            type: JellyfinImagesApi.typePrimary,
            tag: tag,
            fillWidth: (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context)).round(),
            quality: 90,
          ),
          fit: BoxFit.cover,
          frameBuilder: (context, child, frame, loaded) =>
              loaded || frame != null ? child : _IconCard(genre: genre),
          errorBuilder: (_, _, _) => _IconCard(genre: genre),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.5, 1],
              colors: [Color(0x00000000), Color(0xCC000000)],
            ),
          ),
        ),
        _GenreName(genre),
      ],
    ),
  );
}
