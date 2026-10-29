import 'package:chameleon/features/detail/detail_page.dart';
import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:flutter_test/flutter_test.dart';

JellyfinItem _ep(int season, int number, {String? playedAt, bool played = false, int position = 0}) =>
    JellyfinItem.fromJson({
      'Id': 's${season}e$number',
      'Name': 'S$season E$number',
      'Type': 'Episode',
      'ParentIndexNumber': season,
      'IndexNumber': number,
      'UserData': {
        'Played': played,
        'PlaybackPositionTicks': position,
        'LastPlayedDate': ?playedAt,
      },
    });

void main() {
  test('carries on after the episode played most recently, not the furthest one', () {
    final episodes = [
      _ep(1, 5, played: true, playedAt: '2026-10-27T22:00:00Z'), // her, last night
      _ep(1, 6),
      _ep(3, 4, position: 900000000, playedAt: '2026-10-20T20:00:00Z'), // him, a week ago
      _ep(3, 5),
    ];
    final next = continueEpisodeIn(episodes);
    expect(next.episode?.id, 's1e6');
    expect(next.started, isTrue);
  });

  test('the most recent one again, if it was left partway', () {
    final next = continueEpisodeIn([
      _ep(1, 5, played: true, playedAt: '2026-10-20T20:00:00Z'),
      _ep(3, 4, position: 900000000, playedAt: '2026-10-27T22:00:00Z'),
    ]);
    expect(next.episode?.id, 's3e4');
  });

  test('not started: the first regular episode; finished: the first again, as new', () {
    final unstarted = continueEpisodeIn([_ep(0, 1), _ep(1, 2), _ep(1, 1)]);
    expect(unstarted.episode?.id, 's1e1');
    expect(unstarted.started, isFalse);
    final finished = continueEpisodeIn([_ep(1, 1, played: true, playedAt: '2026-10-01T00:00:00Z'), _ep(1, 2, played: true, playedAt: '2026-10-02T00:00:00Z')]);
    expect(finished.episode?.id, 's1e1');
    expect(finished.started, isFalse);
  });
}
