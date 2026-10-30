import 'dart:math' as math;

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:material_ui/material_ui.dart';

import '../../theme/app_icons.dart';
import '../../core/jellyfin/jellyfin_controller.dart';
import '../../core/platform/page_insets.dart';
import '../../core/platform/screen_type.dart';
import '../../widgets/hover_lift.dart';
import '../../theme/theme.dart';
import '../../widgets/tappable.dart';
import '../previews/card_preview.dart';
import 'item_menu.dart';
import '../previews/frames_preview.dart';
import '../../widgets/focus_slot_row.dart';

enum LibraryView { poster, thumbnail }

/// null = automatic (thumbnails on wide screens, posters on phones).
/// Set by the toggle, and kept while the app is open.
final libraryViewOverride = ValueNotifier<LibraryView?>(null);

LibraryView libraryViewFor(BuildContext context) =>
    libraryViewOverride.value ??
    (ScreenType.of(context).isPhone
        ? LibraryView.poster
        : LibraryView.thumbnail);

/// An outlined rectangle icon at a given aspect ratio, colored like other icons.
/// A wide one means thumbnails, a tall one means posters.
class AspectIcon extends StatelessWidget {
  const AspectIcon({super.key, required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 20, // same footprint as a normal icon
    child: Center(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          border: Border.all(
            color: IconTheme.of(context).color ?? const Color(0xFFFFFFFF),
            width: 1.6,
          ),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );
}

const _gridSpacing = 4.0;
/// A library card's widest, before the grid shares out the row.
double libraryCardMaxWidth(LibraryView view) => _tileWidth(view);
double _tileWidth(LibraryView view) => view == LibraryView.poster ? 170 : 320;
double _aspect(LibraryView view) => view == LibraryView.poster ? 2 / 3 : 16 / 9;

/// How wide a [view] card is in a library grid [width] wide (as many columns as fit, sharing the
/// width), with [spacing] between them. For other grids sized like a library's (genres).
double libraryCardWidth(double width, LibraryView view, {double spacing = _gridSpacing}) {
  final columns = (width / (_tileWidth(view) + spacing)).ceil().clamp(1, 1000);
  return (width - (columns - 1) * spacing) / columns;
}

/// Grid sizing for each view: narrow tall posters, or wider 16:9 thumbnails.
SliverGridDelegate libraryGridDelegate(LibraryView view) =>
    SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: _tileWidth(view),
      mainAxisSpacing: _gridSpacing,
      crossAxisSpacing: _gridSpacing,
      childAspectRatio: _aspect(view),
    );

/// The height a grid of [count] items takes at [width], using the same layout rules as Flutter's grid.
/// The library page uses it to work out where each letter section starts.
double libraryGridHeight(int count, double width, LibraryView view) {
  if (count == 0 || width <= 0) return 0;
  final columns = (width / (_tileWidth(view) + _gridSpacing)).ceil().clamp(
    1,
    1000,
  );
  final tileWidth = (width - (columns - 1) * _gridSpacing) / columns;
  final rows = (count / columns).ceil();
  return rows * (tileWidth / _aspect(view)) + (rows - 1) * _gridSpacing;
}

/// How far through an item you are (0–1), or null when there's nothing to show:
/// not started, or already fully watched.
double? watchProgress(JellyfinItem item) {
  final userData = item.raw['UserData'] as Map?;
  if (userData == null) return null;

  // Series: watched episodes ÷ total episodes.
  if (item.type == JellyfinItemKind.series) {
    final total = item.raw['RecursiveItemCount'] as int?;
    final unplayed = userData['UnplayedItemCount'] as int?;
    if (total == null || total <= 0 || unplayed == null) return null;
    final fraction = (total - unplayed) / total;
    return fraction <= 0 || fraction >= 1 ? null : fraction;
  }

  // Movies and episodes: how far into this one you got.
  if (userData['Played'] == true) return null;
  final percent = userData['PlayedPercentage'] as num?;
  if (percent == null || percent <= 0) return null;
  return (percent / 100).clamp(0.0, 1.0);
}

/// True when an item is fully watched: a finished movie or episode, or a series
/// with every episode watched.
bool isWatched(JellyfinItem item) {
  final userData = item.raw['UserData'] as Map?;
  if (userData == null) return false;
  if (userData['Played'] == true) return true;
  // Series: Jellyfin may only report the unwatched count, so zero left means finished.
  return item.type == JellyfinItemKind.series &&
      userData['UnplayedItemCount'] == 0;
}

/// A round check in the theme's primary color, for the corner of watched artwork.
class WatchedBadge extends StatelessWidget {
  const WatchedBadge({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primary,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 4),
        ], // lifts it off bright artwork
      ),
      child: Icon(
        appIcons.check,
        size: size * 0.6,
        color: colors.onPrimary,
        fill: 1,
      ),
    );
  }
}

/// A thin progress line: the theme's primary color over a dark track.
class WatchProgressBar extends StatelessWidget {
  const WatchProgressBar(this.value, {super.key});

