part of 'settings.dart';

/// Server Settings Tab: the server you're connected to, its libraries, and (for admins) a
/// library scan and who's watching right now.
class _ServerCard extends StatefulWidget {
  const _ServerCard();

  @override
  State<_ServerCard> createState() => _ServerCardState();
}

/// What the server says about itself, and how long it took to answer.
typedef _ServerInfo = ({
  String name,
  String version,
  String? os,
  Duration ping,
  bool updateAvailable,
  bool restartPending,
});

class _ServerCardState extends State<_ServerCard> {
  _ServerInfo? _info;
  bool _infoFailed = false;
  bool _admin = false;
  Map<String, dynamic>? _counts;
  List<Map<String, dynamic>> _watching = const [];

  /// The library scan's progress (0–100) while it runs, or null.
  double? _scan;
  bool _scanStarting = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final watch = Stopwatch()..start();
    try {
      final public = await jellyfin.getJson('/System/Info/Public', auth: false, timeout: const Duration(seconds: 5))
          as Map<String, dynamic>;
      final ping = watch.elapsed;
      final me = await jellyfin.getJson('/Users/Me', timeout: const Duration(seconds: 5)) as Map<String, dynamic>;
      final admin = (me['Policy'] as Map?)?['IsAdministrator'] == true;
      // Admins see the full info: the operating system, and whether an update or restart waits.
      Map<String, dynamic>? full;
      if (admin) {
        try {
          full = await jellyfin.getJson('/System/Info', timeout: const Duration(seconds: 5)) as Map<String, dynamic>;
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _admin = admin;
        _info = (
          name: public['ServerName'] as String? ?? 'Jellyfin',
          version: public['Version'] as String? ?? 'Unknown',
          os: switch (full?['OperatingSystemDisplayName']) {
            final String os when os.trim().isNotEmpty => os,
            _ => null,
          },
          ping: ping,
          updateAvailable: full?['HasUpdateAvailable'] == true,
          restartPending: full?['HasPendingRestart'] == true,
        );
      });
    } catch (_) {
      if (mounted) setState(() => _infoFailed = true);
      return;
    }
    await Future.wait([_loadCounts(), _loadWatching(), _checkScan()]);
  }

  Future<void> _loadCounts() async {
    try {
      final counts = await jellyfin.getJson('/Items/Counts', query: {'userId': jellyfin.client!.userId!})
          as Map<String, dynamic>;
      if (mounted) setState(() => _counts = counts);
    } catch (_) {}
  }

  /// Everyone watching something on the server now (admins only: the server lists other
  /// people's sessions only to them).
  Future<void> _loadWatching() async {
    if (!_admin) return;
    try {
      final sessions = await jellyfin.getJson('/Sessions', query: {'activeWithinSeconds': '960'}) as List;
      if (!mounted) return;
      setState(() {
        _watching = [
          for (final s in sessions)
            if (s is Map<String, dynamic> && s['NowPlayingItem'] != null) s,
        ];
      });
    } catch (_) {}
  }

  /// The "Scan Media Library" task, if it's running: shows its progress, and checks again
  /// every couple of seconds until it's done.
  Future<void> _checkScan() async {
    if (!_admin) return;
    try {
      final tasks = await jellyfin.client!.scheduledTasks.list(isHidden: false);
      final scan = tasks.where((t) => t['Key'] == 'RefreshLibrary').firstOrNull;
      final running = scan?['State'] == 'Running' || scan?['State'] == 'Cancelling';
      if (!mounted) return;
      setState(() {
        _scanStarting = false;
        _scan = running ? ((scan?['CurrentProgressPercentage'] as num?)?.toDouble() ?? 0) : null;
      });
      _poll?.cancel();
      if (running) {
        _poll = Timer(const Duration(seconds: 2), _checkScan);
      } else if (scan != null) {
        unawaited(_loadCounts()); // done: new titles may have arrived
      }
    } catch (_) {}
  }

  Future<void> _startScan() async {
    setState(() => _scanStarting = true);
    try {
      await jellyfin.client!.library.refresh();
      await Future<void>.delayed(const Duration(seconds: 1)); // let the server start the task
      await _checkScan();
    } on JellyfinException catch (e) {
      if (!mounted) return;
      setState(() => _scanStarting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeJellyfinError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final waiting = info == null && !_infoFailed;
    final muted = context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant);
    String count(String key) => '${(_counts?[key] as num?)?.toInt() ?? '…'}';

    return _SettingsCard(
      children: [
        // ── Servers: the ones signed in on this device ──
        const _SectionTitle('Servers', first: true),
        const _ServersSetting(),

        // ── Connection ──
        const _SectionTitle('Connection'),
        _InfoRow(label: 'Server', value: waiting ? '…' : info?.name ?? 'Unreachable'),
        _InfoRow(label: 'Address', value: jellyfin.client?.baseUrl ?? 'Not connected'),
        _InfoRow(label: 'Version', value: waiting ? '…' : info?.version ?? '—'),
        if (info?.os case final os?) _InfoRow(label: 'Running on', value: os),
        _InfoRow(label: 'Response time', value: waiting ? '…' : info == null ? '—' : '${info.ping.inMilliseconds} ms'),
        _InfoRow(
          label: 'Signed in as',
          value: '${jellyfin.userName ?? '—'}${_admin ? ' (administrator)' : ''}',
        ),
        if (info?.updateAvailable ?? false)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('A newer version of Jellyfin is available for this server.', style: muted),
          ),
        if (info?.restartPending ?? false)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('The server is waiting for a restart to apply recent changes.', style: muted),
          ),

        // ── Libraries ──
        if (!_infoFailed) ...[
          const _SectionTitle('Libraries'),
          _InfoRow(label: 'Movies', value: count('MovieCount')),
          _InfoRow(label: 'Shows', value: count('SeriesCount')),
          _InfoRow(label: 'Episodes', value: count('EpisodeCount')),
          if (_admin) ...[
            const SizedBox(height: 12),
            Text(
              'Looks through your media folders for anything new, changed or removed.',
              style: muted,
            ),
            const SizedBox(height: 8),
            if (_scan case final progress?) ...[
              LinearProgressIndicator(value: progress / 100),
              const SizedBox(height: 6),
              Text('Scanning… ${progress.round()}%', style: muted),
            ] else
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _scanStarting ? null : _startScan,
                  icon: Icon(appIcons.refresh, size: 18, fill: 1),
                  label: const Text('Scan all libraries'),
                ),
              ),
          ],
        ],

        // ── Watching now (admins) ──
        if (_admin) ...[
          const _SectionTitle('Watching now', description: 'Everyone playing something on this server.'),
          if (_watching.isEmpty)
            Text('Nothing is playing right now.', style: muted)
          else
            for (final s in _watching) _SessionRow(session: s),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: _loadWatching, child: const Text('Refresh')),
          ),
        ],
      ],
    );
  }
}

