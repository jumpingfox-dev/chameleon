import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../jellyfin/jellyfin_controller.dart';
import '../platform/screen_type.dart';

/// Movies and episodes saved on this device for watching offline: the original file, its
/// pictures and external subtitles, and the details to show and play it without the server.
///
/// Phones and tablets only. Each title lives in a folder of its own under the app's support
/// directory (`downloads/<item id>/`), listed in downloads/index.json. The file itself downloads in
/// the background (it carries on with the app closed), through background_downloader.
final downloads = DownloadsController._();

enum DownloadState { queued, running, paused, complete, failed }

/// One saved title.
class DownloadEntry {
  DownloadEntry({
    required this.item,
    required this.server,
    required this.userId,
    required this.fileName,
    required this.added,
    this.state = DownloadState.queued,
    this.progress = 0,
    this.size,
    this.error,
    Map<int, String>? subtitles,
    this.unsyncedPositionTicks,
    this.unsyncedPlayed = false,
  }) : subtitles = subtitles ?? {};

  /// As the server described it when it was downloaded (its UserData keeps the place you're up
  /// to, offline too).
  JellyfinItem item;
  final String server;
  final String userId;

  /// The file's name in the title's folder, e.g. "media.mkv".
  final String fileName;
  final DateTime added;
  DownloadState state;

  /// 0 to 1 while downloading.
  double progress;

  /// Bytes, once known.
  int? size;
  String? error;

  /// External subtitles saved beside it: the stream's index on the server → file name.
  final Map<int, String> subtitles;

  /// Where you stopped while the server couldn't be told, to tell it later.
  int? unsyncedPositionTicks;
  bool unsyncedPlayed;

  String get id => item.id;

  Map<String, dynamic> toJson() => {
    'item': item.raw,
    'server': server,
    'userId': userId,
    'fileName': fileName,
    'added': added.toIso8601String(),
    // Interrupted mid-download it's picked up again from the downloader's own records.
    'state': state.name,
    'progress': progress,
    'size': ?size,
    'error': ?error,
    'subtitles': {for (final e in subtitles.entries) '${e.key}': e.value},
    'unsyncedPositionTicks': ?unsyncedPositionTicks,
    'unsyncedPlayed': unsyncedPlayed,
  };

  static DownloadEntry fromJson(Map<String, dynamic> json) => DownloadEntry(
    item: JellyfinItem.fromJson(json['item'] as Map<String, dynamic>),
    server: json['server'] as String,
    userId: json['userId'] as String,
    fileName: json['fileName'] as String,
    added: DateTime.tryParse(json['added'] as String? ?? '') ?? DateTime.now(),
    state: DownloadState.values.asNameMap()[json['state']] ?? DownloadState.failed,
    progress: (json['progress'] as num?)?.toDouble() ?? 0,
    size: json['size'] as int?,
    error: json['error'] as String?,
    subtitles: {
      for (final e in ((json['subtitles'] as Map?) ?? const {}).entries) int.parse(e.key as String): e.value as String,
    },
    unsyncedPositionTicks: json['unsyncedPositionTicks'] as int?,
    unsyncedPlayed: json['unsyncedPlayed'] == true,
  );
}

class DownloadsController extends ChangeNotifier {
  DownloadsController._();

