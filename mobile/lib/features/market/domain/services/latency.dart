import '../configuration/market_policy.dart';

class LatencyWindow {
  final List<double> _samples = [];
  double? rtt;
  double get jitter {
    if (_samples.length < 2) return 0;
    var total = 0.0;
    for (var i = 1; i < _samples.length; i++) {
      total += (_samples[i] - _samples[i - 1]).abs();
    }
    return total / (_samples.length - 1);
  }

  void add(double sample) {
    if (!sample.isFinite || sample < 0) return;
    rtt = rtt == null
        ? sample
        : MarketLimits.latencyWeight * sample +
              (1 - MarketLimits.latencyWeight) * rtt!;
    _samples.add(sample);
    if (_samples.length > MarketLimits.latencySamples) _samples.removeAt(0);
  }

  void reset() {
    _samples.clear();
    rtt = null;
  }
}
