import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/downloads/downloads.dart';
import '../../theme/app_icons.dart';
import '../../theme/theme.dart';

/// Downloads [item] for offline viewing, shows how far along it is, and once it's done, offers
/// to delete it. Nothing where downloads aren't available (TVs, computers) or the title can't be
/// downloaded. [compact] is just the icon (an episode's row).
class DownloadButton extends StatelessWidget {
  const DownloadButton({super.key, required this.item, this.compact = false, this.style});

  final JellyfinItem item;
  final bool compact;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    if (!downloads.canDownload(item)) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: downloads,
      builder: (context, _) {
        final entry = downloads.entry(item.id);
        final state = entry?.state;
        final (label, icon) = switch (state) {
          null => ('Download', Icon(appIcons.download, size: 18, fill: 1)),
          DownloadState.complete => ('Downloaded', Icon(appIcons.downloaded, size: 18, fill: 1)),
          DownloadState.failed => ('Retry download', Icon(appIcons.refresh, size: 18, fill: 1)),
          DownloadState.paused => ('Paused ${(entry!.progress * 100).floor()}%', Icon(appIcons.download, size: 18)),
          _ => (
            state == DownloadState.queued ? 'Waiting…' : '${(entry!.progress * 100).floor()}%',
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                value: state == DownloadState.queued ? null : entry!.progress,
              ),
            ),
          ),
        };
        void onPress() => switch (state) {
          null => downloads.download(item),
          DownloadState.failed || DownloadState.paused => downloads.resume(item.id),
          _ => _confirmDelete(context, entry!),
        };
        if (compact) {
          return IconButton(
            onPressed: onPress,
            icon: state == DownloadState.complete
                ? Icon(appIcons.downloaded, fill: 1, color: context.colors.primary)
                : icon is Icon
                ? Icon(icon.icon, fill: 1)
                : icon,
          );
        }
        return FilledButton.tonalIcon(style: style, onPressed: onPress, icon: icon, label: Text(label));
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, DownloadEntry entry) async {
    final done = entry.state == DownloadState.complete;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(done ? 'Delete download?' : 'Cancel download?'),
        content: Text(
          done
              ? '${item.name} will be removed from this device. You can download it again later.'
              : 'What has downloaded so far of ${item.name} will be removed.',
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
    if (ok == true) await downloads.delete(item.id);
  }
}
