import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tick_market/features/market/domain/configuration/market_policy.dart';
import 'package:tick_market/features/market/domain/entities/market_entities.dart';
import 'package:tick_market/features/market/domain/entities/market_event.dart';
import 'package:tick_market/features/market/domain/repositories/market_repository.dart';
import 'package:tick_market/features/market/domain/use_cases/market_session.dart';

const definition = MarketDefinition(
  symbol: 'ETH-EUR',
  name: 'Ether',
  baseAsset: 'ETH',
  quoteAsset: 'EUR',
  quoteSign: '€',
  badge: 'Ξ',
  summaryWindow: '6h',
  supportedIntervals: ['1m', '5m'],
);

class MemoryConnection implements MarketConnection {
  final input = StreamController<MarketEvent>.broadcast(sync: true);
  bool closed = false;
  bool failClose = false;
  @override
  Stream<MarketEvent> get events => input.stream;
  @override
  Future<void> close() async {
    closed = true;
    if (failClose) throw StateError('close failed');
  }

  @override
  void subscribe(String interval, int revision) {}
  @override
  void ping(int nonce) {}
  @override
  void reportMetrics(double rtt, double jitter) {}
  @override
  void setOverride(String tier) {}
  @override
  void skipBookDelta() {}
  @override
  void disconnectForDemo() {}
  void hello(String epoch) => input.add(MarketOpened(epoch, true, definition));
}

class MemoryRepository implements MarketRepository {
  final connections = <Completer<MarketConnection>>[];
  final snapshots = <Completer<BookSnapshot>>[];
  @override
  Future<MarketConnection> connect(Uri server) {
    final pending = Completer<MarketConnection>();
    connections.add(pending);
    return pending.future;
  }

  @override
  Future<BookSnapshot> fetchBook(Uri server) {
    final pending = Completer<BookSnapshot>();
    snapshots.add(pending);
    return pending.future;
  }

  @override
  Future<CandleHistory> fetchHistory(Uri server, String interval) async =>
      CandleHistory('epoch', interval, []);
  @override
  void dispose() {}
}

BookSnapshot snapshot() => BookSnapshot(
  'epoch',
  1,
  [for (var i = 0; i < 10; i++) (10000 - i * 10, 100)],
  [for (var i = 0; i < 10; i++) (10100 + i * 10, 100)],
);
MarketSession session(MemoryRepository repository) => MarketSession(
  repository: repository,
  baseUrl: Uri.parse('http://localhost'),
  random: (_) => 0,
);

void main() {
  testWidgets(
    'concurrent starts share one opening; a late connection after pause is closed',
    (tester) async {
      final repository = MemoryRepository(), connection = MemoryConnection();
      final s = session(repository);
      final first = s.start();
      await s.start();
      expect(repository.connections.length, 1);
      s.setPaused(true);
      repository.connections.single.complete(connection);
      await first;
      expect(connection.closed, isTrue);
      expect(s.connected, isFalse);
      s.dispose();
    },
  );
  testWidgets(
    'malformed bursts coalesce snapshot recovery and preserve bounded request concurrency',
    (tester) async {
      final repository = MemoryRepository(), connection = MemoryConnection();
      final s = session(repository);
      final start = s.start();
      repository.connections.single.complete(connection);
      await start;
      connection.hello('epoch');
      await tester.pump();
      for (var i = 0; i < 100; i++) {
        connection.input.add(const InvalidMarketMessage());
      }
      expect(repository.snapshots.length, 1);
      repository.snapshots.first.complete(snapshot());
      await tester.pump();
      expect(s.book.synchronized, isFalse);
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.snapshots.length, 2);
      repository.snapshots.last.complete(snapshot());
      await tester.pump();
      expect(s.isLive, isTrue);
      expect(s.definition!.name, 'Ether');
      s.dispose();
    },
  );
  testWidgets(
    'missing hello times out even when unsolicited messages keep arriving',
    (tester) async {
      final repository = MemoryRepository(), connection = MemoryConnection();
      final s = session(repository);
      final start = s.start();
      repository.connections.single.complete(connection);
      await start;
      connection.input.add(const PongReceived(999));
      await tester.pump(const Duration(seconds: 8));
      expect(connection.closed, isTrue);
      expect(s.link, LinkState.stale);
      s.dispose();
    },
  );
  testWidgets(
    'new epoch discards old chart; changing servers clears the old book and metadata',
    (tester) async {
      final repository = MemoryRepository(), connection = MemoryConnection();
      final s = session(repository);
      final start = s.start();
      repository.connections.single.complete(connection);
      await start;
      connection.hello('epoch');
      repository.snapshots.first.complete(snapshot());
      await tester.pump();
      s.chart.merge([const Candle(0, 100, 110, 90, 100, 5, 9)]);
      connection.hello('new-epoch');
      expect(s.candles, isEmpty);
      connection.failClose = true;
      s.setPaused(true);
      s.changeServer('https://example.test');
      expect(s.book.bids, isEmpty);
      expect(s.definition, isNull);
      s.dispose();
      s.dispose();
      await tester.pump();
    },
  );
  test(
    'retry policy is capped, jittered, and rejects inconsistent timings',
    () {
      final policy = SessionPolicy();
      expect(policy.reconnectDelay(0, (_) => 0).inMilliseconds, 1000);
      expect(policy.reconnectDelay(30, (_) => 250).inMilliseconds, 16250);
      expect(
        () => SessionPolicy(staleAfter: const Duration(seconds: 1)),
        throwsArgumentError,
      );
    },
  );
}
