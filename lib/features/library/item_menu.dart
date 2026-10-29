import 'dart:math' as math;

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/downloads/downloads.dart';
import '../../core/format/format.dart';
import '../../core/format/item_format.dart';
import '../../core/jellyfin/jellyfin_controller.dart';
import '../../core/storage/app_cache.dart';
import '../../core/storage/storage.dart';
import '../../theme/app_icons.dart';
import '../../theme/theme.dart';
import '../../widgets/tappable.dart';
import '../detail/detail_page.dart';
import '../home/home_modules.dart' show refreshWatchProgress;
import '../player/player.dart';

// Holding Select on a card (a long press, or a right-click) opens a small menu of what you can
// do with it: play or continue it, see more, favorite it, mark it played, and in Continue
// Watching and Next Up, take it off the list.

/// Where [item] was left off, or zero (a movie or episode).
Duration _position(JellyfinItem item) {
  final userData = item.raw['UserData'] as Map?;
  final ticks = userData?['PlaybackPositionTicks'];
  if (userData?['Played'] == true || ticks is! int || ticks <= 0) return Duration.zero;
  return Duration(microseconds: ticks ~/ 10);
}

/// Plays [item] from where you left off, or [fromStart].
void playFromProgress(BuildContext context, JellyfinItem item, {bool fromStart = false}) => context.push(
  Uri(
    path: '/play/${item.id}',
    queryParameters: {'start': (fromStart ? PlayStart.beginning : PlayStart.resume).name},
  ).toString(),
);

/// Whether [item] has a menu: the things that play (not folders, people and the like).
bool hasItemMenu(JellyfinItem item) => const {
  JellyfinItemKind.movie,
  JellyfinItemKind.series,
  JellyfinItemKind.episode,
  'BoxSet',
  'Video',
}.contains(item.type);

/// The Home list a card is in, for its menu's "Remove from …".
enum ItemMenuList { continueWatching, nextUp }

// ─── Next Up entries you've removed ──────────────────────────────────────────

/// Episode ids taken off Next Up here. The server has no way to hide them, so it's kept on
/// this device: the show comes back once its next episode is a different one.
const _hiddenKey = 'next_up_hidden';

Set<String> hiddenFromNextUp() => {...?storage.getStringList(_hiddenKey)};

Future<void> _hideFromNextUp(String episodeId) async {
  final hidden = [...?storage.getStringList(_hiddenKey), episodeId];
  // The most recent few hundred: enough for anyone, without growing forever.
  await storage.setStringList(_hiddenKey, hidden.sublist(math.max(0, hidden.length - 300)));
}

// ─── The menu ────────────────────────────────────────────────────────────────

typedef _Option = ({IconData icon, String label, Future<void> Function() run});

