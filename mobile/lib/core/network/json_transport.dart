import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'network_policy.dart';

abstract interface class JsonSocket {
  Stream<dynamic> get messages;
  void send(Map<String, dynamic> message);
  Future<void> close();
}

abstract interface class JsonTransport {
  Future<Map<String, dynamic>> get(Uri url);
  Future<JsonSocket> connect(Uri url);
  void dispose();
}

class IoJsonTransport implements JsonTransport {
  final HttpClient _http;
  final NetworkPolicy policy;
  bool _disposed = false;
  IoJsonTransport({NetworkPolicy? policy, HttpClient? client})
    : policy = policy ?? NetworkPolicy(),
      _http = client ?? HttpClient() {
    _http.connectionTimeout = this.policy.requestTimeout;
    _http.maxConnectionsPerHost = this.policy.maxConnectionsPerHost;
  }

  @override
  Future<Map<String, dynamic>> get(Uri url) async {
    if (_disposed) throw StateError('Transport disposed');
    HttpClientRequest? request;
    var expired = false;
    Future<Map<String, dynamic>> fetch() async {
      request = await _http.getUrl(url);
      if (expired || _disposed) {
        request!.abort();
        throw StateError('Request cancelled');
      }
      final response = await request!.close();
      if (response.statusCode != HttpStatus.ok) {
        request!.abort();
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      if (response.contentLength > policy.maxResponseBytes) {
        request!.abort();
        throw const FormatException('Response exceeds size limit');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > policy.maxResponseBytes) {
          request!.abort();
          throw const FormatException('Response exceeds size limit');
        }
        bytes.addAll(chunk);
      }
      final parsed = jsonDecode(utf8.decode(bytes));
      if (parsed is! Map<String, dynamic>) {
        throw const FormatException('Expected object');
      }
      return parsed;
    }

    return fetch().timeout(
      policy.requestTimeout,
      onTimeout: () {
        expired = true;
        request?.abort();
        throw TimeoutException('HTTP request timed out', policy.requestTimeout);
      },
    );
  }

  @override
  Future<JsonSocket> connect(Uri url) async {
    if (_disposed) throw StateError('Transport disposed');
    var expired = false;
    final pending = WebSocket.connect(url.toString()).then((socket) async {
      if (expired || _disposed) {
        await _IoSocket(socket, policy).close();
        throw StateError('Connection cancelled');
      }
      return socket;
    });
    final socket = await pending.timeout(
      policy.handshakeTimeout,
      onTimeout: () {
        expired = true;
        throw TimeoutException(
          'WebSocket handshake timed out',
          policy.handshakeTimeout,
        );
      },
    );
    return _IoSocket(socket, policy);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _http.close(force: true);
  }
}

class _IoSocket implements JsonSocket {
  final WebSocket socket;
  final NetworkPolicy policy;
  _IoSocket(this.socket, this.policy);
  @override
  Stream<dynamic> get messages => socket;
  @override
  void send(Map<String, dynamic> message) => socket.add(jsonEncode(message));
  @override
  Future<void> close() async {
    try {
      await socket.close().timeout(policy.closeTimeout);
    } catch (_) {
      /* Socket cleanup must not block recovery or app disposal. */
    }
  }
}
