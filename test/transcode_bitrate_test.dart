import 'package:chameleon/core/jellyfin/jellyfin_controller.dart';
import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:flutter_test/flutter_test.dart';

JellyfinItem _item(int? bitrate) => JellyfinItem.fromJson({
  'Id': 'a',
  'Name': 'A',
  'Type': 'Movie',
  'MediaSources': [
    {'Id': 'a', 'Bitrate': ?bitrate},
  ],
});

void main() {
  test("a converted picture gets the file's own rate, within the limit, less the sound", () {
    expect(transcodeVideoBitrate(_item(8000000), limit: 18000000), 8000000 - 192000);
    expect(transcodeVideoBitrate(_item(25000000), limit: 18000000), 18000000 - 192000);
    expect(transcodeVideoBitrate(_item(25000000), limit: 60000000, audio: 384000), 25000000 - 384000);
  });

  test('without a known rate, the limit; never below half a megabit', () {
    expect(transcodeVideoBitrate(_item(null), limit: 18000000), 18000000 - 192000);
    expect(transcodeVideoBitrate(_item(300000), limit: 18000000), 500000);
  });
}
