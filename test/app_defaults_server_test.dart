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
}
