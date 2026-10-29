import 'dart:io';

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/downloads/downloads.dart';
import '../../core/format/format.dart';
import '../../core/format/item_format.dart';
import '../../core/platform/page_insets.dart';
import '../../theme/app_icons.dart';
import '../../theme/theme.dart';
import '../../widgets/tappable.dart';

/// What's saved on this device for watching offline: anything still downloading, then movies,
/// then episodes by show. Everything here plays without the server.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListenableBuilder(
      listenable: downloads,
      builder: (context, _) {
        final muted = context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant);
        if (!DownloadsController.supported) {
          return Center(child: Text('Downloads are for phones and tablets.', style: muted));
        }
        final all = downloads.all;
        if (all.isEmpty) {
          return Center(
            child: Padding(
              padding: pageSides(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  Icon(appIcons.download, size: 40, color: context.colors.onSurfaceVariant, fill: 1),
                  Text('Nothing downloaded yet', style: context.text.titleLarge),
                  Text(
                    'Download a movie or an episode from its page, or hold it anywhere and choose '
                    'Download, to watch it without a connection.',
                    textAlign: TextAlign.center,
                    style: muted,
                  ),
                ],
              ),
            ),
          );
        }

        final going = [for (final e in all) if (e.state != DownloadState.complete) e];
        final done = [for (final e in all) if (e.state == DownloadState.complete) e];
        final movies = [for (final e in done) if (e.item.type != JellyfinItemKind.episode) e];
        // Episodes by show, shows in the order their latest episode was downloaded, and each
        // show's episodes in order.
        final shows = <String, List<DownloadEntry>>{};
        for (final e in done.where((e) => e.item.type == JellyfinItemKind.episode)) {
          shows.putIfAbsent((e.item.raw['SeriesName'] as String?) ?? 'Episodes', () => []).add(e);
        }
        for (final episodes in shows.values) {
          int order(DownloadEntry e) =>
              ((e.item.raw['ParentIndexNumber'] as int?) ?? 0) * 10000 + ((e.item.raw['IndexNumber'] as int?) ?? 0);
          episodes.sort((a, b) => order(a).compareTo(order(b)));
        }

        return ListView(
          padding: pageSides(context).copyWith(top: pageTop(context), bottom: pageBottom(context, 24)),
          children: [
            if (going.isNotEmpty) ...[
              _Heading('Downloading'),
              for (final e in going) _DownloadTile(entry: e),
            ],
            if (movies.isNotEmpty) ...[
              _Heading('Movies'),
              for (final e in movies) _DownloadTile(entry: e),
            ],
            for (final MapEntry(key: show, value: episodes) in shows.entries) ...[
              _Heading(show),
              for (final e in episodes) _DownloadTile(entry: e),
            ],
            const SizedBox(height: 16),
            Text(
              '${formatBytes(downloads.bytesUsed)} used on this device',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ],
        );
      },
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(text, style: context.text.titleLarge),
  );
}

/// One saved (or saving) title: its picture, name, size or progress, and what you can do with
/// it. Selecting a finished one plays it.
class _DownloadTile extends StatelessWidget {
  const _DownloadTile({required this.entry});

  final DownloadEntry entry;

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    final isEpisode = item.type == JellyfinItemKind.episode;
    final done = entry.state == DownloadState.complete;
    final muted = context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant);
    final title = isEpisode
        ? episodeLabel(item.raw['ParentIndexNumber'], item.raw['IndexNumber'], item.name)
        : item.name;
    final status = switch (entry.state) {
      DownloadState.complete => [
        if (item.raw['ProductionYear'] != null && !isEpisode) '${item.raw['ProductionYear']}',
        ?formatRuntime(item.raw['RunTimeTicks']),
        if (entry.size != null) formatBytes(entry.size!),
      ].join(' · '),
      DownloadState.queued => 'Waiting…',
      DownloadState.running =>
        '${(entry.progress * 100).floor()}%${entry.size == null ? '' : ' of ${formatBytes(entry.size!)}'}',
      DownloadState.paused => 'Paused at ${(entry.progress * 100).floor()}%',
      DownloadState.failed => entry.error ?? "Couldn't download",
    };
    final image = downloads.imageFor(item.id, 'primary') ??
        downloads.imageFor(item.id, 'backdrop');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Tappable(
        onPress: done ? () => context.push('/play/${item.id}') : null,
        builder: (context, states, child) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isHighlighted(states) ? context.colors.surfaceContainerHigh : context.colors.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHighlighted(states) ? context.colors.primary : context.colors.primary.withValues(alpha: 0),
              width: 2,
            ),
          ),
          child: child,
        ),
        child: Row(
          spacing: 12,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: isEpisode ? 128 : 60,
                height: isEpisode ? 72 : 90,
                child: image == null
                    ? ColoredBox(
                        color: context.colors.surfaceContainerHighest,
                        child: Icon(appIcons.movies, color: context.colors.onSurfaceVariant),
                      )
                    : Image.file(File(image.path), fit: BoxFit.cover),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
                  Text(
                    status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: entry.state == DownloadState.failed ? muted?.copyWith(color: context.colors.error) : muted,
                  ),
                  if (!done && entry.state != DownloadState.failed)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: entry.state == DownloadState.queued ? null : entry.progress,
                        minHeight: 4,
                      ),
                    ),
                ],
              ),
            ),
            if (done)
              Icon(appIcons.play, color: context.colors.primary, fill: 1)
            else if (entry.state == DownloadState.running)
              IconButton(
                onPressed: () => downloads.pause(item.id),
                icon: Icon(appIcons.pause, fill: 1),
              )
            else if (entry.state == DownloadState.paused || entry.state == DownloadState.failed)
              IconButton(
                onPressed: () => downloads.resume(item.id),
                icon: Icon(entry.state == DownloadState.paused ? appIcons.download : appIcons.refresh, fill: 1),
              ),
            IconButton(
              onPressed: () => _confirmDelete(context),
              icon: Icon(done ? appIcons.delete : appIcons.close, fill: 1),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final done = entry.state == DownloadState.complete;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(done ? 'Delete download?' : 'Cancel download?'),
        content: Text(
          done
              ? '${entry.item.name} will be removed from this device. You can download it again later.'
              : 'What has downloaded so far of ${entry.item.name} will be removed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep')),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(done ? 'Delete' : 'Cancel download'),
          ),
        ],
      ),
    );
    if (ok == true) await downloads.delete(entry.id);
  }
}
