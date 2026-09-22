import '../../../../core/network/json_transport.dart';

/// The only feature class that knows endpoint paths and transport URLs.
class MarketRemoteDataSource {
  final JsonTransport transport;
  const MarketRemoteDataSource(this.transport);

  Future<Map<String, dynamic>> fetchHistory(Uri server, String interval) =>
      transport.get(
        server
            .resolve('/v1/candles')
            .replace(queryParameters: {'interval': interval}),
      );
  Future<Map<String, dynamic>> fetchBook(Uri server) =>
      transport.get(server.resolve('/v1/book'));
  Future<JsonSocket> connect(Uri server) => transport.connect(
    server.replace(
      scheme: server.scheme == 'https' ? 'wss' : 'ws',
      path: '/v1/stream',
    ),
  );
  void dispose() => transport.dispose();
}
