import 'dart:ui' as ui;

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
import 'icon_card_art.dart';

IconData _iconFor(String genre) {
  final name = genre.toLowerCase();
  for (final (keyword, icon) in appIcons.genreIcons) {
    if (name.contains(keyword)) return icon;
  }
  return appIcons.genres; // anything without a match, in the current icon style
}

// ─── The setting ─────────────────────────────────────────────────────────────

/// How genre cards look, on the Genres page and Home's Genres section (Settings › Appearance ›
/// Genre cards).
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
    // No side padding around the page: the grid puts it inside its scrolling, so a card at the
    // edge has room to grow when it's focused.
    body: ListenableBuilder(
        listenable: Listenable.merge([jellyfin, genreCards, serverThemes]),
        builder: (context, _) {
          final genres = jellyfin.genres;
          if (genres.isEmpty) {
            return Center(child: Text('No genres found', style: context.text.bodyLarge));
          }

          return GridView.builder(
            // Room after the last row, so it can come up off the bottom edge like the rest.
            padding: pageSides(context, extra: 12).copyWith(top: pageTop(context), bottom: pageBottom(context, 64)),
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
  );
}

// ─── A genre's card ──────────────────────────────────────────────────────────

/// A genre's card, opening the genre's titles: its icon on a color of its own, or the picture
/// Jellyfin has for it (see [genreCards]), with its name. The Genres page and Home's Genres
/// section. It fills the room it's given.
class GenreTile extends StatelessWidget {
  const GenreTile({super.key, required this.genre, this.nameInside = true});

  final String genre;

  /// Its name on the card; false when it's named under it instead (Home's Genres, if set to).
  final bool nameInside;

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
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: active ? cardHoverShadow : const [], // lifted off the page
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: active ? colors.primary : colors.primary.withValues(alpha: 0), width: 3),
            ),
            child: child,
          ),
        );
      },
      child: picture
          ? _PictureCard(genre: genre, item: item, tag: tag, showName: nameInside)
          : themePictures.isNotEmpty
          ? _ThemePictureCard(genre: genre, pictures: themePictures, showName: nameInside)
          : IconCard(name: genre, icon: _iconFor(genre), showName: nameInside),
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

/// Icons: a deep color of its own (the same every time, from its [name]), its [icon] large and
/// faint at the right, and its name. A genre's card, and a library's in My Media. The color and
/// icon are a picture, made once (see IconCardArt).
class IconCard extends StatelessWidget {
  const IconCard({super.key, required this.name, required this.icon, this.showName = true});

  final String name;
  final IconData icon;

  /// Its name on it (not when it's named under it instead).
  final bool showName;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final ratio = MediaQuery.devicePixelRatioOf(context);
          final width = (constraints.maxWidth * ratio).round(), height = (constraints.maxHeight * ratio).round();
          return _IconCardPicture(
            name: name,
            icon: icon,
            width: width,
            height: height,
          );
        },
      ),
      if (showName) _GenreName(name),
    ],
  );
}

class _IconCardPicture extends StatefulWidget {
  const _IconCardPicture({required this.name, required this.icon, required this.width, required this.height});

  final String name;
  final IconData icon;
  final int width;
  final int height;

  @override
  State<_IconCardPicture> createState() => _IconCardPictureState();
}

class _IconCardPictureState extends State<_IconCardPicture> {
  ui.Image? _image;
  Object? _for;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_IconCardPicture old) {
    super.didUpdateWidget(old);
    _load();
  }

  void _load() {
    final w = widget;
    if (w.width <= 0 || w.height <= 0 || !w.width.isFinite) return;
    final key = (w.name, w.icon, w.width, w.height);
    if (key == _for) return;
    _for = key;
    IconCardArt.of(w.name, w.icon, w.width, w.height).then((image) {
      if (mounted && key == _for) setState(() => _image = image);
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    // Just its color until the picture's ready (a moment, the first time).
    if (image == null) {
      return DecoratedBox(decoration: BoxDecoration(gradient: IconCardArt.gradientOf(widget.name)));
    }
    return RawImage(image: image, fit: BoxFit.fill, filterQuality: FilterQuality.medium);
  }
}

/// A server theme's picture for the genre, filling the card, with the name over a fade.
class _ThemePictureCard extends StatelessWidget {
  const _ThemePictureCard({required this.genre, required this.pictures, this.showName = true});

  final String genre;
  final List<ImageProvider> pictures;
  final bool showName;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      LayeredImage(pictures: pictures, fit: BoxFit.cover, fallback: IconCard(name: genre, icon: _iconFor(genre), showName: showName)),
      if (showName) ...[
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
    ],
  );
}

/// Jellyfin's picture for the genre, whole, with the name over a fade at the bottom. Its icon
/// card's color shows until it's in.
class _PictureCard extends StatelessWidget {
  const _PictureCard({required this.genre, required this.item, required this.tag, this.showName = true});

  final String genre;
  final JellyfinItem item;
  final String tag;
  final bool showName;

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
              loaded || frame != null ? child : IconCard(name: genre, icon: _iconFor(genre), showName: showName),
          errorBuilder: (_, _, _) => IconCard(name: genre, icon: _iconFor(genre), showName: showName),
        ),
        if (showName) ...[
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
      ],
    ),
  );
}
