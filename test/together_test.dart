import 'package:chameleon/core/jellyfin/together.dart';
import 'package:flutter_test/flutter_test.dart';

class _Offline implements Exception {}

void main() {
  test('results come back in order', () async {
    final (a, b, c) = await together3(Future.value(1), Future.value('two'), Future.value(3.0));
    expect((a, b, c), (1, 'two', 3.0));
  });

  test('a failure comes through as itself, so `on` checks still catch it', () async {
    Future<int> fails() async => throw _Offline();
    expect(together2(Future.value(1), fails()), throwsA(isA<_Offline>()));
    expect(together3(fails(), Future.value(2), Future.value(3)), throwsA(isA<_Offline>()));
  });
}
