import 'package:flutter_test/flutter_test.dart';
import 'package:tick_market/features/market/data/datasources/market_remote_data_source.dart';
import 'package:tick_market/features/market/data/repositories/remote_market_repository.dart';
import 'package:tick_market/features/market/domain/entities/market_entities.dart';
import 'package:tick_market/features/market/domain/entities/market_event.dart';
import '../../../support/fake_json_transport.dart';

void main() {
  test(
    'REST adapter maps endpoint responses into typed domain values',
    () async {
      final transport = FakeTransport();
      final repository = RemoteMarketRepository(
        MarketRemoteDataSource(transport),
      );
      final server = Uri.parse('https://example.test:8443');
      final history = repository.fetchHistory(server, '5m');
      expect(
        transport.requests.single.$1.toString(),
        'https://example.test:8443/v1/candles?interval=5m',
      );
      transport.history('5m', [const Candle(0, 100, 110, 90, 105, 200, 5)]);
      final result = await history;
      expect(result.streamId, 'epoch');
      expect(result.interval, '5m');
      expect(result.candles.single.close, 105);
      final book = repository.fetchBook(server);
      expect(transport.requests.last.$1.path, '/v1/book');
      transport.book();
      expect((await book).bids.first, (10000, 100));
      repository.dispose();
    },
  );

  test(
    'socket adapter validates frames, emits typed events, and preserves command protocol',
    () async {
      final transport = FakeTransport();
      final repository = RemoteMarketRepository(
        MarketRemoteDataSource(transport),
      );
      final connection = await repository.connect(
        Uri.parse('https://example.test:8443'),
      );
      expect(
        transport.connections.single.toString(),
        'wss://example.test:8443/v1/stream',
      );
      final events = <MarketEvent>[];
      final subscription = connection.events.listen(events.add);
      transport.hello();
      transport.socket.source.add('{broken');
      transport.socket.emit({'type': 'pong', 'nonce': 7});
      expect(
        events[0],
        isA<MarketOpened>().having((event) => event.streamId, 'epoch', 'epoch'),
      );
      expect(events[1], isA<InvalidMarketMessage>());
      expect(
        events[2],
        isA<PongReceived>().having((event) => event.nonce, 'nonce', 7),
      );
      connection.subscribe('5m', 2);
      connection.ping(7);
      connection.reportMetrics(25, 3);
      connection.setOverride('minimal');
      connection.skipBookDelta();
      connection.disconnectForDemo();
      expect(transport.socket.sent, [
        {'type': 'subscribe', 'interval': '5m', 'revision': 2},
        {'type': 'ping', 'nonce': 7},
        {'type': 'metrics', 'rtt': 25.0, 'jitter': 3.0},
        {'type': 'override', 'tier': 'minimal'},
        {'type': 'debug', 'action': 'skip_book'},
        {'type': 'debug', 'action': 'disconnect'},
      ]);
      await subscription.cancel();
      await connection.close();
      expect(transport.socket.closed, isTrue);
      repository.dispose();
    },
  );
}
