import 'package:equatable/equatable.dart';
import '../../domain/entities/market_entities.dart';
import '../../domain/use_cases/market_session.dart';
import '../market_view_policy.dart';

/// A value snapshot, never a reference to the session's mutable stores.
final class MarketState extends Equatable {
  final Uri baseUrl;
  final LinkState link;
  final List<Candle> candles;
  final List<Trade> trades;
  final List<Level> bids, asks;
  final List<String> supportedIntervals;
  final MarketDefinition? _definition;
  final int? price, reference, high, low, volume;
  final int bookSequence, bookRecoveries, malformed, reconnects;
  final String interval, tier, overrideMode, reason;
  final MarketFailure? failure;
  final String? addressError;
  final bool connected,
      historyLoading,
      debugEnabled,
      offline,
      paused,
      bookSynchronized;
  final double targetHz, effectiveHz, jitter;
  final double? rtt;

  MarketState.fromSession(MarketSession session, {this.addressError})
    : baseUrl = session.baseUrl,
      link = session.link,
      candles = List.unmodifiable(session.candles),
      trades = List.unmodifiable(session.trades),
      bids = List.unmodifiable(
        session.book.bids.take(MarketViewPolicy.bookRows),
      ),
      asks = List.unmodifiable(
        session.book.asks.take(MarketViewPolicy.bookRows),
      ),
      supportedIntervals = List.unmodifiable(
        session.definition?.supportedIntervals ?? intervals.keys,
      ),
      _definition = session.definition,
      price = session.price,
      reference = session.reference,
      high = session.high,
      low = session.low,
      volume = session.volume,
      bookSequence = session.book.sequence,
      bookRecoveries = session.book.recoveries,
      malformed = session.malformed,
      reconnects = session.reconnects,
      interval = session.interval,
      tier = session.tier,
      overrideMode = session.overrideMode,
      reason = session.reason ?? 'Measuring connection',
      failure = session.error,
      connected = session.connected,
      historyLoading = session.historyLoading,
      debugEnabled = session.debugEnabled,
      offline = session.offline,
      paused = session.paused,
      bookSynchronized = session.book.synchronized,
      targetHz = session.targetHz,
      effectiveHz = session.effectiveHz,
      jitter = session.latency.jitter,
      rtt = session.latency.rtt;

  bool get isLive => link == LinkState.live;
  String get marketName => _definition?.name ?? 'Market';
  String get baseAsset => _definition?.baseAsset ?? '—';
  String get quoteAsset => _definition?.quoteAsset ?? '—';
  String get quoteSign => _definition?.quoteSign ?? '';
  String get badge => _definition?.badge ?? '·';
  String get summaryWindow => _definition?.summaryWindow ?? '—';
  String? get error => switch (failure) {
    MarketFailure.historyUnavailable => 'History unavailable · retrying',
    MarketFailure.invalidServerMessage => 'Server ignored an invalid message',
    null => null,
  };

  @override
  List<Object?> get props => [
    baseUrl,
    link,
    candles,
    trades,
    bids,
    asks,
    supportedIntervals,
    marketName,
    baseAsset,
    quoteAsset,
    quoteSign,
    badge,
    summaryWindow,
    price,
    reference,
    high,
    low,
    volume,
    bookSequence,
    bookRecoveries,
    malformed,
    reconnects,
    interval,
    tier,
    overrideMode,
    reason,
    failure,
    addressError,
    connected,
    historyLoading,
    debugEnabled,
    offline,
    paused,
    bookSynchronized,
    targetHz,
    effectiveHz,
    jitter,
    rtt,
  ];
}
