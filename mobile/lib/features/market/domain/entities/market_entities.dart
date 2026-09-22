const intervals = {'1m': 60000, '5m': 300000};
const priceScale = 100;
const quantityScale = 100000000;

/// Version 1 prices are integer cents; quantities are integer 1e-8 asset units.
class Trade {
  final int id, time, price, quantity;
  final bool buy;
  const Trade(this.id, this.time, this.price, this.quantity, this.buy);
}

class Candle {
  final int start, open, high, low, close, volume, lastTradeId;
  const Candle(
    this.start,
    this.open,
    this.high,
    this.low,
    this.close,
    this.volume,
    this.lastTradeId,
  );
}

typedef Level = (int, int);

class BookSnapshot {
  final String streamId;
  final int sequence;
  final List<Level> bids, asks;
  const BookSnapshot(this.streamId, this.sequence, this.bids, this.asks);
}

class BookDelta extends BookSnapshot {
  final int previous;
  const BookDelta(
    super.streamId,
    super.sequence,
    this.previous,
    super.bids,
    super.asks,
  );
}

class CandleHistory {
  final String streamId, interval;
  final List<Candle> candles;
  const CandleHistory(this.streamId, this.interval, this.candles);
}

class MarketSummary {
  final int reference, high, low, volume;
  const MarketSummary(this.reference, this.high, this.low, this.volume);
}

/// Supplied by the server; no product identity is embedded in the screen.
class MarketDefinition {
  final String symbol,
      name,
      baseAsset,
      quoteAsset,
      quoteSign,
      badge,
      summaryWindow;
  final List<String> supportedIntervals;
  const MarketDefinition({
    required this.symbol,
    required this.name,
    required this.baseAsset,
    required this.quoteAsset,
    required this.quoteSign,
    required this.badge,
    required this.summaryWindow,
    required this.supportedIntervals,
  });
}
