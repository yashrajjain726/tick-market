import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tick_market/features/market/presentation/bloc/market_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tick_market/app/tick_app.dart';
import 'package:tick_market/features/market/presentation/pages/market_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const record = bool.fromEnvironment('RECORD_DEMO');
  testWidgets(
    'live market, inspection, interval, all tiers, gap and disconnect recovery',
    (tester) async {
      await tester.pumpWidget(const TickApp());
      await tester.pump();
      final bloc = tester.element(find.byType(MarketScreen)).read<MarketBloc>();
      MarketState getState() => bloc.state;
      Future<void> waitUntil(bool Function() ready, String reason) async {
        for (var i = 0; i < 100 && !ready(); i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(ready(), isTrue, reason: reason);
        await tester.pump(const Duration(milliseconds: 200));
      }

      Future<void> hold(int seconds) async {
        final count = record ? seconds * 5 : 2;
        for (var i = 0; i < count; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
      }

      Future<void> tap(String key) async {
        if (find.byKey(Key(key)).hitTestable().evaluate().isEmpty) {
          await tester.ensureVisible(find.byKey(Key(key)));
        }
        await tester.tap(find.byKey(Key(key)));
        await tester.pump(const Duration(milliseconds: 400));
      }

      await waitUntil(
        () => getState().isLive,
        'Initial REST and WS synchronization',
      );
      expect(getState().bids.length, greaterThanOrEqualTo(10));
      expect(getState().candles, isNotEmpty);
      debugPrint('DEMO_READY');
      await hold(15);
      final firstTrade = getState().trades.first.id;
      await hold(3);
      expect(getState().trades.first.id, greaterThan(firstTrade));
      final chart = find.byKey(const Key('candle-chart'));
      await tester.tapAt(tester.getTopLeft(chart) + const Offset(80, 80));
      await hold(2);
      expect(find.byTooltip('Clear candle selection'), findsOneWidget);
      await tester.drag(chart, const Offset(120, 0));
      await hold(2);
      await tap('interval-5m');
      await waitUntil(
        () => getState().isLive && getState().interval == '5m',
        'Interval switched',
      );
      await hold(4);
      await tester.drag(
        find.byKey(const Key('market-scroll')),
        const Offset(0, -540),
      );
      await tester.pump(const Duration(seconds: 1));
      await hold(5);
      await tester.drag(
        find.byKey(const Key('market-scroll')),
        const Offset(0, 850),
      );
      await tester.pump(const Duration(seconds: 1));
      await tap('diagnostics');
      await hold(2);
      for (final tier in ['full', 'degraded', 'minimal']) {
        await tap('tier-$tier');
        await waitUntil(
          () => getState().tier == tier && getState().overrideMode == tier,
          'Server acknowledged $tier',
        );
        await hold(5);
      }
      final recoveries = getState().bookRecoveries;
      await tap('skip-book');
      await waitUntil(
        () =>
            getState().bookRecoveries > recoveries &&
            getState().bookSynchronized,
        'Book recovered from skipped delta',
      );
      await hold(3);
      await tap('toggle-offline');
      expect(getState().offline, isTrue);
      final cachedTrade = getState().trades.first.id;
      await tap('close-lab');
      await hold(5);
      expect(getState().trades.first.id, cachedTrade);
      expect(getState().isLive, isFalse);
      await tap('reconnect-banner');
      await waitUntil(() => getState().isLive, 'Manual reconnect completed');
      await hold(4);
      await tester.drag(
        find.byKey(const Key('market-scroll')),
        const Offset(0, 850),
      );
      await tester.pump(const Duration(seconds: 1));
      await tap('diagnostics');
      await tap('tier-auto');
      await waitUntil(
        () => getState().overrideMode == 'auto',
        'Automatic policy restored',
      );
      final reconnects = getState().reconnects;
      await tap('drop-socket');
      await waitUntil(
        () => getState().reconnects > reconnects && getState().isLive,
        'Socket drop recovered automatically',
      );
      await hold(2);
      await tap('close-lab');
      await hold(5);
      expect(tester.takeException(), isNull);
      debugPrint('DEMO_COMPLETE');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
