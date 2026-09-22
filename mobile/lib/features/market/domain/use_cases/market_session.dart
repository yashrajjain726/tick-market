import 'dart:async';
import 'dart:math' as math;
import '../configuration/market_policy.dart';
import '../entities/market_entities.dart';
import '../entities/market_event.dart';
import '../repositories/market_repository.dart';
import '../services/book_sync.dart';
import '../services/candle_store.dart';
import '../services/latency.dart';

enum LinkState { connecting, syncing, live, stale, paused }

enum MarketFailure { historyUnavailable, invalidServerMessage }

/// Framework-independent use case for a market session: lifecycle, subscription
/// generations, snapshot replay, candle merge, heartbeat, and recovery.
class MarketSession {
  final MarketRepository repository;
  final _changes = StreamController<void>.broadcast(sync: true);
  Stream<void> get changes => _changes.stream;
  Uri baseUrl;
  final SessionPolicy policy;
  final int Function(int) random;
  MarketDefinition? definition;
  MarketSession({
    required this.repository,
    required this.baseUrl,
    SessionPolicy? policy,
    int Function(int)? random,
  }) : policy = policy ?? SessionPolicy(),
       random = random ?? math.Random().nextInt;
  LinkState link = LinkState.connecting;
  final BookSync book = BookSync();
  final LatencyWindow latency = LatencyWindow();
  final Map<String, CandleStore> _cache = {};
  CandleStore _pendingCandles = CandleStore();
  CandleStore get chart => _cache.putIfAbsent(interval, CandleStore.new);
  String interval = '1m', tier = 'full', overrideMode = 'auto';
  String? streamId, reason;
  MarketFailure? error;
  bool connected = false,
      historyLoading = true,
      debugEnabled = false,
      offline = false;
  bool get isLive => link == LinkState.live;
  bool get paused => _paused;
  double targetHz = 0, effectiveHz = 0;
  int malformed = 0, reconnects = 0;
  int? reference, high, low, volume;
  List<Trade> trades = [];
  int? get price =>
      trades.isNotEmpty ? trades.first.price : chart.values.lastOrNull?.close;
  List<Candle> get candles => chart.values;
  MarketConnection? _connection;
  StreamSubscription<MarketEvent>? _subscription;
  Timer? _pingTimer, _retryTimer, _bookRetry, _historyRetry, _helloTimer;
  int? _openingGeneration;
  bool _bookRecoveryPending = false;
  final Stopwatch _clock = Stopwatch()..start();
  final Map<int, int> _pings = {};
  int _nonce = 0,
      _generation = 0,
      _revision = 0,
      _historyRequest = 0,
      _bookRequest = 0;
  int _failures = 0, _lastMessage = 0, _historyFailures = 0, _bookFailures = 0;
  bool _disposed = false, _paused = false, _bookBusy = false;

  Future<void> start() async {
    if (_disposed ||
        _paused ||
        offline ||
        connected ||
        _openingGeneration != null) {
      return;
    }
    _retryTimer?.cancel();
    final generation = ++_generation;
    _openingGeneration = generation;
    link = trades.isEmpty ? LinkState.connecting : LinkState.stale;
    _emit();
    try {
      final socket = await repository.connect(baseUrl);
      if (!_valid(generation)) {
        await _closeQuietly(socket);
        return;
      }
      _connection = socket;
      connected = true;
      link = LinkState.syncing;
      latency.reset();
      _pings.clear();
      _lastMessage = _clock.elapsedMilliseconds;
      _subscription = socket.events.listen(
        (raw) {
          if (!_valid(generation)) return;
          _lastMessage = _clock.elapsedMilliseconds;
          _handle(raw);
        },
        onDone: () {
          if (_valid(generation)) _lost();
        },
        onError: (Object _) {
          if (_valid(generation)) _lost();
        },
        cancelOnError: true,
      );
      if (!_valid(generation) || !connected) return;
      _helloTimer = Timer(policy.helloTimeout, () {
        if (_valid(generation)) _lost();
      });
      _pingTimer = Timer.periodic(policy.heartbeat, (_) {
        if (_clock.elapsedMilliseconds - _lastMessage >
                policy.staleAfter.inMilliseconds ||
            (_pings.isNotEmpty &&
                _clock.elapsedMilliseconds - _pings.values.first >
                    policy.staleAfter.inMilliseconds)) {
          _lost();
          return;
        }
        _ping();
      });
      _ping();
      _emit();
    } catch (_) {
      if (_valid(generation)) _lost();
    } finally {
      if (_openingGeneration == generation) _openingGeneration = null;
    }
  }

