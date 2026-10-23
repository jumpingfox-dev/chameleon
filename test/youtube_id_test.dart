import 'package:chameleon/features/previews/trailers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('YouTube addresses give their video id', () {
    expect(youTubeId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(youTubeId('http://youtube.com/watch?feature=share&v=dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(youTubeId('https://youtu.be/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(youTubeId('https://m.youtube.com/embed/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(youTubeId('https://www.youtube.com/shorts/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
  });

  test('anything else gives nothing', () {
    expect(youTubeId(null), isNull);
    expect(youTubeId('https://vimeo.com/12345'), isNull);
    expect(youTubeId('https://www.youtube.com/channel/abc'), isNull);
    expect(youTubeId('not a url'), isNull);
  });
}
