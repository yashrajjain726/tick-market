import '../../../../core/network/json_transport.dart';
import '../../domain/entities/market_entities.dart';
import '../../domain/entities/market_event.dart';
import '../../domain/repositories/market_repository.dart';
import '../datasources/market_remote_data_source.dart';
import '../models/market_dto.dart';

class RemoteMarketRepository implements MarketRepository {
  final MarketRemoteDataSource source;
  const RemoteMarketRepository(this.source);
  @override
  Future<CandleHistory> fetchHistory(Uri server, String interval) async =>
      MarketDto.history(await source.fetchHistory(server, interval));
  @override
  Future<BookSnapshot> fetchBook(Uri server) async =>
      MarketDto.book(await source.fetchBook(server));
  @override
  Future<MarketConnection> connect(Uri server) async =>
      _RemoteMarketConnection(await source.connect(server));
  @override
  void dispose() => source.dispose();
}

class _RemoteMarketConnection implements MarketConnection {
  final JsonSocket socket;
  _RemoteMarketConnection(this.socket);
  @override
  Stream<MarketEvent> get events => socket.messages.map(MarketDto.event);
  @override
  void subscribe(String interval, int revision) => socket.send({
    'type': 'subscribe',
    'interval': interval,
    'revision': revision,
  });
  @override
  void ping(int nonce) => socket.send({'type': 'ping', 'nonce': nonce});
  @override
  void reportMetrics(double rtt, double jitter) =>
      socket.send({'type': 'metrics', 'rtt': rtt, 'jitter': jitter});
  @override
  void setOverride(String tier) =>
      socket.send({'type': 'override', 'tier': tier});
  @override
  void skipBookDelta() => socket.send({'type': 'debug', 'action': 'skip_book'});
  @override
  void disconnectForDemo() =>
      socket.send({'type': 'debug', 'action': 'disconnect'});
  @override
  Future<void> close() => socket.close();
}
