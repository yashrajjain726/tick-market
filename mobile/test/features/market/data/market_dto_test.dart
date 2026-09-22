import '../../../support/fake_json_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tick_market/features/market/data/models/market_dto.dart';

void main() {
  test(
    'incompatible precision, symbols, and intervals never enter the domain',
    () {
      for (final invalid in [
        {...marketDefinitionJson, 'priceScale': 1000},
        {...marketDefinitionJson, 'symbol': 'ETH-USD'},
        {
          ...marketDefinitionJson,
          'intervals': ['1h'],
        },
      ]) {
        expect(() => MarketDto.market(invalid), throwsFormatException);
      }
    },
  );
  test(
    'wire validation rejects malformed prices, impossible OHLC and duplicate levels',
    () {
      expect(() => MarketDto.integer(1.4), throwsFormatException);
      expect(
        () => MarketDto.levels([
          [100, 2],
          [100, 3],
        ]),
        throwsFormatException,
      );
      expect(
        () => MarketDto.candle({
          'start': 0,
          'open': 100,
          'high': 90,
          'low': 80,
          'close': 100,
          'volume': 1,
          'lastTradeId': 1,
        }),
        throwsFormatException,
      );
    },
  );
}
