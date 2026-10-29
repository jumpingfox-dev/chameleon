import 'package:chameleon/core/storage/app_defaults.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await appDefaults.load(); // assets/defaults.json
  });

  tearDown(() => appDefaults.server = const {});

  test("a server's defaults take precedence over the file's, each as its kind", () {
    appDefaults.server = {
      'headingFont': '"Inter"',
      'bottomBar': 'home, settings',
      'autoplayNext': 'false',
      'countdownSeconds': '20',
      'skipIntro': 'auto',
      'home': 'carousel, genres',
    };
    expect(appDefaults.appearance('headingFont'), 'Inter');
    expect(appDefaults.strings('bottomBar', sectionName: 'appearance'), ['home', 'settings']);
    expect(appDefaults.strings('home'), ['carousel', 'genres']);
    final playback = appDefaults.settings('playback', const [], const {'skip'});
    expect(playback['autoplayNext'], false);
    expect(playback['countdownSeconds'], 20);
    expect((playback['skip'] as Map)['intro'], 'auto');
    expect((playback['skip'] as Map)['recap'], 'ask'); // the file's, where the server says nothing
  });

  test("without a server's, the file's", () {
    expect(appDefaults.appearance('headingFont'), isNot('Inter'));
  });

  test("a server's Home section defaults, over the file's", () {
    appDefaults.server = {
      'sectionContinueWatchingLimit': '50',
      'sectionCarouselShowTitle': 'yes',
      'sectionGenresGenreCount': '6',
      'sectionFavoritesKinds': 'Movie, Season',
      'sectionFavoritesNamesSeason': 'false',
      'sectionRecentlyAddedMoviesLimit': '10',
      'sectionGenreLimit': '20',
    };
    final longer = {'recentlyAdded': ['recentlyAddedMovies', 'recentlyAddedSeries']};
    Map<String, dynamic> of(String type) => appDefaults.sectionDefaults(type, longer: longer[type] ?? const []);

    expect(of('continueWatching')['limit'], 50);
    expect(of('continueWatching')['episodeTitleStyle'], 'both'); // the file's
    expect(of('carousel')['showTitle'], true);
    expect(of('genres')['genreCount'], 6); // a number where the file has "all"
    expect(of('favorites')['kinds'], ['Movie', 'Season']);
    expect((of('favorites')['names'] as Map)['Season'], false);
    expect((of('favorites')['names'] as Map)['Episode'], true);
    // Sections whose names start alike keep to their own.
    expect(of('recentlyAddedMovies')['limit'], 10);
    expect(of('recentlyAdded')['limit'], 30);
    expect(of('genre')['limit'], 20);
    expect(of('genres').containsKey('limit'), false);
  });
}
