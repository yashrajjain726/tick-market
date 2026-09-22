import '../market_view_policy.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/market_bloc.dart';
import '../formatters/market_formatters.dart';

class OrderBook extends StatelessWidget {
  final MarketState state;
  const OrderBook({super.key, required this.state});
  @override
  Widget build(BuildContext context) {
    final c = state,
        bids = state.bids.take(MarketViewPolicy.bookRows).toList(),
        asks = state.asks.take(MarketViewPolicy.bookRows).toList();
    final maxBid = bids.isEmpty ? 1 : bids.map((l) => l.$2).reduce(math.max);
    final maxAsk = asks.isEmpty ? 1 : asks.map((l) => l.$2).reduce(math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Order book',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
              ),
            ),
            const Spacer(),
            Icon(
              c.isLive && c.bookSynchronized
                  ? Icons.check_circle_outline
                  : Icons.sync,
              size: 12,
              color: c.isLive ? positive : amber,
            ),
            const SizedBox(width: 4),
            Text(
              c.isLive && c.bookSynchronized
                  ? 'Synchronized'
                  : 'Cached / syncing',
              style: TextStyle(fontSize: 10, color: c.isLive ? muted : amber),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Bid (${c.quoteAsset})',
                    style: TextStyle(color: positive, fontSize: 10),
                  ),
                  Text(
                    c.baseAsset,
                    style: TextStyle(color: muted, fontSize: 10),
                  ),
                ],
              ),
            ),
            SizedBox(width: 24),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Ask (${c.quoteAsset})',
                    style: TextStyle(color: negative, fontSize: 10),
                  ),
                  Text(
                    c.baseAsset,
                    style: TextStyle(color: muted, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < MarketViewPolicy.bookRows; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: _BookRow(
                    price: i < bids.length ? bids[i].$1 : null,
                    size: i < bids.length ? bids[i].$2 : null,
                    max: maxBid,
                    color: positive,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _BookRow(
                    price: i < asks.length ? asks[i].$1 : null,
                    size: i < asks.length ? asks[i].$2 : null,
                    max: maxAsk,
                    color: negative,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Text(
                'Spread',
                style: TextStyle(color: muted, fontSize: 10),
              ),
              const SizedBox(width: 8),
              Text(
                bids.isEmpty || asks.isEmpty
                    ? '—'
                    : '${c.quoteSign}${money(asks.first.$1 - bids.first.$1)}',
                style: numbers(size: 11),
              ),
              const Spacer(),
              Text(
                '${MarketViewPolicy.bookRows} levels · #${c.bookSequence}',
                style: numbers(size: 10, color: muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BookRow extends StatelessWidget {
  final int? price, size;
  final int max;
  final Color color;
  const _BookRow({
    this.price,
    this.size,
    required this.max,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 24,
    child: Stack(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FractionallySizedBox(
            widthFactor: (size ?? 0) / max,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(money(price), style: numbers(size: 11, color: color)),
              Text(
                size == null ? '—' : quantity(size!, places: 4),
                style: numbers(size: 10),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
