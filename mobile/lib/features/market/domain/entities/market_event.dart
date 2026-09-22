import 'market_entities.dart';

/// Typed input to the use case. Wire frames never cross the data boundary.
sealed class MarketEvent {
  const MarketEvent();
}

final class MarketOpened extends MarketEvent {
  final String streamId;
  final bool debugEnabled;
  final MarketDefinition definition;
  const MarketOpened(this.streamId, this.debugEnabled, this.definition);
}

final class BookChanged extends MarketEvent {
  final BookDelta delta;
  const BookChanged(this.delta);
}

final class CandlesChanged extends MarketEvent {
  final String streamId, interval;
  final int revision;
  final List<Candle> candles;
  const CandlesChanged(
    this.streamId,
    this.interval,
    this.revision,
    this.candles,
  );
}

final class TradesReceived extends MarketEvent {
  final String streamId;
  final List<Trade> trades;
  final MarketSummary? summary;
  const TradesReceived(this.streamId, this.trades, this.summary);
}

final class DeliveryChanged extends MarketEvent {
  final String tier, overrideMode, reason;
  final double targetHz, effectiveHz;
  const DeliveryChanged(
    this.tier,
    this.overrideMode,
    this.reason,
    this.targetHz,
    this.effectiveHz,
  );
}

final class PongReceived extends MarketEvent {
  final int nonce;
  const PongReceived(this.nonce);
}

final class SubscriptionAccepted extends MarketEvent {
  const SubscriptionAccepted();
}

final class ServerRejectedMessage extends MarketEvent {
  const ServerRejectedMessage();
}

final class InvalidMarketMessage extends MarketEvent {
  const InvalidMarketMessage();
}
