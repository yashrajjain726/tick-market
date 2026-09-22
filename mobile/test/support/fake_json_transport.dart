import 'dart:async';
import 'dart:convert';
import 'package:tick_market/core/network/json_transport.dart';
import 'package:tick_market/features/market/domain/entities/market_entities.dart';

class FakeSocket implements JsonSocket {
  final source = StreamController<dynamic>.broadcast(sync: true);
  final sent = <Map<String, dynamic>>[];
  bool closed = false;
  @override
  Stream<dynamic> get messages => source.stream;
  @override
  void send(Map<String, dynamic> message) => sent.add(message);
  @override
  Future<void> close() async {
    closed = true;
  }

  void emit(Map<String, dynamic> message) => source.add(jsonEncode(message));
}

class FakeTransport implements JsonTransport {
  final sockets = <FakeSocket>[];
  final connections = <Uri>[];
  final requests = <(Uri, Completer<Map<String, dynamic>>)>[];
  FakeSocket get socket => sockets.last;
  @override
  Future<JsonSocket> connect(Uri url) async {
    connections.add(url);
    final s = FakeSocket();
    sockets.add(s);
    return s;
  }

  @override
  Future<Map<String, dynamic>> get(Uri url) {
    final c = Completer<Map<String, dynamic>>();
    requests.add((url, c));
    return c.future;
  }

  void history(String interval, List<Candle> candles, {int request = 0}) =>
      requests
          .where((r) => r.$1.queryParameters['interval'] == interval)
          .elementAt(request)
          .$2
          .complete({
            'streamId': 'epoch',
            'interval': interval,
            'candles': candles.map(candleJson).toList(),
          });
  @override
  void dispose() {}
  void hello() => socket.emit({
    'type': 'hello',
    'streamId': 'epoch',
    'symbol': 'BTC-USD',
    'market': marketDefinitionJson,
    'debug': true,
  });
  void book() =>
      requests.lastWhere((r) => r.$1.path == '/v1/book').$2.complete({
        'streamId': 'epoch',
        'sequence': 1,
        'bids': [
          for (var i = 0; i < 10; i++) [10000 - i * 10, 100],
        ],
        'asks': [
          for (var i = 0; i < 10; i++) [10100 + i * 10, 100],
        ],
      });
}

Map<String, dynamic> candleJson(Candle c) => {
  'start': c.start,
  'open': c.open,
  'high': c.high,
  'low': c.low,
  'close': c.close,
  'volume': c.volume,
  'lastTradeId': c.lastTradeId,
};

const marketDefinitionJson = <String, dynamic>{
  'symbol': 'BTC-USD',
  'name': 'Bitcoin',
  'baseAsset': 'BTC',
  'quoteAsset': 'USD',
  'quoteSign': r'$',
  'badge': '₿',
  'priceScale': 100,
  'quantityScale': 100000000,
  'intervals': ['1m', '5m'],
  'summaryWindow': '6h',
};
