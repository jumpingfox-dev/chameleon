/// Waits for requests side by side, like a record's `.wait`, but a failure comes through as it
/// was thrown (a JellyfinException, say), so `on JellyfinException` catches it. `.wait` wraps
/// failures in a ParallelWaitError instead, which slips past those checks.
library;

Future<(A, B)> together2<A, B>(Future<A> a, Future<B> b) async {
  await Future.wait<Object?>([a, b]);
  return (await a, await b);
}

Future<(A, B, C)> together3<A, B, C>(Future<A> a, Future<B> b, Future<C> c) async {
  await Future.wait<Object?>([a, b, c]);
  return (await a, await b, await c);
}
