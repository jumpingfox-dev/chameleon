import 'package:chameleon/core/storage/database.dart';
import 'package:chameleon/core/storage/storage.dart';
import 'package:chameleon/features/detail/expandable_text.dart';
import 'package:chameleon/theme/app_icons.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _long = List.filled(40, 'A sentence that goes on for a while.').join(' ');

Widget _boxed(String text, {double width = 400}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, height: 96, child: ExpandableText.fill(text, style: const TextStyle(fontSize: 16))),
    ),
  ),
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await Storage.open(AppDatabase(NativeDatabase.memory()));
    iconController = await IconController.load();
  });

  testWidgets('fill: short text shows whole, with no link', (tester) async {
    await tester.pumpWidget(_boxed('Short.'));
    expect(find.text('Read more'), findsNothing);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('fill: long text fills the room, then scrolls in it when read', (tester) async {
    await tester.pumpWidget(_boxed(_long));
    expect(find.text('Read more'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    // Clipped to the room it has, not overflowing it.
    expect(tester.takeException(), isNull);
    final collapsed = tester.getSize(find.byType(ExpandableText));
    expect(collapsed.height, lessThanOrEqualTo(96));

    await tester.tap(find.text('Read more'));
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.getSize(find.byType(ExpandableText)).height, 96);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).last).position;
    expect(scroll.maxScrollExtent, greaterThan(0));

    // To the end, then back to the clipped text.
    scroll.jumpTo(scroll.maxScrollExtent);
    await tester.pump();
    await tester.tap(find.text('Show less'));
    await tester.pumpAndSettle();
    expect(find.text('Read more'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fill: "Read more" ends inside the room, however the lines break', (tester) async {
    for (var width = 240.0; width <= 720; width += 7) {
      await tester.pumpWidget(_boxed(_long, width: width));
      final box = tester.getRect(find.byType(ExpandableText));
      final link = tester.getRect(find.text('Read more'));
      expect(link.bottom, lessThanOrEqualTo(box.bottom + 0.5), reason: 'at $width wide');
      expect(link.right, lessThanOrEqualTo(box.right + 0.5), reason: 'at $width wide');
    }
  });
}