  final double value;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: SizedBox(
      height: 4,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(
            color: Color(0x73000000),
          ), // track: readable on any artwork
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value,
            child: ColoredBox(color: context.colors.primary),
          ),
        ],
      ),
    ),
  );
}

/// The size and spacing of cards in a sideways row (Home's, and a title page's): on wider
/// screens sized to the row, so as many fit whatever the screen: 3½ thumbnails (the half one
/// says there's more), and about 6 posters. Phones keep theirs.
abstract final class CardRows {
  /// The space between a row's cards.
  static const gap = 4.0;

  /// A row's padding at its ends: the first card in line with the page's titles (it rests in
  /// from its edge), and the same room after the last one.
  static EdgeInsets sides(BuildContext context) {
    final sides = pageSides(context);
    return sides.copyWith(right: sides.left);
  }

  /// A card's width in a row showing [across] of them (4.5: the half says there's more), with
  /// [spacing] between, across the room the page has (narrower beside a pinned menu).
  static double acrossWidth(BuildContext context, double across, {double spacing = gap}) {
    final row = MediaQuery.sizeOf(context).width - sides(context).horizontal;
    return (row - (across.ceil() - 1) * spacing) / across;
  }

  /// A card's width in a row.
  static double tileWidth(BuildContext context, LibraryView view) {
    if (ScreenType.of(context).isPhone) return view == LibraryView.poster ? 150.0 : 280.0;
    final row = MediaQuery.sizeOf(context).width - sides(context).horizontal;
    final across = view == LibraryView.poster ? 6.3 : 3.5;
    // The row's width, less the gaps between the cards that show.
    return (row - (across.ceil() - 1) * gap) / across;
  }

  /// The height of a card's picture.
  static double imageHeight(BuildContext context, LibraryView view) {
    final width = tileWidth(context, view);
    return view == LibraryView.poster ? width * 3 / 2 : width * 9 / 16;
  }
}

