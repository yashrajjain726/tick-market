import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tick_market/core/theme/app_theme.dart';
import 'package:tick_market/features/market/domain/entities/market_entities.dart';
import 'package:tick_market/features/market/presentation/widgets/candle_chart.dart';

Widget screen(
  List<Candle> candles, {
  String interval = '1m',
  bool stale = false,
}) => MaterialApp(
  theme: tickTheme,
  home: Scaffold(
    body: CandleChart(
      candles: candles,
      loading: false,
      stale: stale,
      interval: interval,
      baseAsset: 'BTC',
    ),
  ),
);

void main() {
  testWidgets(
    'renderer preserves supplied OHLCV and selection follows candle time',
    (tester) async {
      final candles = [
        for (var i = 0; i < 50; i++)
          Candle(
            i * 60000,
            10000 + i,
            12000 + i,
            9000 + i,
            11000 + i,
            (i + 1) * 100000000,
            i + 1,
          ),
      ];
      await tester.pumpWidget(screen(candles));
      final data = tester
          .widget<CandlestickChart>(find.byType(CandlestickChart))
          .data;
      expect(data.candlestickSpots.length, 48);
      final first = data.candlestickSpots.first;
      expect(
        [first.open, first.high, first.low, first.close],
        [10002, 12002, 9002, 11002],
      );
      expect(
        tester
            .widget<BarChart>(find.byType(BarChart))
            .data
            .barGroups
            .first
            .barRods
            .single
            .toY,
        300000000,
      );
      final chart = find.byKey(const Key('candle-chart'));
      await tester.tapAt(tester.getTopLeft(chart) + const Offset(4, 40));
      await tester.pump();
      expect(find.textContaining('1970-01-01  00:02 UTC'), findsOneWidget);
      await tester.dragFrom(
        tester.getTopLeft(chart) + const Offset(4, 40),
        const Offset(140, 0),
      );
      await tester.pump();
      expect(find.textContaining('1970-01-01  00:02 UTC'), findsNothing);
      expect(find.textContaining('1970-01-01'), findsOneWidget);
      await tester.pumpWidget(screen(candles, interval: '5m'));
      expect(find.textContaining('1970-01-01'), findsNothing);
      await tester.pumpWidget(screen([]));
      expect(find.text('No candles yet. Waiting for trades.'), findsOneWidget);
      expect(find.byType(CandlestickChart), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'single flat candle with zero volume is inspectable at narrow width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        screen([
          const Candle(0, 10000, 10000, 10000, 10000, 0, 1),
        ], stale: true),
      );
      await tester.tap(find.byKey(const Key('candle-chart')));
      await tester.pump();
      expect(find.text('O 100.00'), findsOneWidget);
      expect(find.text('H 100.00'), findsOneWidget);
      expect(find.textContaining('Candle volume  0.000 BTC'), findsOneWidget);
      expect(find.text('CACHED'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'book-only rebuilds reuse chart; candle or stale changes refresh it',
    (tester) async {
      const candle = Candle(0, 10000, 12000, 9000, 11000, 100, 1);
      await tester.pumpWidget(screen([candle]));
      final initial = tester.widget<CandlestickChart>(
        find.byType(CandlestickChart),
      );
      await tester.pumpWidget(screen([candle]));
      expect(
        identical(
          initial,
          tester.widget<CandlestickChart>(find.byType(CandlestickChart)),
        ),
        isTrue,
      );
      await tester.pumpWidget(screen([candle], stale: true));
      expect(
        identical(
          initial,
          tester.widget<CandlestickChart>(find.byType(CandlestickChart)),
        ),
        isFalse,
      );
      const updated = Candle(0, 10000, 14000, 9000, 13000, 200, 2);
      await tester.pumpWidget(screen([updated]));
      expect(
        tester
            .widget<CandlestickChart>(find.byType(CandlestickChart))
            .data
            .candlestickSpots
            .single
            .close,
        13000,
      );
    },
  );
}
