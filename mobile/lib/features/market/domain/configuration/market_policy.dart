/// Resource limits are named protocol/client policy, not display data.
abstract final class MarketLimits {
  static const retainedTrades = 30;
  static const retainedCandles = 180;
  static const bufferedBookDeltas = 512;
  static const bookLevels = 500;
  static const minimumBookLevels = 10;
  static const wireCandles = 500;
  static const wireTrades = 100;
  static const frameCharacters = 1000000;
  static const latencySamples = 10;
  static const latencyWeight = 0.25;
}

class SessionPolicy {
  final Duration heartbeat,
      staleAfter,
      helloTimeout,
      retryBase,
      retryMax,
      retryJitter,
      historyRetry,
      bookRetry;
  SessionPolicy({
    this.heartbeat = const Duration(seconds: 2),
    this.staleAfter = const Duration(seconds: 8),
    this.helloTimeout = const Duration(seconds: 8),
    this.retryBase = const Duration(seconds: 1),
    this.retryMax = const Duration(seconds: 16),
    this.retryJitter = const Duration(milliseconds: 250),
    this.historyRetry = const Duration(seconds: 2),
    this.bookRetry = const Duration(milliseconds: 500),
  }) {
    if ([
          heartbeat,
          staleAfter,
          helloTimeout,
          retryBase,
          retryMax,
          historyRetry,
          bookRetry,
        ].any((duration) => duration <= Duration.zero) ||
        staleAfter <= heartbeat ||
        retryMax < retryBase ||
        retryJitter < Duration.zero) {
      throw ArgumentError('Invalid session timing policy');
    }
  }
  Duration reconnectDelay(int failures, int Function(int) random) =>
      recoveryDelay(retryBase, failures, random);
  Duration recoveryDelay(
    Duration base,
    int failures,
    int Function(int) random,
  ) {
    final exponential = base.inMilliseconds * (1 << failures.clamp(0, 20));
    final capped = exponential.clamp(0, retryMax.inMilliseconds);
    return Duration(
      milliseconds: capped + random(retryJitter.inMilliseconds + 1),
    );
  }
}
