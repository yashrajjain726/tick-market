import '../../core/network/network_policy.dart';
import '../../features/market/domain/configuration/market_policy.dart';

/// Build configuration is parsed once, then injected into domain/infrastructure.
class AppConfig {
  final Uri server;
  final NetworkPolicy network;
  final SessionPolicy session;
  AppConfig({
    required this.server,
    required this.network,
    required this.session,
  }) {
    if (!['http', 'https'].contains(server.scheme) ||
        server.host.isEmpty ||
        server.userInfo.isNotEmpty ||
        server.hasQuery ||
        server.hasFragment ||
        (server.path.isNotEmpty && server.path != '/')) {
      throw ArgumentError('API_URL must be an HTTP or HTTPS origin');
    }
  }
  factory AppConfig.fromEnvironment() => AppConfig(
    server: Uri.parse(
      const String.fromEnvironment(
        'API_URL',
        defaultValue: 'http://10.0.2.2:8080',
      ),
    ),
    network: NetworkPolicy(
      requestTimeout: _milliseconds(
        const String.fromEnvironment(
          'REQUEST_TIMEOUT_MS',
          defaultValue: '4000',
        ),
      ),
      handshakeTimeout: _milliseconds(
        const String.fromEnvironment(
          'HANDSHAKE_TIMEOUT_MS',
          defaultValue: '5000',
        ),
      ),
    ),
    session: SessionPolicy(
      retryMax: _milliseconds(
        const String.fromEnvironment('RECONNECT_MAX_MS', defaultValue: '16000'),
      ),
    ),
  );
  static Duration _milliseconds(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed <= 0 || parsed > 120000) {
      throw ArgumentError('Invalid duration in app configuration');
    }
    return Duration(milliseconds: parsed);
  }
}
