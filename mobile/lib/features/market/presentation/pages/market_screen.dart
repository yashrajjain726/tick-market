import '../market_view_policy.dart';
import '../widgets/market_stat.dart';
import '../widgets/connection_status.dart';
import '../widgets/order_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/market_bloc.dart';
import '../widgets/candle_chart.dart';
import '../widgets/diagnostics_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../formatters/market_formatters.dart';

class MarketScreen extends StatelessWidget {
  const MarketScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: BlocBuilder<MarketBloc, MarketState>(
            builder: (context, c) {
              final change = c.price == null || c.reference == null
                  ? null
                  : c.price! - c.reference!;
              final up = (change ?? 0) >= 0;
              return CustomScrollView(
                key: const Key('market-scroll'),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    sliver: SliverList.list(
                      children: [
                        SizedBox(
                          height: 58,
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: accent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.stacked_line_chart_rounded,
                                  color: paletteBackground,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'tick.',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -1.3,
                                ),
                              ),
                              const Expanded(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'MARKET LAB',
                                      style: TextStyle(
                                        fontSize: 9,
                                        letterSpacing: 1.8,
                                        color: muted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              IconButton(
                                key: const Key('diagnostics'),
                                tooltip: 'Connection lab',
                                onPressed: () => showModalBottomSheet<void>(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: surface,
                                  builder: (_) => BlocProvider.value(
                                    value: context.read<MarketBloc>(),
                                    child: const DiagnosticsSheet(),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.tune_rounded,
                                  size: 21,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFF33281A),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                c.badge,
                                style: TextStyle(
                                  fontSize: 29,
                                  color: Color(0xFFF5AF54),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.marketName,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.6,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    '${c.baseAsset} / ${c.quoteAsset}',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 11,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: line),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'SIMULATED',
                                style: TextStyle(
                                  fontSize: 8,
                                  letterSpacing: 1.1,
                                  color: muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            c.price == null
                                ? 'Connecting…'
                                : '${c.quoteSign}${money(c.price)}',
                            style: numbers(
                              size: 42,
                              weight: FontWeight.w500,
                            ).copyWith(letterSpacing: -1.7),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Icon(
                              up ? Icons.north_east : Icons.south_east,
                              size: 14,
                              color: up ? positive : negative,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              change == null
                                  ? 'Waiting for market data'
                                  : '${up ? '+' : '−'}${c.quoteSign}${money(change.abs())} (${up ? '+' : '−'}${(change.abs() / c.reference! * 100).toStringAsFixed(2)}%)',
                              style: numbers(
                                size: 12,
                                color: up ? positive : negative,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              c.summaryWindow,
                              style: TextStyle(color: muted, fontSize: 10),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            MarketStat(
                              '${c.summaryWindow} high',
                              '${c.quoteSign}${money(c.high)}',
                            ),
                            MarketStat(
                              '${c.summaryWindow} low',
                              '${c.quoteSign}${money(c.low)}',
                            ),
                            MarketStat(
                              '${c.summaryWindow} volume',
                              c.volume == null
                                  ? '—'
                                  : '${quantity(c.volume!, places: 2)} ${c.baseAsset}',
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        ConnectionStatus(state: c),
                        if (!c.isLive)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    c.offline
                                        ? 'You’re offline. Displaying cached values.'
                                        : c.link == LinkState.syncing
                                        ? 'Synchronizing chart and order book…'
                                        : 'Values are stale. Reconnecting automatically…',
                                    style: const TextStyle(
                                      color: amber,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                if (c.offline)
                                  TextButton(
                                    key: const Key('reconnect-banner'),
                                    onPressed: () => context
                                        .read<MarketBloc>()
                                        .add(const OfflineChanged(false)),
                                    child: const Text('Reconnect'),
                                  ),
                              ],
                            ),
                          ),
                        if (c.error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              c.error!,
                              style: const TextStyle(
                                color: amber,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Text(
                              'Price chart',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            for (final interval in c.supportedIntervals)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Semantics(
                                  selected: c.interval == interval,
                                  child: TextButton(
                                    key: Key('interval-$interval'),
                                    onPressed: () => context
                                        .read<MarketBloc>()
                                        .add(IntervalSelected(interval)),
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(44, 44),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      foregroundColor: c.interval == interval
                                          ? accent
                                          : muted,
                                      backgroundColor: c.interval == interval
                                          ? surface
                                          : Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                    ),
                                    child: Text(
                                      interval,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        CandleChart(
                          candles: c.candles,
                          loading: c.historyLoading,
                          stale: !c.isLive,
                          interval: c.interval,
                          baseAsset: c.baseAsset,
                        ),
                        const SizedBox(height: 28),
                        OrderBook(state: c),
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            const Text(
                              'Recent trades',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              c.isLive ? 'LIVE TAPE' : 'CACHED TAPE',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 9,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Price (${c.quoteAsset})',
                                style: TextStyle(color: muted, fontSize: 10),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'Size (${c.baseAsset})',
                                style: TextStyle(color: muted, fontSize: 10),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'Time (UTC)',
                                style: TextStyle(color: muted, fontSize: 10),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (c.trades.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                              'Waiting for trades…',
                              style: TextStyle(color: muted),
                            ),
                          ),
                        for (final trade in c.trades.take(
                          MarketViewPolicy.trades,
                        ))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Icon(
                                        trade.buy
                                            ? Icons.arrow_upward
                                            : Icons.arrow_downward,
                                        size: 10,
                                        color: trade.buy ? positive : negative,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        money(trade.price),
                                        style: numbers(
                                          size: 12,
                                          color: trade.buy
                                              ? positive
                                              : negative,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    quantity(trade.quantity),
                                    style: numbers(size: 12),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    clockTime(trade.time, seconds: true),
                                    style: numbers(size: 11, color: muted),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 28),
                        const Divider(height: 1),
                        const SizedBox(height: 18),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.science_outlined,
                              size: 13,
                              color: muted,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'A synthetic market. Every tick accounted for.',
                              style: TextStyle(color: muted, fontSize: 10),
                            ),
                          ],
                        ),
                        const SizedBox(height: 26),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}
