import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'jellyfin_controller.dart';

/// Everyone's profile pictures, and each server's list of users, saved on the device: fetched
/// when it connects (see JellyfinController), so "Who's watching?" shows everyone at once. A
/// picture's address has its tag in it, so a new picture is a new address: fetched, and the old
/// one deleted.
abstract final class ProfilePictures {
  static Directory? _dir;

  /// The saved pictures, by address.
  static final _files = <String, File>{};

  /// Each server's users, as last listed (see JellyfinController.publicUsers).
  static var _users = <String, List<PublicUser>>{};

  /// Being fetched, so each is fetched once.
  static final _fetching = <String>{};

  /// The size they're saved at, and decoded at: about the most any is shown. (A full-size
  /// photo took seconds to decode, even from the device.)
  static const _size = 320;

  /// Reads what's saved. Once, at startup.
  static Future<void> init() async {
    try {
      final support = (await getApplicationSupportDirectory()).path;
      // (The first version kept them full size: let go of those.)
      final old = Directory('$support/profile_pictures');
      if (old.existsSync()) unawaited(old.delete(recursive: true).catchError((_) => old));
      final dir = Directory('$support/profile_pictures_$_size');
      await dir.create(recursive: true);
      _dir = dir;
      final index = File('${dir.path}/index.json');
      if (index.existsSync()) {
        for (final MapEntry(:key, :value) in (jsonDecode(await index.readAsString()) as Map<String, dynamic>).entries) {
          final file = File('${dir.path}/$value');
          if (file.existsSync()) _files[key] = file;
        }
      }
      final users = File('${dir.path}/users.json');
      if (users.existsSync()) {
        _users = {
          for (final MapEntry(:key, :value) in (jsonDecode(await users.readAsString()) as Map<String, dynamic>).entries)
            key: [
              for (final u in value as List)
                PublicUser(
                  server: key,
                  id: u['id'] as String,
                  name: u['name'] as String,
                  hasPassword: u['hasPassword'] as bool,
                  imageTag: u['imageTag'] as String?,
                ),
            ],
        };
      }
    } catch (e) {
      debugPrint('Profile pictures: $e'); // unreadable: they're fetched again
    }
  }

  /// The picture at [url]: the saved copy, or from the server (and saved for next time).
  static ImageProvider image(String url) {
    if (_files[url] case final file?) return ResizeImage(FileImage(file), width: _size, policy: ResizeImagePolicy.fit);
    unawaited(save([url]));
    return ResizeImage(NetworkImage(_sized(url)), width: _size, policy: ResizeImagePolicy.fit);
  }

  /// [url], asking the server for it at [_size].
  static String _sized(String url) => '$url${url.contains('?') ? '&' : '?'}maxWidth=$_size&maxHeight=$_size&quality=90';

  /// [server]'s users as last listed, or null if they never have been.
  static List<PublicUser>? usersOf(String server) => _users[server];

  /// Remembers [server]'s users, and saves their pictures.
  static Future<void> rememberUsers(String server, List<PublicUser> users) async {
    _users[server] = users;
    await _write('users.json', {
      for (final MapEntry(:key, :value) in _users.entries)
        key: [
          for (final u in value)
            {'id': u.id, 'name': u.name, 'hasPassword': u.hasPassword, 'imageTag': u.imageTag},
        ],
    });
    await save([for (final u in users) ?u.imageUrl]);
  }

  /// Fetches and saves the pictures at [urls] not saved yet, each replacing that person's
  /// older picture.
  static Future<void> save(Iterable<String> urls) async {
    final dir = _dir;
    if (dir == null) return;
    final wanted = [for (final url in urls) if (!_files.containsKey(url) && _fetching.add(url)) url];
    if (wanted.isEmpty) return;
    var changed = false;
    await Future.wait([
      for (final url in wanted)
        () async {
          try {
            final res = await http.get(Uri.parse(_sized(url))).timeout(const Duration(seconds: 15));
            if (res.statusCode != 200 || res.bodyBytes.isEmpty) return;
            final file = File('${dir.path}/${_nameFor(url)}');
            await file.writeAsBytes(res.bodyBytes);
            // That person's older pictures go.
            final person = _personOf(url);
            for (final old in [for (final u in _files.keys) if (_personOf(u) == person) u]) {
              final oldFile = _files.remove(old);
              if (oldFile != null && oldFile.path != file.path) unawaited(oldFile.delete().catchError((_) => oldFile));
            }
            _files[url] = file;
            changed = true;
          } catch (_) {
            // Unreachable: from the server next time it's shown.
          } finally {
            _fetching.remove(url);
          }
        }(),
    ]);
    if (changed) await _write('index.json', {for (final e in _files.entries) e.key: e.value.uri.pathSegments.last});
  }

  /// Who [url] is a picture of: its server and user, without the tag.
  static String _personOf(String url) {
    final uri = Uri.parse(url);
    return '${uri.origin}${uri.path}|${uri.queryParameters['userId']}';
  }

  static String _nameFor(String url) => '${url.hashCode.toUnsigned(32).toRadixString(16)}-${_personOf(url).hashCode.toUnsigned(32).toRadixString(16)}';

  static Future<void> _write(String name, Object json) async {
    final dir = _dir;
    if (dir == null) return;
    try {
      await File('${dir.path}/$name').writeAsString(jsonEncode(json));
    } catch (e) {
      debugPrint('Profile pictures: $e');
    }
  }
}
