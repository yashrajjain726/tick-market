import '../entities/market_entities.dart';
import '../configuration/market_policy.dart';

class CandleStore {
  final int capacity;
  CandleStore({this.capacity = MarketLimits.retainedCandles});
  final Map<int, Candle> _candles = {};
  List<Candle> get values =>
      _candles.values.toList()..sort((a, b) => a.start.compareTo(b.start));
  void clear() => _candles.clear();
  void merge(Iterable<Candle> incoming) {
    for (final candle in incoming) {
      final old = _candles[candle.start];
      // A slow history response must never overwrite a newer WS candle.
      if (old == null || candle.lastTradeId > old.lastTradeId) {
        _candles[candle.start] = candle;
      }
    }
    if (_candles.length > capacity) {
      final ordered = _candles.keys.toList()..sort();
      for (final key in ordered.take(ordered.length - capacity)) {
        _candles.remove(key);
      }
    }
  }
}