/// The menu for [item], from [list] if it's in Continue Watching or Next Up.
Future<void> showItemMenu(BuildContext context, JellyfinItem item, {ItemMenuList? list}) {
  final client = jellyfin.client;
  if (client == null) return Future.value();
  final userData = (item.raw['UserData'] as Map?) ?? const {};
  final isEpisode = item.type == JellyfinItemKind.episode;
  final seriesId = item.raw['SeriesId'] as String?;
  final position = _position(item);
  final partway = position > Duration.zero;
  final played = userData['Played'] == true;
  final favorite = userData['IsFavorite'] == true;
  // A show or collection you've started: its Play picks up where you are.
  final started = !partway && ((userData['PlayedPercentage'] as num?) ?? 0) > 0 && !played;
  final playsDirectly = item.type == JellyfinItemKind.movie || isEpisode || item.type == 'Video';

  /// Runs [action] against the server, then refreshes what shows the change.
  Future<void> change(Future<void> Function() action) async {
    try {
      await action();
    } on Exception catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(describeJellyfinError(e))));
      }
      return;
    }
    final ids = {item.id, ?seriesId};
    appCache.invalidateWhere((key) => ids.any((id) => key.endsWith(':$id')));
    refreshWatchProgress();
  }

  final listName = switch (list) {
    ItemMenuList.continueWatching => 'Continue Watching',
    ItemMenuList.nextUp => 'Next Up',
    null => null,
  };

  final options = <_Option>[
    (
      icon: appIcons.play,
      label: partway
          ? 'Continue from ${formatDuration(position)}'
          : started
          ? 'Continue'
          : 'Play',
      run: () async => playsDirectly ? playFromProgress(context, item) : await playItem(context, item),
    ),
    if (partway)
      (icon: appIcons.reset, label: 'Play from beginning', run: () async => playFromProgress(context, item, fromStart: true)),
    (
      icon: appIcons.info,
      label: 'More info',
      // An episode's is its show's page.
      run: () async => isEpisode && seriesId != null ? openSeries(context, seriesId) : openItem(context, item),
    ),
    (
      icon: favorite ? appIcons.favorite : appIcons.favoriteOutline,
      label: favorite ? 'Remove from favorites' : 'Add to favorites',
      run: () => change(() async {
        await client.userData.setFavorite(item.id, !favorite);
        // As the heart on its page does: the Favorites list's cache is out of date (so the
        // Favorites page loads again when it's next opened), and anything showing it is told.
        appCache.invalidateWhere((key) => key == 'favorites');
        favoritesChanged.value++;
      }),
    ),
    (
      icon: appIcons.check,
      label: played ? 'Mark as unplayed' : 'Mark as played',
      run: () => change(() => played ? client.userData.markUnplayed(item.id) : client.userData.markPlayed(item.id)),
    ),
    // Saved on the device for offline (phones and tablets).
    if (downloads.canDownload(item))
      switch (downloads.entry(item.id)?.state) {
        null => (icon: appIcons.download, label: 'Download', run: () => downloads.download(item)),
        DownloadState.complete => (
          icon: appIcons.delete,
          label: 'Remove download',
          run: () => downloads.delete(item.id),
        ),
        _ => (icon: appIcons.close, label: 'Cancel download', run: () => downloads.delete(item.id)),
      },
    if (list == ItemMenuList.nextUp)
      (icon: appIcons.close, label: 'Remove from $listName', run: () => change(() => _hideFromNextUp(item.id)))
    else if (list == ItemMenuList.continueWatching)
      (
        icon: appIcons.close,
        label: 'Remove from $listName',
        // Jellyfin has no way to hide something from it, so this forgets where you were.
        run: () => change(() => client.userData.update(itemId: item.id, raw: {'PlaybackPositionTicks': 0})),
      ),
  ];

  final seriesName = item.raw['SeriesName'] as String?;
  final title = isEpisode && seriesName != null ? seriesName : item.name;
  final runtime = item.raw['RunTimeTicks'];
  final left = partway && runtime is int ? formatRuntime(runtime - position.inMicroseconds * 10) : null;
  final subtitle = [
    if (isEpisode) episodeLabel(item.raw['ParentIndexNumber'], item.raw['IndexNumber'], item.name),
    if (!isEpisode && item.raw['ProductionYear'] != null) '${item.raw['ProductionYear']}',
    if (left != null) '$left left',
  ].join('  ·  ');

  return showGeneralDialog<_Option>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: context.colors.scrim,
    transitionDuration: const Duration(milliseconds: 150),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(animation), child: child),
    ),
    pageBuilder: (context, _, _) => Center(
      child: _ItemMenu(title: title, subtitle: subtitle, options: options),
    ),
  ).then((picked) {
    if (picked != null && context.mounted) picked.run();
  });
}

class _ItemMenu extends StatelessWidget {
  const _ItemMenu({required this.title, required this.subtitle, required this.options});

  final String title;
  final String subtitle;
  final List<_Option> options;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Escape for keyboards. A remote's Back is left to the system, which closes it.
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop()},
      child: SizedBox(
        width: math.min(380, size.width - 32),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 4,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleLarge),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                for (final (i, option) in options.indexed)
                  Tappable(
                    autofocus: i == 0,
                    onPress: () => Navigator.of(context).pop(option),
                    builder: (context, states, _) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isHighlighted(states) ? context.colors.surfaceContainerHighest : context.colors.surfaceContainerHighest.withValues(alpha: 0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        spacing: 12,
                        children: [
                          // The outline heart stays hollow ("not a favorite yet").
                          Icon(option.icon, size: 20, fill: option.icon == appIcons.favoriteOutline ? 0 : 1),
                          Expanded(child: Text(option.label, style: context.text.bodyLarge)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
