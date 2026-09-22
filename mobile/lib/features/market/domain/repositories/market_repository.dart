import '../entities/market_entities.dart';
import '../entities/market_event.dart';

/// Domain-owned ports. Implementations can use a network, replay file, or a fake.
abstract interface class MarketRepository {
  Future<CandleHistory> fetchHistory(Uri server, String interval);
  Future<BookSnapshot> fetchBook(Uri server);
  Future<MarketConnection> connect(Uri server);
  void dispose();
}

abstract interface class MarketConnection {
  Stream<MarketEvent> get events;
  void subscribe(String interval, int revision);
  void ping(int nonce);
  void reportMetrics(double rtt, double jitter);
  void setOverride(String tier);
  void skipBookDelta();
  void disconnectForDemo();
  Future<void> close();
}
