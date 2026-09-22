import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../domain/entities/market_entities.dart';
import '../../../../core/theme/app_theme.dart';
import '../formatters/market_formatters.dart';
import '../market_view_policy.dart';

/// Rendering adapter only: supplied candles remain owned by the domain session.
class CandleChart extends StatefulWidget {
  final String baseAsset;
  final List<Candle> candles;
  final bool loading, stale;
  final String interval;
  const CandleChart({
    super.key,
    this.baseAsset = '—',
    required this.candles,
    required this.loading,
    required this.stale,
    required this.interval,
  });
  @override
  State<CandleChart> createState() => _CandleChartState();
}

class _CandleChartState extends State<CandleChart> {
  int? selected;
  List<Candle> _rendered = const [];
  bool? _renderedStale;
  int? _renderedSelection;
  Widget? _plot;

  @override
  void didUpdateWidget(covariant CandleChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interval != widget.interval) selected = null;
  }

  Widget _buildPlot(List<Candle> candles, Candle? match) {
    final low = candles.map((c) => c.low).reduce(math.min).toDouble();
    final high = candles.map((c) => c.high).reduce(math.max).toDouble();
    final padding = math.max((high - low) * 0.16, 50.0);
    Color color(Candle c) => (c.close >= c.open ? positive : negative)
        .withValues(alpha: widget.stale ? 0.45 : 1);
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bodyWidth = ((constraints.maxWidth - 62) / candles.length * 0.6)
              .clamp(2.0, 12.0);
          return Column(
            children: [
              Expanded(
                child: CandlestickChart(
                  CandlestickChartData(
                    minX: -0.5,
                    maxX: candles.length - 0.5,
                    minY: low - padding,
                    maxY: high + padding,
                    candlestickSpots: [
                      for (var i = 0; i < candles.length; i++)
                        CandlestickSpot(
                          x: i.toDouble(),
                          open: candles[i].open.toDouble(),
                          high: candles[i].high.toDouble(),
                          low: candles[i].low.toDouble(),
                          close: candles[i].close.toDouble(),
                        ),
                    ],
                    candlestickPainter: DefaultCandlestickPainter(
                      candlestickStyleProvider: (spot, index) =>
                          CandlestickStyle(
                            lineColor: color(candles[index]),
                            lineWidth: 1,
                            bodyFillColor: color(candles[index]),
                            bodyWidth: bodyWidth,
                            bodyStrokeColor: color(candles[index]),
                            bodyStrokeWidth: 1,
                            bodyRadius: 0.8,
                          ),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(),
                      topTitles: const AxisTitles(),
                      bottomTitles: const AxisTitles(),
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 62,
                          minIncluded: false,
                          maxIncluded: false,
                          getTitlesWidget: (value, meta) => SideTitleWidget(
                            meta: meta,
                            space: 8,
                            child: Text(
                              money(value.round()),
                              style: numbers(size: 9, color: muted),
                            ),
                          ),
                        ),
                      ),
                    ),
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) =>
                          const FlLine(color: line, strokeWidth: 0.5),
                    ),
                    borderData: FlBorderData(show: false),
                    touchedPointIndicator: AxisSpotIndicator(
                      x: match == null
                          ? null
                          : candles.indexOf(match).toDouble(),
                      y: (match ?? candles.last).close.toDouble(),
                      painter: AxisLinesIndicatorPainter(
                        verticalLineProvider: (x) => VerticalLine(
                          x: x,
                          color: muted,
                          strokeWidth: 1,
                          dashArray: [3, 3],
                        ),
                        horizontalLineProvider: (y) => HorizontalLine(
                          y: y,
                          color: accent.withValues(alpha: 0.4),
                          strokeWidth: 0.6,
                          dashArray: [3, 4],
                        ),
                      ),
                    ),
                    candlestickTouchData: CandlestickTouchData(
                      handleBuiltInTouches: false,
                      touchSpotThreshold: double.infinity,
                      touchCallback: (event, response) {
                        final hit = response?.touchedSpot;
                        if (event.isInterestedForInteractions && hit != null) {
                          setState(
                            () => selected = candles[hit.spotIndex].start,
                          );
                        }
                      },
                    ),
                  ),
                  chartRendererKey: const Key('candle-chart'),
                  duration: Duration.zero,
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 62),
                child: SizedBox(
                  height: 28,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      minY: 0,
                      maxY: math
                          .max(1, candles.map((c) => c.volume).reduce(math.max))
                          .toDouble(),
                      titlesData: const FlTitlesData(show: false),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      barTouchData: BarTouchData(enabled: false),
                      barGroups: [
                        for (var i = 0; i < candles.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: candles[i].volume.toDouble(),
                                width: bodyWidth,
                                color: color(
                                  candles[i],
                                ).withValues(alpha: widget.stale ? 0.12 : 0.25),
                                borderRadius: BorderRadius.zero,
                              ),
                            ],
                          ),
                      ],
                    ),
                    duration: Duration.zero,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 7, right: 62),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final i in {
                      0,
                      candles.length ~/ 2,
                      candles.length - 1,
                    })
                      Text(
                        clockTime(candles[i].start),
                        style: numbers(size: 9, color: muted),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final candles = widget.candles
        .skip(math.max(0, widget.candles.length - MarketViewPolicy.candles))
        .toList();
    final match = candles.where((c) => c.start == selected).firstOrNull;
    // Unrelated book/trade notifications must not redraw a slower-tier chart.
    if (_plot == null ||
        !listEquals(_rendered, candles) ||
        _renderedStale != widget.stale ||
        _renderedSelection != selected) {
      _rendered = candles;
      _renderedStale = widget.stale;
      _renderedSelection = selected;
      _plot = candles.isEmpty ? null : _buildPlot(candles, match);
    }
    final volume = match ?? candles.lastOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 226,
          child: _plot == null
              ? Center(
                  child: Text(
                    widget.loading
                        ? 'Connecting to your market…'
                        : 'No candles yet. Waiting for trades.',
                    style: const TextStyle(color: muted),
                  ),
                )
              : Semantics(
                  label:
                      'Candlestick chart. Touch or drag to inspect ${widget.interval} candles.',
                  child: _plot,
                ),
        ),
        const SizedBox(height: 10),
        Container(
          constraints: const BoxConstraints(minHeight: 66),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      match == null
                          ? 'Touch the chart to explore'
                          : '${DateTime.fromMillisecondsSinceEpoch(match.start, isUtc: true).toIso8601String().substring(0, 10)}  ${clockTime(match.start)} UTC',
                      style: TextStyle(
                        fontSize: 10,
                        color: match == null ? muted : accent,
                      ),
                    ),
                  ),
                  if (widget.stale)
                    const Text(
                      'CACHED',
                      style: TextStyle(color: muted, fontSize: 10),
                    ),
                  if (match != null)
                    IconButton(
                      tooltip: 'Clear candle selection',
                      onPressed: () => setState(() => selected = null),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.close, size: 17, color: muted),
                    ),
                ],
              ),
              if (match != null)
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    for (final pair in [
                      ('O', match.open),
                      ('H', match.high),
                      ('L', match.low),
                      ('C', match.close),
                    ])
                      Text(
                        '${pair.$1} ${money(pair.$2)}',
                        style: numbers(size: 10),
                      ),
                  ],
                ),
              const SizedBox(height: 5),
              Text(
                'Candle volume  ${volume == null ? '—' : '${quantity(volume.volume, places: 3)} ${widget.baseAsset}'}',
                style: numbers(size: 11, color: muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
