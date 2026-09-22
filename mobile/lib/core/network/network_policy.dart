class NetworkPolicy {
  final Duration requestTimeout, handshakeTimeout, closeTimeout;
  final int maxResponseBytes, maxConnectionsPerHost;
  NetworkPolicy({
    this.requestTimeout = const Duration(seconds: 4),
    this.handshakeTimeout = const Duration(seconds: 5),
    this.closeTimeout = const Duration(seconds: 2),
    this.maxResponseBytes = 1000000,
    this.maxConnectionsPerHost = 4,
  }) {
    if ([
          requestTimeout,
          handshakeTimeout,
          closeTimeout,
        ].any((value) => value <= Duration.zero) ||
        maxResponseBytes < 1 ||
        maxConnectionsPerHost < 1) {
      throw ArgumentError('Invalid network policy');
    }
  }
}
