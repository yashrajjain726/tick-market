import 'dart:async';
import 'package:tick_market/app/tick_app.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tick_market/features/market/data/models/market_dto.dart';
import '../../../support/fake_json_transport.dart';
import 'package:tick_market/features/market/data/datasources/market_remote_data_source.dart';
import 'package:tick_market/features/market/data/repositories/remote_market_repository.dart';
import 'package:tick_market/features/market/domain/use_cases/market_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tick_market/features/market/domain/entities/market_entities.dart';
import 'package:tick_market/features/market/presentation/bloc/market_bloc.dart';
import 'package:tick_market/core/network/json_transport.dart';
import 'package:tick_market/features/market/presentation/pages/market_screen.dart';
import 'package:tick_market/core/theme/app_theme.dart';

MarketSession makeSession({
  required JsonTransport transport,
  required Uri baseUrl,
}) => MarketSession(
  repository: RemoteMarketRepository(MarketRemoteDataSource(transport)),
  baseUrl: baseUrl,
);

Future<void> flush(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
}

Future<void> closeBloc(MarketBloc bloc, WidgetTester tester) async {
  // Stream teardown may schedule zero-duration work outside frame pumping.
  await tester.runAsync(bloc.close);
}

Widget screen(MarketBloc bloc) => BlocProvider.value(
  value: bloc,
  child: MaterialApp(theme: tickTheme, home: const MarketScreen()),
);

class PendingTransport extends FakeTransport {
  final opening = Completer<JsonSocket>();
  int opens = 0;
  @override
  Future<JsonSocket> connect(Uri url) {
    opens++;
    return opening.future;
  }
}

Future<MarketBloc> liveBloc(
  FakeTransport transport,
  WidgetTester tester,
) async {
  final bloc = MarketBloc(
    makeSession(transport: transport, baseUrl: Uri.parse('http://localhost')),
  )..add(const MarketStarted());
  await flush(tester);
  transport.hello();
  transport.book();
  transport.history('1m', [early]);
  await flush(tester);
  expect(bloc.state.isLive, isTrue);
  return bloc;
}