  /// Phones and tablets: where watching offline matters. Not TVs or computers.
  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS) && !ScreenType.isTvDevice;

  Directory? _root;
  final _entries = <String, DownloadEntry>{};
  bool _ready = false;

  /// Everything saved or saving, newest first.
  List<DownloadEntry> get all => _entries.values.toList()..sort((a, b) => b.added.compareTo(a.added));

  DownloadEntry? entry(String itemId) => _entries[itemId];

  /// Whether [item] can be downloaded: a movie, episode or video with a file behind it.
  bool canDownload(JellyfinItem item) =>
      supported &&
      const {JellyfinItemKind.movie, JellyfinItemKind.episode, 'Video'}.contains(item.type) &&
      item.raw['LocationType'] != 'Virtual';

  /// The saved file for [itemId], if it's finished and still there.
  File? fileFor(String itemId) {
    final e = _entries[itemId];
    final root = _root;
    if (e == null || root == null || e.state != DownloadState.complete) return null;
    final file = File('${root.path}/${e.id}/${e.fileName}');
    return file.existsSync() ? file : null;
  }

  /// A saved external subtitle's path, by the stream's index on the server.
  String? subtitleFor(String itemId, int streamIndex) {
    final name = _entries[itemId]?.subtitles[streamIndex];
    final root = _root;
    if (name == null || root == null) return null;
    final file = File('${root.path}/$itemId/$name');
    return file.existsSync() ? file.path : null;
  }

  /// A saved picture: 'primary', 'backdrop' or 'series' (an episode's show's poster).
  File? imageFor(String itemId, String kind) {
    final root = _root;
    if (root == null) return null;
    final file = File('${root.path}/$itemId/$kind.jpg');
    return file.existsSync() ? file : null;
  }

  /// Bytes used by finished downloads.
  int get bytesUsed => [
    for (final e in _entries.values)
      if (e.state == DownloadState.complete) e.size ?? 0,
  ].fold(0, (a, b) => a + b);

  /// Call once at startup.
  Future<void> init() async {
    if (!supported || _ready) return;
    _ready = true;
    try {
      _root = Directory('${(await getApplicationSupportDirectory()).path}/downloads');
      await _root!.create(recursive: true);
      await _readIndex();
      final downloader = FileDownloader();
      downloader.configureNotification(
        running: const TaskNotification('Downloading', '{displayName}'),
        complete: const TaskNotification('Downloaded', '{displayName}'),
        error: const TaskNotification("Couldn't download", '{displayName}'),
        paused: const TaskNotification('Download paused', '{displayName}'),
        progressBar: true,
      );
      downloader.updates.listen(_onUpdate);
      // Picks up what happened while the app was closed, and carries on what was going.
      await downloader.start();
      // Finished while closed, with no update to say so: the file is there.
      for (final e in _entries.values) {
        if (e.state != DownloadState.complete && File('${_root!.path}/${e.id}/${e.fileName}').existsSync()) {
          final task = await downloader.taskForId(e.id);
          if (task == null) {
            e
              ..state = DownloadState.complete
              ..progress = 1;
            e.size ??= File('${_root!.path}/${e.id}/${e.fileName}').lengthSync();
          }
        }
      }
      await _writeIndex();
      notifyListeners();
    } catch (e) {
      debugPrint('Downloads.init: $e');
    }
  }

  /// Starts saving [item] (as fetched from the server, with its media sources) for offline.
  Future<void> download(JellyfinItem item) async {
    final client = jellyfin.client;
    final root = _root;
    final base = client?.baseUrl;
    final userId = client?.userId;
    if (!canDownload(item) || client == null || root == null || base == null || userId == null) return;
    if (_entries.containsKey(item.id)) return;

    // The full item: media sources and streams, for the file name and the subtitles.
    final full = item.raw['MediaSources'] == null ? await client.items.byId(item.id) ?? item : item;
    final source = (full.raw['MediaSources'] as List?)?.firstOrNull as Map?;
    final container = ((source?['Container'] as String?) ?? 'mkv').split(',').first;
    final entry = DownloadEntry(
      item: full,
      server: base,
      userId: userId,
      fileName: 'media.$container',
      added: DateTime.now(),
      size: source?['Size'] as int?,
    );
    _entries[item.id] = entry;
    notifyListeners();
    await Directory('${root.path}/${item.id}').create(recursive: true);
    await _writeIndex();

    // Its progress shows in a notification, which Android 13 and later ask about first.
    final downloader = FileDownloader();
    if (await downloader.permissions.status(PermissionType.notifications) == PermissionStatus.undetermined) {
      await downloader.permissions.request(PermissionType.notifications);
    }

    final name = _displayName(full);
    await downloader.enqueue(
      DownloadTask(
        taskId: item.id,
        url: '$base/Items/${item.id}/Download',
        headers: jellyfin.authHeaders,
        baseDirectory: BaseDirectory.applicationSupport,
        directory: 'downloads/${item.id}',
        filename: entry.fileName,
        displayName: name,
        updates: Updates.statusAndProgress,
        allowPause: true,
        retries: 3,
        transferHints: {TransferHint.userInitiated, TransferHint.largeFile},
      ),
    );
    // The rest is small: alongside, not waiting for the file.
    unawaited(_saveExtras(entry, source));
  }

  Future<void> pause(String itemId) async {
    final task = await FileDownloader().taskForId(itemId);
    if (task is DownloadTask) await FileDownloader().pause(task);
  }

  Future<void> resume(String itemId) async {
    final task = await FileDownloader().taskForId(itemId);
    if (task is DownloadTask) {
      await FileDownloader().resume(task);
    } else if (_entries[itemId] case final e? when e.state == DownloadState.failed) {
      // Gone from the downloader (failed for good): start it again.
      _entries.remove(itemId);
      await download(e.item);
    }
  }

  /// Stops it if it's still downloading, and deletes everything saved for it.
  Future<void> delete(String itemId) async {
    await FileDownloader().cancelTaskWithId(itemId);
    _entries.remove(itemId);
    notifyListeners();
    final root = _root;
    if (root != null) {
      final dir = Directory('${root.path}/$itemId');
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
    await _writeIndex();
  }

  /// Where playback of a saved title stopped, when the server couldn't be told: kept with the
  /// title (so it resumes there offline) and sent to the server later ([syncPositions]).
  Future<void> rememberPosition(String itemId, Duration position, {required bool reported}) async {
    final e = _entries[itemId];
    if (e == null) return;
    final ticks = position.inMicroseconds * 10;
    final runtime = e.item.raw['RunTimeTicks'] as int?;
    final played = runtime != null && runtime > 0 && ticks > runtime * 0.9;
    final userData = Map<String, dynamic>.from((e.item.raw['UserData'] as Map?) ?? const {});
    userData['PlaybackPositionTicks'] = played ? 0 : ticks;
    if (played) userData['Played'] = true;
    e.item = JellyfinItem.fromJson({...e.item.raw, 'UserData': userData});
    if (!reported) {
      e
        ..unsyncedPositionTicks = played ? 0 : ticks
        ..unsyncedPlayed = played;
    }
    await _writeIndex();
  }

  /// Tells the server where you got to while offline. Called once signed in and connected.
  Future<void> syncPositions() async {
    final client = jellyfin.client;
    if (client == null) return;
    var changed = false;
    for (final e in _entries.values) {
      final ticks = e.unsyncedPositionTicks;
      if (ticks == null || e.server != client.baseUrl || e.userId != client.userId) continue;
      try {
        if (e.unsyncedPlayed) {
          await client.userData.markPlayed(e.id);
        } else {
          await client.userData.update(itemId: e.id, raw: {'PlaybackPositionTicks': ticks});
        }
        e
          ..unsyncedPositionTicks = null
          ..unsyncedPlayed = false;
        changed = true;
      } catch (_) {
        return; // still offline: next time
      }
    }
    if (changed) await _writeIndex();
  }

  // ── Updates from the downloader ──

  void _onUpdate(TaskUpdate update) {
    final e = _entries[update.task.taskId];
    if (e == null) return;
    switch (update) {
      case TaskStatusUpdate(:final status, :final exception):
        e.state = switch (status) {
          TaskStatus.enqueued || TaskStatus.waitingToRetry => DownloadState.queued,
          TaskStatus.running => DownloadState.running,
          TaskStatus.paused => DownloadState.paused,
          TaskStatus.complete => DownloadState.complete,
          _ => DownloadState.failed, // failed, canceled, notFound
        };
        if (status == TaskStatus.complete) {
          e.progress = 1;
          final file = File('${_root!.path}/${e.id}/${e.fileName}');
          if (file.existsSync()) e.size = file.lengthSync();
        }
        e.error = switch (status) {
          TaskStatus.notFound => "The server didn't have the file.",
          TaskStatus.failed when exception is TaskHttpException && exception.httpResponseCode == 403 =>
            "Your account isn't allowed to download. An admin can turn on downloads for you in "
                "the server's user settings.",
          TaskStatus.failed => exception?.description ?? 'The download failed.',
          _ => null,
        };
        unawaited(_writeIndex());
      case TaskProgressUpdate(:final progress, :final expectedFileSize):
        if (progress >= 0) e.progress = progress;
        if (expectedFileSize > 0) e.size = expectedFileSize;
    }
    notifyListeners();
  }

  // ── Pictures and subtitles ──

  Future<void> _saveExtras(DownloadEntry e, Map? source) async {
    final client = jellyfin.client;
    final root = _root;
    if (client == null || root == null) return;
    final dir = '${root.path}/${e.id}';
    final item = e.item;

    Future<void> save(String url, String name) async {
      try {
        final res = await http.get(Uri.parse(url), headers: jellyfin.authHeaders);
        if (res.statusCode == 200) await File('$dir/$name').writeAsBytes(res.bodyBytes);
      } catch (_) {
        // A missing picture or subtitle isn't worth failing the download over.
      }
    }

    final primary = item.imageTags['Primary'];
    if (primary != null) {
      await save(
        client.images.url(itemId: item.id, type: JellyfinImagesApi.typePrimary, tag: primary, fillWidth: 720),
        'primary.jpg',
      );
    }
    final backdrop = (item.raw['BackdropImageTags'] as List?)?.firstOrNull as String?;
    final parentBackdrop = (item.raw['ParentBackdropImageTags'] as List?)?.firstOrNull as String?;
    final backdropOwner = backdrop != null ? item.id : item.raw['ParentBackdropItemId'] as String?;
    if ((backdrop ?? parentBackdrop) != null && backdropOwner != null) {
      await save(
        client.images.url(
          itemId: backdropOwner,
          type: JellyfinImagesApi.typeBackdrop,
          tag: backdrop ?? parentBackdrop,
          fillWidth: 1280,
        ),
        'backdrop.jpg',
      );
    }
    final seriesId = item.raw['SeriesId'] as String?;
    final seriesTag = item.raw['SeriesPrimaryImageTag'] as String?;
    if (seriesId != null && seriesTag != null) {
      await save(
        client.images.url(itemId: seriesId, type: JellyfinImagesApi.typePrimary, tag: seriesTag, fillWidth: 480),
        'series.jpg',
      );
    }

    // External text subtitles (ones inside the file come with it).
    final sourceId = (source?['Id'] as String?) ?? item.id;
    for (final stream in ((source?['MediaStreams'] as List?) ?? const []).whereType<Map>()) {
      if (stream['Type'] != 'Subtitle' || stream['IsExternal'] != true || stream['IsTextSubtitleStream'] == false) {
        continue;
      }
      final index = stream['Index'] as int?;
      if (index == null) continue;
      final ext = switch ((stream['Codec'] as String?)?.toLowerCase()) {
        'ass' || 'ssa' => 'ass',
        'webvtt' || 'vtt' => 'vtt',
        _ => 'srt',
      };
      final name = 'subtitle-$index.$ext';
      await save('${client.baseUrl}/Videos/${item.id}/$sourceId/Subtitles/$index/0/Stream.$ext', name);
      if (File('$dir/$name').existsSync()) e.subtitles[index] = name;
    }
    await _writeIndex();
    notifyListeners();
  }

  static String _displayName(JellyfinItem item) {
    final series = item.raw['SeriesName'] as String?;
    if (item.type == JellyfinItemKind.episode && series != null) {
      final s = item.raw['ParentIndexNumber'], ep = item.raw['IndexNumber'];
      return s != null && ep != null ? '$series S$s:E$ep · ${item.name}' : '$series · ${item.name}';
    }
    return item.name;
  }

  // ── The index ──

  File get _indexFile => File('${_root!.path}/index.json');

  Future<void> _readIndex() async {
    try {
      final file = _indexFile;
      if (!file.existsSync()) return;
      for (final json in jsonDecode(await file.readAsString()) as List) {
        final e = DownloadEntry.fromJson(json as Map<String, dynamic>);
        _entries[e.id] = e;
      }
    } catch (e) {
      debugPrint('Downloads index: $e');
    }
  }

  /// Written whole, through a temporary file, so a crash mid-write can't leave half an index.
  Future<void> _writeIndex() async {
    if (_root == null) return;
    final tmp = File('${_root!.path}/index.json.tmp');
    await tmp.writeAsString(jsonEncode([for (final e in _entries.values) e.toJson()]));
    await tmp.rename(_indexFile.path);
  }
}
