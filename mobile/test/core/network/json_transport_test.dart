import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tick_market/core/network/json_transport.dart';
import 'package:tick_market/core/network/network_policy.dart';

void main() {
  late HttpServer server;
  late IoJsonTransport transport;
  late Uri base;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    transport = IoJsonTransport(
      policy: NetworkPolicy(
        requestTimeout: const Duration(milliseconds: 150),
        maxResponseBytes: 32,
      ),
    );
  });
  tearDown(() async {
    transport.dispose();
    await server.close(force: true);
  });

  test(
    'whole-request deadline aborts a response that never finishes',
    () async {
      server.listen((request) {
        request.response.write('{');
        request.response.flush();
      });
      await expectLater(transport.get(base), throwsA(isA<TimeoutException>()));
    },
  );
  test(
    'non-success status fails without draining an endless error body',
    () async {
      server.listen((request) {
        request.response.statusCode = 503;
        request.response.write('busy');
        request.response.flush();
      });
      await expectLater(transport.get(base), throwsA(isA<HttpException>()));
    },
  );
  test(
    'oversized streaming body is rejected even without content length',
    () async {
      server.listen((request) {
        request.response.write('x' * 64);
        request.response.close();
      });
      await expectLater(transport.get(base), throwsFormatException);
    },
  );
  test('malformed JSON is rejected and valid responses are decoded', () async {
    server.listen((request) {
      request.response.write(
        request.uri.path == '/valid' ? '{"ok":true}' : '{bad',
      );
      request.response.close();
    });
    await expectLater(transport.get(base), throwsFormatException);
    expect(await transport.get(base.resolve('/valid')), {'ok': true});
  });
  test('a WebSocket handshake finishing after disposal is closed', () async {
    final arrived = Completer<void>(), release = Completer<void>();
    WebSocket? accepted;
    server.listen((request) async {
      arrived.complete();
      await release.future;
      accepted = await WebSocketTransformer.upgrade(request);
      accepted!.listen((_) {});
    });
    final opening = transport.connect(base.replace(scheme: 'ws'));
    final rejected = expectLater(opening, throwsStateError);
    await arrived.future;
    transport.dispose();
    release.complete();
    await rejected;
    await accepted?.close();
  });
  test('disposal prevents further requests or socket handshakes', () async {
    transport.dispose();
    transport.dispose();
    await expectLater(transport.get(base), throwsStateError);
    await expectLater(
      transport.connect(base.replace(scheme: 'ws')),
      throwsStateError,
    );
  });
}
