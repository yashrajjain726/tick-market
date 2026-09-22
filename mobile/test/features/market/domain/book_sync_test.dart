import 'package:flutter_test/flutter_test.dart';
import 'package:tick_market/features/market/domain/entities/market_entities.dart';
import 'package:tick_market/features/market/domain/services/book_sync.dart';
import 'package:tick_market/features/market/domain/services/candle_store.dart';
import 'package:tick_market/features/market/domain/services/latency.dart';

BookSnapshot snapshot(int sequence) => BookSnapshot(
  'epoch',
  sequence,
  [for (var i = 0; i < 10; i++) (10000 - i * 10, 100)],
  [for (var i = 0; i < 10; i++) (10100 + i * 10, 100)],
);
BookDelta delta(int n, {int quantity = 200}) =>
    BookDelta('epoch', n, n - 1, [(10000, quantity)], []);
void main() {
  test(
    'unique deltas cannot grow the local book beyond its resource limit',
    () {
      final book = BookSync(maxLevels: 10)
        ..begin('epoch')
        ..install(snapshot(10));
      expect(
        book.receive(const BookDelta('epoch', 11, 10, [(9800, 100)], [])),
        isTrue,
      );
      expect(book.synchronized, isFalse);
      expect(book.bids.length, 10);
      expect(book.sequence, 10);
    },
  );
  test(
    'buffers deltas during REST, discards snapshot-covered events, applies contiguous remainder',
    () {
      final book = BookSync()..begin('epoch');
      book.receive(delta(9));
      book.receive(delta(10));
      book.receive(delta(11, quantity: 300));
      book.receive(delta(12, quantity: 400));
      expect(book.install(snapshot(10)), isTrue);
      expect(book.sequence, 12);
      expect(book.bids.first.$2, 400);
      expect(book.buffered, 0);
      expect(book.synchronized, isTrue);
    },
  );
  test(
    'a gap marks cached book stale; fresh snapshot and queued deltas recover atomically',
    () {
      final book = BookSync()
        ..begin('epoch')
        ..install(snapshot(10));
      expect(book.receive(delta(12)), isTrue);
      expect(book.synchronized, isFalse);
      expect(book.sequence, 10);
      expect(book.bids.first.$2, 100);
      book.receive(delta(13, quantity: 500));
      expect(book.install(snapshot(12)), isTrue);
      expect(book.sequence, 13);
      expect(book.bids.first.$2, 500);
      expect(book.recoveries, 1);
    },
  );
  test(
    'failed buffer replay never exposes partial state; out-of-order forces recovery',
    () {
      final book = BookSync()
        ..begin('epoch')
        ..install(snapshot(10));
      book.begin('epoch');
      book.receive(delta(11));
      book.receive(delta(13));
      expect(book.install(snapshot(10)), isFalse);
      expect(book.sequence, 10);
      expect(book.bids.first.$2, 100);
      expect(book.install(snapshot(13)), isTrue);
      expect(book.receive(delta(12)), isTrue);
      expect(book.synchronized, isFalse);
    },
  );
  test(
    'duplicates are idempotent, wrong epochs ignored, zero removes levels',
    () {
      final book = BookSync()
        ..begin('epoch')
        ..install(snapshot(10));
      expect(book.receive(delta(10)), isFalse);
      expect(book.sequence, 10);
      expect(book.receive(const BookDelta('old', 11, 10, [], [])), isFalse);
      book.receive(
        const BookDelta('epoch', 11, 10, [(9910, 0), (9900, 900)], []),
      );
      expect(book.bids.length, 10);
      expect(book.bids.last, (9900, 900));
    },
  );
  test('buffer is bounded and crossed books are rejected', () {
    final book = BookSync()..begin('epoch');
    for (var i = 1; i <= 512; i++) {
      book.receive(delta(i));
    }
    expect(book.receive(delta(513)), isTrue);
    expect(book.buffered, 0);
    book.install(snapshot(20));
    expect(
      book.receive(const BookDelta('epoch', 21, 20, [(10200, 2)], [])),
      isTrue,
    );
    expect(book.sequence, 20);
  });
  test(
    'candle versions merge without duplicate buckets or backwards volume',
    () {
      const old = Candle(0, 100, 110, 90, 105, 200, 5);
      const newest = Candle(0, 100, 120, 80, 110, 900, 9);
      final store = CandleStore()
        ..merge([newest])
        ..merge([old, newest]);
      expect(store.values.length, 1);
      expect(store.values.single.volume, 900);
      store.merge([]);
      expect(store.values.length, 1);
    },
  );
  test('RTT is EWMA and jitter is mean absolute successive difference', () {
    final latency = LatencyWindow()
      ..add(100)
      ..add(200)
      ..add(100);
    expect(latency.rtt, 118.75);
    expect(latency.jitter, 100);
    latency.reset();
    expect(latency.rtt, isNull);
    expect(latency.jitter, 0);
  });
}