class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.onPress,
    this.menuList,
    this.view = LibraryView.poster,
    this.preview = true,
    this.onPreviewShowing,
    this.anchor = Alignment.center,
  });

  final JellyfinItem item;
  final VoidCallback onPress;

  /// The Home list it's in, if it's Continue Watching or Next Up: its menu (holding Select, a
  /// long press, or a right-click) can then take it off the list.
  final ItemMenuList? menuList;
  final LibraryView view;

  /// Whether the card plays stills from the title after a moment on it (Settings › Playback).
  /// Off where you're picking up something you've started (Continue Watching, Next Up).
  final bool preview;

  /// Told when the stills start or stop showing (Home's rows widen a poster to 16:9 for them).
  final ValueChanged<bool>? onPreviewShowing;

  /// How tall Home's cards are on wider screens, posters and thumbnails alike (330 pixels on a
  /// 1080p TV), so a poster widened to 16:9 for its preview is a thumbnail's size.
  static const height = 220.0;

  /// Behind a picture boxed in a card of another shape (see _boxed): one soft gradient in the
  /// theme's colors, the same on every card, like the genre and library cards' backgrounds.
  static Widget boxBackground(ColorScheme colors) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(colors.surfaceContainerHighest, colors.primary, 0.22)!,
          Color.lerp(colors.surfaceContainerLow, colors.primary, 0.06)!,
        ],
      ),
    ),
  );

  /// The focus border's width. Stills playing in the card sit just inside it.
  static const borderWidth = 2.5;

  /// What stays put as the card grows on focus: the middle, or a side (a row's first card grows
  /// away from the screen's left edge, its last one away from its right).
  final Alignment anchor;

  /// How far in a resting card sits from each side, for a card [height] tall: the same on
  /// posters and thumbnails (3% of a poster's width and height).
  static EdgeInsets restInset(
    double height, {
    Alignment anchor = Alignment.center,
  }) {
    final x = height * 0.02;
    final y = height * 0.03;
    return EdgeInsets.fromLTRB(x * (1 + anchor.x), y, x * (1 - anchor.x), y);
  }

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  JellyfinItem get item => widget.item;
  LibraryView get view => widget.view;

  /// The width the image is asked for, in pixels: what the card covers on screen, rounded up to
  /// a step of 160 (so the server and cache see few sizes). It only grows, so a poster widening
  /// for its trailer fetches a bigger copy once rather than on every frame.
  int _fillWidth = 0;

  int _fillFor(BuildContext context, Size card) {
    // Pixels per layout unit: the app is laid out at a virtual size and scaled up (UiScaler).
    final pixels =
        View.of(context).physicalSize.width / MediaQuery.sizeOf(context).width;
    // Cropped to fit, the image's width covers the card's width, or its height at its own shape.
    final shape = view == LibraryView.poster || !_hasLandscapeArt
        ? 2 / 3
        : 16 / 9;
    final needed = math.max(card.width, card.height * shape) * pixels;
    final stepped = ((needed / 160).ceil() * 160).clamp(240, 1920);
    if (stepped > _fillWidth) _fillWidth = stepped;
    return _fillWidth;
  }

  bool get _hasLandscapeArt =>
      item.imageTags['Thumb'] != null ||
      ((item.raw['BackdropImageTags'] as List?)?.isNotEmpty ?? false);

  /// Posters use the Primary image. Thumbnails prefer the landscape Thumb image,
  /// then a Backdrop, then fall back to the poster (cropped to fit).
  ///
  /// Not wideImageUrl: this goes through client.images.url() for its quality and sizing,
  /// not a hand-built address.
  /// The card's shape and its picture's don't match, so the picture sits whole in it over
  /// [PosterCard.boxBackground] rather than being cut down to fill it: a season's poster in a
  /// thumbnail (it has no wide picture of its own), an episode's still in a poster.
  bool get _boxed => switch (view) {
    LibraryView.thumbnail =>
      item.type == JellyfinItemKind.season &&
          item.imageTags['Thumb'] == null &&
          ((item.raw['BackdropImageTags'] as List?)?.isEmpty ?? true),
    LibraryView.poster => item.type == JellyfinItemKind.episode,
  };

  String? _imageUrl(JellyfinClient client, int fillWidth) {
    if (view == LibraryView.thumbnail) {
      final thumb = item.imageTags['Thumb'];
      if (thumb != null) {
        return client.images.url(
          itemId: item.id,
          type: JellyfinImagesApi.typeThumb,
          tag: thumb,
          fillWidth: fillWidth,
          quality: 90,
        );
      }
      final backdrops = item.raw['BackdropImageTags'] as List?;
      if (backdrops != null && backdrops.isNotEmpty) {
        return client.images.url(
          itemId: item.id,
          type: JellyfinImagesApi.typeBackdrop,
          tag: backdrops.first as String,
          fillWidth: fillWidth,
          quality: 90,
        );
      }
    }
    final primary = item.imageTags['Primary'];
    if (primary == null) return null;
    return client.images.url(
      itemId: item.id,
      type: JellyfinImagesApi.typePrimary,
      tag: primary,
      fillWidth: fillWidth,
      quality: 90,
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = jellyfin.client; // null for a moment right after sign-out
    final colors = context.colors;

    return Semantics(
      label: item.name,
      button: true,
      child: HoverLift(
        builder: (context, active) => Tappable(
          onPress: widget.onPress,
          onLongPress: hasItemMenu(item) ? () => showItemMenu(context, item, list: widget.menuList) : null,
          // Resting cards sit in a little from their tile's edges; focused, they fill it.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final url = client == null
                  ? null
                  : _imageUrl(client, _fillFor(context, constraints.biggest));
              return AnimatedPadding(
                padding: active
                    ? EdgeInsets.zero
                    : PosterCard.restInset(
                        constraints.maxHeight,
                        anchor: widget.anchor,
                      ),
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  // Hovered or focused: a shadow lifting it off the page.
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: active ? cardHoverShadow : const [],
                  ),
                  // And a border drawn over the artwork's edge (it takes up no space), and around
                  // stills playing in the card.
                  foregroundDecoration: BoxDecoration(
                    border: Border.all(
                      // (In a FocusSlotRow, the row draws it.)
                      color: active && !FocusSlotRow.ownsBorder(context)
                          ? context.colors.primary
                          : context.colors.primary.withValues(alpha: 0),
                      width: PosterCard.borderWidth,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (url != null && _boxed) PosterCard.boxBackground(colors),
                        url == null
                            ? _placeholder(context, colors)
                            : Image.network(
                                url,
                                // A picture of another shape than the card's sits whole in it.
                                fit: _boxed ? BoxFit.contain : BoxFit.cover,
                                gaplessPlayback: true, // a bigger copy replaces the smaller in place
                                width: double.infinity,
                                height: double.infinity,
                                errorBuilder: (_, _, _) =>
                                    _placeholder(context, colors),
                              ),
                        if (watchProgress(item) case final progress?)
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 8,
                            child: WatchProgressBar(progress),
                          ),
                        if (isWatched(item))
                          const Positioned(
                            top: 8,
                            right: 8,
                            child: WatchedBadge(),
                          ),
                        // After a moment on the card, stills from the title play in it (see
                        // Settings › Playback). Not on phones, which have no focus or hover.
                        if (widget.preview &&
                            FramesPreview.supports(item) &&
                            !ScreenType.of(context).isPhone)
                          CardPreview(
                            item: item,
                            active: active,
                            onShowing: widget.onPreviewShowing,
                            // A poster where nothing widens it (a grid): in a 16:9 panel over it.
                            widen: view == LibraryView.poster && widget.onPreviewShowing == null,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context, ColorScheme colors) => ColoredBox(
    color: colors.surfaceContainerHighest,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          item.name,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: context.text.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ),
    ),
  );
}