  bool _valid(int generation) =>
      !_disposed && generation == _generation && !_paused && !offline;

  void _withConnection(void Function(MarketConnection) action) {
    try {
      final connection = _connection;
      if (connection != null) action(connection);
    } catch (_) {
      if (connected) _lost();
    }
  }

  void _ping() {
    final nonce = ++_nonce;
    _pings[nonce] = _clock.elapsedMilliseconds;
    _withConnection((connection) => connection.ping(nonce));
  }

  void _handle(MarketEvent event) {
    switch (event) {
      case MarketOpened():
        _helloTimer?.cancel();
        definition = event.definition;
        if (!definition!.supportedIntervals.contains(interval)) {
          interval = definition!.supportedIntervals.first;
        }
        final epoch = event.streamId;
        if (streamId != null && epoch != streamId) {
          _cache.clear();
          book.clear();
          trades = [];
          reference = null;
          high = null;
          low = null;
          volume = null;
        }
        streamId = epoch;
        debugEnabled = event.debugEnabled;
        book.begin(epoch);
        _bookBusy = false;
        _subscribe();
        _recoverBook();
        if (overrideMode != 'auto') {
          _withConnection((connection) => connection.setOverride(overrideMode));
        }
      case BookChanged():
        if (book.receive(event.delta)) _recoverBook(restart: true);
        _updateLink();
      case CandlesChanged():
        if (event.streamId != streamId ||
            event.interval != interval ||
            event.revision != _revision) {
          return;
        }
        if (historyLoading) {
          _pendingCandles.merge(event.candles);
        } else {
          chart.merge(event.candles);
        }
      case TradesReceived():
        if (event.streamId != streamId) return;
        final unique = {
          for (final t in trades) t.id: t,
          for (final t in event.trades) t.id: t,
        };
        trades = unique.values.toList()..sort((a, b) => b.id.compareTo(a.id));
        trades = trades.take(MarketLimits.retainedTrades).toList();
        final summary = event.summary;
        if (summary != null) {
          reference = summary.reference;
          high = summary.high;
          low = summary.low;
          volume = summary.volume;
        }
      case DeliveryChanged():
        tier = event.tier;
        targetHz = event.targetHz;
        effectiveHz = event.effectiveHz;
        overrideMode = event.overrideMode;
        reason = event.reason;
      case PongReceived():
        final start = _pings.remove(event.nonce);
        if (start == null) return;
        latency.add((_clock.elapsedMilliseconds - start).toDouble());
        _withConnection(
          (connection) =>
              connection.reportMetrics(latency.rtt!, latency.jitter),
        );
      case ServerRejectedMessage():
        error = MarketFailure.invalidServerMessage;
      case SubscriptionAccepted():
        break;
      case InvalidMarketMessage():
        malformed++;
        if (streamId != null && connected) {
          if (book.synchronized) book.begin(streamId!);
          _recoverBook(restart: true);
        }
    }
    _emit();
  }

  void selectInterval(String value) {
    if (_disposed ||
        value == interval ||
        !(definition?.supportedIntervals ?? intervals.keys).contains(value)) {
      return;
    }
    interval = value;
    _historyRequest++;
    _historyRetry?.cancel();
    historyLoading = true;
    _pendingCandles = CandleStore();
    if (connected && streamId != null) _subscribe();
    _updateLink();
    _emit();
  }

  void _subscribe() {
    _revision++;
    historyLoading = true;
    _pendingCandles = CandleStore();
    _withConnection((connection) => connection.subscribe(interval, _revision));
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    _historyRetry?.cancel();
    final request = ++_historyRequest,
        generation = _generation,
        selected = interval,
        epoch = streamId;
    try {
      final data = await repository.fetchHistory(baseUrl, selected);
      if (!_valid(generation) ||
          request != _historyRequest ||
          selected != interval) {
        return;
      }
      if (data.streamId != epoch || data.interval != selected) {
        throw const FormatException('History epoch mismatch');
      }
      final store = CandleStore()
        ..merge(data.candles)
        ..merge(_pendingCandles.values);
      _cache[selected] = store;
      _pendingCandles.clear();
      historyLoading = false;
      _historyFailures = 0;
      error = null;
      _updateLink();
      _emit();
    } catch (_) {
      if (!_valid(generation) || request != _historyRequest) return;
      error = MarketFailure.historyUnavailable;
      _historyRetry = Timer(
        policy.recoveryDelay(policy.historyRetry, _historyFailures++, random),
        _loadHistory,
      );
      _emit();
    }
  }