const early = Candle(0, 100, 110, 90, 105, 200, 5);
const newer = Candle(0, 100, 120, 80, 110, 900, 9);
void main() {
  for (final size in [const Size(320, 700), const Size(800, 600)]) {
    testWidgets('server-provided identity renders without overflow at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = makeSession(
        transport: FakeTransport(),
        baseUrl: Uri.parse('http://localhost'),
      );
      session.definition = MarketDto.market({
        ...marketDefinitionJson,
        'name': 'Ether',
        'symbol': 'ETH-EUR',
        'baseAsset': 'ETH',
        'quoteAsset': 'EUR',
        'quoteSign': '€',
        'badge': 'Ξ',
      });
      session.trades = [const Trade(1, 60000, 12345, 10000000, true)];
      session.reference = 12000;
      final bloc = MarketBloc(session);
      await tester.pumpWidget(screen(bloc));
      expect(find.text('Ether'), findsOneWidget);
      expect(find.text('ETH / EUR'), findsOneWidget);
      expect(find.text('€123.45'), findsOneWidget);
      expect(find.text('Bitcoin'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await closeBloc(bloc, tester);
    });
  }
  testWidgets(
    'late interval response is ignored, buffered live candle beats history, empty history works',
    (tester) async {
      final transport = FakeTransport();
      final session = makeSession(
        transport: transport,
        baseUrl: Uri.parse('http://localhost:8080'),
      );
      final bloc = MarketBloc(session)..add(const MarketStarted());
      await flush(tester);
      transport.hello();
      transport.book();
      bloc.add(const IntervalSelected('5m'));
      await tester.pump();
      transport.socket.emit({
        'type': 'candles',
        'streamId': 'epoch',
        'interval': '5m',
        'revision': 2,
        'candles': [candleJson(newer)],
      });
      transport.history('5m', [early]);
      await flush(tester);
      expect(bloc.state.candles.single.volume, 900);
      expect(bloc.state.isLive, isTrue);
      transport.history('1m', [early]);
      await flush(tester);
      expect(bloc.state.interval, '5m');
      expect(bloc.state.candles.single.lastTradeId, 9);
      transport.socket.emit({
        'type': 'candles',
        'streamId': 'epoch',
        'interval': '1m',
        'revision': 1,
        'candles': [candleJson(early)],
      });
      expect(bloc.state.candles.single.lastTradeId, 9);
      bloc.add(const IntervalSelected('1m'));
      await tester.pump();
      transport.history('1m', [], request: 1);
      await flush(tester);
      expect(bloc.state.candles, isEmpty);
      expect(bloc.state.historyLoading, isFalse);
      await closeBloc(bloc, tester);
      await tester.pump(const Duration(milliseconds: 200));
    },
  );
  testWidgets(
    'malformed message triggers recovery; background closes socket and foreground resubscribes',
    (tester) async {
      final transport = FakeTransport();
      final session = makeSession(
        transport: transport,
        baseUrl: Uri.parse('http://localhost:8080'),
      );
      final bloc = MarketBloc(session)..add(const MarketStarted());
      await flush(tester);
      transport.hello();
      transport.book();
      transport.history('1m', [early]);
      await tester.pump();
      transport.socket.source.add('{bad');
      await flush(tester);
      expect(bloc.state.malformed, 1);
      expect(bloc.state.bookSynchronized, isFalse);
      transport.book();
      await flush(tester);
      expect(bloc.state.bookSynchronized, isTrue);
      final oldSocket = transport.socket;
      bloc.add(const LifecyclePausedChanged(true));
      await flush(tester);
      expect(oldSocket.closed, isTrue);
      expect(bloc.state.link, LinkState.paused);
      expect(bloc.state.candles, isNotEmpty);
      bloc.add(const LifecyclePausedChanged(false));
      await flush(tester);
      expect(transport.sockets.length, 2);
      transport.hello();
      expect(
        transport.socket.sent.any((m) => m['type'] == 'subscribe'),
        isTrue,
      );
      await closeBloc(bloc, tester);
      transport.history('1m', [newer], request: 1);
      await flush(tester);
      expect(
        bloc.state.candles.single.lastTradeId,
        5,
        reason: 'Disposed request must not mutate cached state',
      );
    },
  );
  testWidgets(
    'mobile layout, candle inspection, and connection lab have no overflow at 360 dp',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = makeSession(
        transport: FakeTransport(),
        baseUrl: Uri.parse('http://localhost:8080'),
      );
      session.chart.merge([
        for (var i = 0; i < 48; i++)
          Candle(i * 60000, 6700000, 6710000, 6690000, 6705000, 2000000, i + 1),
      ]);
      session.trades = [const Trade(1, 60000, 6705000, 1234000, true)];
      session.reference = 6700000;
      final bloc = MarketBloc(session);
      await tester.pumpWidget(screen(bloc));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('candle-chart')));
      await flush(tester);
      expect(find.textContaining('1970-01-01'), findsOneWidget);
      await tester.tap(find.byKey(const Key('diagnostics')));
      await tester.pumpAndSettle();
      expect(find.text('Connection lab'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await closeBloc(bloc, tester);
    },
  );
  testWidgets(
    'market bursts coalesce while previously emitted snapshots stay immutable',
    (tester) async {
      final transport = FakeTransport();
      final bloc = await liveBloc(transport, tester);
      final before = bloc.state;
      final states = <MarketState>[];
      final subscription = bloc.stream.listen(states.add);
      for (var i = 1; i <= 20; i++) {
        transport.socket.emit({
          'type': 'trades',
          'streamId': 'epoch',
          'trades': [
            {
              'id': i,
              'time': 60000 + i,
              'price': 10000 + i,
              'quantity': 100,
              'side': 'buy',
            },
          ],
        });
      }
      transport.socket.emit({
        'type': 'candles',
        'streamId': 'epoch',
        'interval': '1m',
        'revision': 1,
        'candles': [candleJson(newer)],
      });
      transport.socket.emit({
        'type': 'book',
        'streamId': 'epoch',
        'previous': 1,
        'sequence': 2,
        'bids': [
          [10000, 777],
        ],
        'asks': [],
      });
      await tester.pump(const Duration(milliseconds: 99));
      expect(states, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(states, hasLength(1));
      expect(bloc.state.price, 10020);
      expect(bloc.state.trades, hasLength(20));
      expect(bloc.state.candles.single.volume, 900);
      expect(bloc.state.bids.first.$2, 777);
      expect(before.candles.single.volume, 200);
      expect(before.bids.first.$2, 100);
      expect(before.trades, isEmpty);
      expect(() => before.bids.clear(), throwsUnsupportedError);
      expect(() => before.candles.clear(), throwsUnsupportedError);
      expect(() => before.trades.clear(), throwsUnsupportedError);
      expect(() => before.supportedIntervals.clear(), throwsUnsupportedError);
      bloc.add(const IntervalSelected('1m'));
      await tester.pump();
      expect(
        states,
        hasLength(1),
        reason: 'Equal snapshots do not notify widgets',
      );
      bloc.add(const OfflineChanged(true));
      await tester.pump();
      expect(
        bloc.state.offline,
        isTrue,
        reason: 'User actions bypass market-data batching',
      );
      expect(bloc.state.link, LinkState.stale);
      expect(bloc.state.candles.single.volume, 900);
      await tester.runAsync(subscription.cancel);
      await closeBloc(bloc, tester);
    },
  );

  testWidgets(
    'ordered events allow pause and close during an unfinished connection',
    (tester) async {
      final transport = PendingTransport();
      final bloc =
          MarketBloc(
              makeSession(
                transport: transport,
                baseUrl: Uri.parse('http://localhost'),
              ),
            )
            ..add(const MarketStarted())
            ..add(const MarketStarted())
            ..add(const IntervalSelected('5m'))
            ..add(const LifecyclePausedChanged(true));
      await tester.pump();
      expect(transport.opens, 1);
      expect(bloc.state.interval, '5m');
      expect(bloc.state.link, LinkState.paused);
      expect(bloc.state.connected, isFalse);
      await closeBloc(bloc, tester);
      final state = bloc.state;
      final socket = FakeSocket();
      transport.opening.complete(socket);
      await flush(tester);
      expect(socket.closed, isTrue);
      expect(bloc.state, same(state));
      expect(bloc.isClosed, isTrue);
      await closeBloc(bloc, tester);
    },
  );

  testWidgets(
    'server-address errors enter Bloc state and tiers wait for server acknowledgment',
    (tester) async {
      final transport = FakeTransport();
      final bloc = await liveBloc(transport, tester);
      bloc.add(const TierOverrideRequested('minimal'));
      await tester.pump();
      expect(transport.socket.sent.last, {
        'type': 'override',
        'tier': 'minimal',
      });
      expect(bloc.state.overrideMode, 'auto');
      transport.socket.emit({
        'type': 'status',
        'tier': 'minimal',
        'targetHz': 0.5,
        'effectiveHz': 0.5,
        'override': 'minimal',
        'reason': 'Manual demonstration',
      });
      await flush(tester);
      expect(bloc.state.overrideMode, 'minimal');
      expect(bloc.state.targetHz, 0.5);
      bloc.add(const ServerChanged('ftp://bad/path'));
      await tester.pump();
      expect(bloc.state.addressError, isNotNull);
      expect(bloc.state.baseUrl, Uri.parse('http://localhost'));
      expect(transport.sockets, hasLength(1));
      final oldSocket = transport.socket;
      bloc.add(const ServerChanged('http://new-server:9000'));
      await flush(tester);
      expect(bloc.state.addressError, isNull);
      expect(bloc.state.baseUrl, Uri.parse('http://new-server:9000'));
      expect(bloc.state.candles, isEmpty);
      expect(oldSocket.closed, isTrue);
      expect(transport.sockets, hasLength(2));
      await closeBloc(bloc, tester);
    },
  );

  testWidgets(
    'app provider owns the bloc and forwards background/resume events',
    (tester) async {
      final transport = FakeTransport();
      final bloc = MarketBloc(
        makeSession(
          transport: transport,
          baseUrl: Uri.parse('http://localhost'),
        ),
      );
      await tester.pumpWidget(TickApp(createBloc: () => bloc));
      await flush(tester);
      final socket = transport.socket;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await flush(tester);
      expect(bloc.state.paused, isTrue);
      expect(socket.closed, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flush(tester);
      expect(bloc.state.paused, isFalse);
      expect(transport.sockets, hasLength(2));
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
      expect(bloc.isClosed, isTrue);
      expect(transport.socket.closed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
