import 'dart:convert';
import '../../domain/configuration/market_policy.dart';
import '../../domain/entities/market_entities.dart';
import '../../domain/entities/market_event.dart';

/// Decode and validate untrusted data before constructing domain values.
abstract final class MarketDto {
  static Map<String, dynamic> object(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected object');
    }
    return value;
  }

  static int integer(Object? value, {int min = 0}) {
    if (value is! int || value < min || value > 9007199254740991) {
      throw const FormatException('Invalid fixed-point integer');
    }
    return value;
  }

  static String string(Object? value) {
    if (value is! String || value.isEmpty || value.length > 256) {
      throw const FormatException('Expected string');
    }
    return value;
  }

  static Trade trade(Map<String, dynamic> j) {
    if (j['side'] != 'buy' && j['side'] != 'sell') {
      throw const FormatException('Bad side');
    }
    return Trade(
      integer(j['id'], min: 1),
      integer(j['time']),
      integer(j['price'], min: 1),
      integer(j['quantity'], min: 1),
      j['side'] == 'buy',
    );
  }

  static Candle candle(Map<String, dynamic> j) {
    final c = Candle(
      integer(j['start']),
      integer(j['open'], min: 1),
      integer(j['high'], min: 1),
      integer(j['low'], min: 1),
      integer(j['close'], min: 1),
      integer(j['volume']),
      integer(j['lastTradeId'], min: 1),
    );
    if (c.high < c.open ||
        c.high < c.close ||
        c.low > c.open ||
        c.low > c.close ||
        c.low > c.high) {
      throw const FormatException('Invalid OHLC');
    }
    return c;
  }

  static List<Candle> candles(Object? value, String interval) {
    if (value is! List ||
        value.length > MarketLimits.wireCandles ||
        !intervals.containsKey(interval)) {
      throw const FormatException('Invalid candles');
    }
    final parsed = value.map((c) => candle(object(c))).toList();
    if (parsed.any((c) => c.start % intervals[interval]! != 0)) {
      throw const FormatException('Unaligned candle');
    }
    return parsed;
  }

  static List<Level> levels(Object? value, {bool allowZero = false}) {
    if (value is! List || value.length > MarketLimits.bookLevels) {
      throw const FormatException('Invalid levels');
    }
    final seen = <int>{};
    return value.map((row) {
      if (row is! List || row.length != 2) {
        throw const FormatException('Invalid level');
      }
      final price = integer(row[0], min: 1),
          quantity = integer(row[1], min: allowZero ? 0 : 1);
      if (!seen.add(price)) throw const FormatException('Duplicate price');
      return (price, quantity);
    }).toList();
  }

  static BookSnapshot book(Map<String, dynamic> j) => BookSnapshot(
    string(j['streamId']),
    integer(j['sequence']),
    levels(j['bids']),
    levels(j['asks']),
  );
  static BookDelta delta(Map<String, dynamic> j) => BookDelta(
    string(j['streamId']),
    integer(j['sequence'], min: 1),
    integer(j['previous']),
    levels(j['bids'], allowZero: true),
    levels(j['asks'], allowZero: true),
  );
  static CandleHistory history(Map<String, dynamic> j) {
    final interval = string(j['interval']);
    return CandleHistory(
      string(j['streamId']),
      interval,
      candles(j['candles'], interval),
    );
  }

  static MarketSummary summary(Map<String, dynamic> j) => MarketSummary(
    integer(j['reference'], min: 1),
    integer(j['high'], min: 1),
    integer(j['low'], min: 1),
    integer(j['volume']),
  );

  static MarketDefinition market(Map<String, dynamic> j) {
    final supported = j['intervals'];
    if (j['priceScale'] != priceScale ||
        j['quantityScale'] != quantityScale ||
        supported is! List ||
        supported.isEmpty ||
        supported.length > intervals.length ||
        supported.toSet().length != supported.length ||
        supported.any((value) => !intervals.containsKey(value))) {
      throw const FormatException('Unsupported market contract');
    }
    String text(String key, int max) {
      final value = string(j[key]);
      if (value.trim().isEmpty || value.length > max) {
        throw const FormatException('Invalid market label');
      }
      return value;
    }

    final base = text('baseAsset', 20), quote = text('quoteAsset', 20);
    final symbol = text('symbol', 41);
    if (symbol != '$base-$quote') throw const FormatException('Invalid symbol');
    return MarketDefinition(
      symbol: symbol,
      name: text('name', 32),
      baseAsset: base,
      quoteAsset: quote,
      quoteSign: text('quoteSign', 4),
      badge: text('badge', 4),
      summaryWindow: text('summaryWindow', 8),
      supportedIntervals: List<String>.unmodifiable(supported),
    );
  }

  static MarketEvent event(dynamic raw) {
    try {
      if (raw is! String || raw.length > MarketLimits.frameCharacters) {
        throw const FormatException('Invalid frame');
      }
      final m = object(jsonDecode(raw));
      switch (m['type']) {
        case 'hello':
          final definition = market(object(m['market']));
          if (m['symbol'] != definition.symbol) {
            throw const FormatException('Symbol mismatch');
          }
          return MarketOpened(
            string(m['streamId']),
            m['debug'] == true,
            definition,
          );
        case 'book':
          return BookChanged(delta(m));
        case 'candles':
          final interval = string(m['interval']);
          return CandlesChanged(
            string(m['streamId']),
            interval,
            integer(m['revision'], min: 1),
            candles(m['candles'], interval),
          );
        case 'trades':
          final list = m['trades'];
          if (list is! List || list.length > MarketLimits.wireTrades) {
            throw const FormatException('Invalid trades');
          }
          return TradesReceived(
            string(m['streamId']),
            list.map((t) => trade(object(t))).toList(),
            m['summary'] == null ? null : summary(object(m['summary'])),
          );
        case 'status':
          final tier = m['tier'],
              target = m['targetHz'],
              effective = m['effectiveHz'];
          final forced = m['override'] ?? 'auto';
          if (!['full', 'degraded', 'minimal'].contains(tier) ||
              !['auto', 'full', 'degraded', 'minimal'].contains(forced) ||
              target is! num ||
              effective is! num ||
              !target.isFinite ||
              !effective.isFinite ||
              target <= 0 ||
              effective < 0) {
            throw const FormatException('Invalid delivery status');
          }
          return DeliveryChanged(
            tier as String,
            forced as String,
            string(m['reason']),
            target.toDouble(),
            effective.toDouble(),
          );
        case 'pong':
          return PongReceived(integer(m['nonce']));
        case 'subscribed':
          return const SubscriptionAccepted();
        case 'error':
          return const ServerRejectedMessage();
        default:
          throw const FormatException('Unknown message');
      }
    } catch (_) {
      // Invalid frames are data events, not socket errors: recovery can resnapshot
      // without discarding an otherwise healthy connection.
      return const InvalidMarketMessage();
    }
  }
}