/// One person watching: what, where, and whether it's paused or being converted.
class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});

  final Map<String, dynamic> session;

  @override
  Widget build(BuildContext context) {
    final item = session['NowPlayingItem'] as Map<String, dynamic>;
    final series = item['SeriesName'] as String?;
    final title = series == null
        ? item['Name'] as String? ?? ''
        : '$series · ${episodeLabel(item['ParentIndexNumber'], item['IndexNumber'], item['Name'] as String? ?? '')}';
    final paused = (session['PlayState'] as Map?)?['IsPaused'] == true;
    final converting = session['TranscodingInfo'] != null;
    final details = [
      session['UserName'] as String? ?? 'Someone',
      session['DeviceName'] as String? ?? session['Client'] as String? ?? '',
      if (paused) 'Paused',
      converting ? 'Converting' : 'Direct play',
    ].where((s) => s.isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        spacing: 12,
        children: [
          Icon(paused ? Icons.pause_rounded : Icons.play_arrow_rounded, color: context.colors.primary),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  details,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The servers signed in on this device: the one in use, and the others to switch to (on
/// "Who's watching?", with that server's people) or remove. Plus Add a server.
class _ServersSetting extends StatelessWidget {
  const _ServersSetting();

  Future<void> _remove(BuildContext context, String server, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove $name?'),
        content: const Text('Everyone signed in to it on this device is signed out. You can add it again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await jellyfin.forgetServer(server);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: jellyfin,
    builder: (context, _) {
      final current = jellyfin.client?.baseUrl ?? jellyfin.lastServer;
      final muted = context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          for (final server in jellyfin.servers)
            FutureBuilder(
              future: jellyfin.nameOf(server),
              builder: (context, snap) {
                final name = snap.data ?? displayServerUrl(server);
                final inUse = server == current;
                final people = jellyfin.accounts.where((a) => a.server == server).length;
                return Tappable(
                  // Another server: pick who's watching on it.
                  onPress: inUse
                      ? null
                      : () => GoRouter.of(context).push(
                          Uri(path: '/profiles', queryParameters: {'pick': '1', 'server': server}).toString(),
                        ),
                  builder: (context, states, child) => AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                    decoration: BoxDecoration(
                      color: isHighlighted(states) ? context.colors.surfaceContainerHighest : context.colors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: child,
                  ),
                  child: Row(
                    spacing: 12,
                    children: [
                      Icon(appIcons.server, color: inUse ? context.colors.primary : null, fill: 1),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: context.text.titleMedium),
                            Text(
                              '${displayServerUrl(server)} · $people ${people == 1 ? 'account' : 'accounts'}',
                              style: muted,
                            ),
                          ],
                        ),
                      ),
                      if (inUse)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text('In use', style: muted?.copyWith(color: context.colors.primary)),
                        )
                      else
                        IconButton(
                          onPressed: () => _remove(context, server, name),
                          icon: Icon(appIcons.delete, fill: 1),
                        ),
                    ],
                  ),
                );
              },
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              // Sign-in from the start, with the address empty.
              onPressed: () => GoRouter.of(context).push('/login?add=1&fresh=1'),
              icon: Icon(appIcons.server, size: 18, fill: 1),
              label: const Text('Add a server'),
            ),
          ),
        ],
      );
    },
  );
}