  Future<void> _recoverBook({bool restart = false}) async {
    if (!connected || streamId == null) return;
    if (_bookBusy || _bookRetry?.isActive == true) {
      _bookRecoveryPending |= restart;
      return;
    }
    _bookRetry?.cancel();
    _bookBusy = true;
    _bookRecoveryPending = false;
    _updateLink();
    final request = ++_bookRequest, generation = _generation;
    try {
      final data = await repository.fetchBook(baseUrl);
      if (!_valid(generation) || request != _bookRequest) return;
      _bookBusy = false;
      if (_bookRecoveryPending || !book.install(data)) {
        throw const FormatException('Snapshot replay gap');
      }
      _bookFailures = 0;
      _updateLink();
      _emit();
    } catch (_) {
      if (!_valid(generation) || request != _bookRequest) return;
      _bookBusy = false;
      _bookRetry = Timer(
        policy.recoveryDelay(policy.bookRetry, _bookFailures++, random),
        _recoverBook,
      );
      _emit();
    }
  }

  void _updateLink() {
    if (!connected) return;
    link = book.synchronized && !historyLoading
        ? LinkState.live
        : LinkState.syncing;
    if (isLive) _failures = 0;
  }

  void setOverride(String value) {
    if (!debugEnabled ||
        !['auto', 'full', 'degraded', 'minimal'].contains(value)) {
      return;
    }
    _withConnection((connection) => connection.setOverride(value));
  }

  void skipBookDelta() =>
      _withConnection((connection) => connection.skipBookDelta());
  void serverDisconnect() =>
      _withConnection((connection) => connection.disconnectForDemo());

  void setOffline(bool value) {
    if (_disposed || offline == value) return;
    offline = value;
    if (value) {
      _stop();
      link = LinkState.stale;
      effectiveHz = 0;
    } else {
      reconnects++;
      start();
    }
    _emit();
  }

  void setPaused(bool value) {
    if (_disposed || _paused == value) return;
    _paused = value;
    if (value) {
      _stop();
      link = LinkState.paused;
    } else if (!offline) {
      start();
    }
    _emit();
  }

  void changeServer(String value) {
    if (_disposed) return;
    final uri = Uri.parse(value.trim());
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException('Use an HTTP or HTTPS server address');
    }
    _stop();
    baseUrl = uri;
    streamId = null;
    definition = null;
    book.clear();
    reason = null;
    error = null;
    targetHz = 0;
    offline = false;
    _cache.clear();
    trades = [];
    reference = null;
    high = null;
    low = null;
    volume = null;
    overrideMode = 'auto';
    _emit();
    start();
  }

  void _lost() {
    if (_disposed || _paused || offline) return;
    _stop();
    link = LinkState.stale;
    effectiveHz = 0;
    final delay = policy.reconnectDelay(_failures++, random);
    _retryTimer = Timer(delay, () {
      reconnects++;
      start();
    });
    _emit();
  }

  void _stop() {
    _generation++;
    _historyRequest++;
    _bookRequest++;
    connected = false;
    _openingGeneration = null;
    _bookRecoveryPending = false;
    _bookBusy = false;
    _helloTimer?.cancel();
    historyLoading = true;
    if (streamId != null) book.begin(streamId!);
    _pingTimer?.cancel();
    _retryTimer?.cancel();
    _bookRetry?.cancel();
    _historyRetry?.cancel();
    final subscription = _subscription;
    if (subscription != null) {
      unawaited(subscription.cancel().catchError((Object _) {}));
    }
    _subscription = null;
    final connection = _connection;
    if (connection != null) unawaited(_closeQuietly(connection));
    _connection = null;
    _pings.clear();
  }

  Future<void> _closeQuietly(MarketConnection connection) async {
    try {
      await connection.close();
    } catch (_) {
      /* Cleanup must not interrupt recovery. */
    }
  }

  void _emit() {
    if (!_disposed) _changes.add(null);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stop();
    _clock.stop();
    repository.dispose();
    _changes.close();
  }
}
