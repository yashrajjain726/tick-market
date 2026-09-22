import '../entities/market_entities.dart';
import '../configuration/market_policy.dart';

/// Pure state machine. While a REST request is outstanding, retain WS deltas.
/// Installation is atomic: failed replay never exposes a partially applied book.
class BookSync {
  final int maxLevels, maxBuffered;
  BookSync({
    this.maxLevels = MarketLimits.bookLevels,
    this.maxBuffered = MarketLimits.bufferedBookDeltas,
  });
  void clear() {
    streamId = null;
    sequence = 0;
    synchronized = false;
    _bids.clear();
    _asks.clear();
    _buffer.clear();
  }

  String? streamId;
  int sequence = 0, recoveries = 0;
  bool synchronized = false;
  Map<int, int> _bids = {}, _asks = {};
  final List<BookDelta> _buffer = [];
  int get buffered => _buffer.length;
  List<Level> get bids => _sorted(_bids, true);
  List<Level> get asks => _sorted(_asks, false);
  static List<Level> _sorted(Map<int, int> values, bool descending) =>
      values.entries.map((e) => (e.key, e.value)).toList()..sort(
        (a, b) => descending ? b.$1.compareTo(a.$1) : a.$1.compareTo(b.$1),
      );

  void begin(String epoch) {
    streamId = epoch;
    synchronized = false;
    _buffer.clear();
  }

  /// True means a new snapshot is required. An exact retransmission is harmless;
  /// a backwards sequence or a gap is an error and enters recovery.
  bool receive(BookDelta delta) {
    if (delta.streamId != streamId) return false; // old socket/epoch
    if (!synchronized) {
      if (_buffer.length >= maxBuffered) {
        _buffer.clear();
        recoveries++;
        return true;
      }
      _buffer.add(delta);
      return false;
    }
    if (delta.sequence == sequence) return false;
    if (delta.previous != sequence || delta.sequence != sequence + 1) {
      synchronized = false;
      recoveries++;
      _buffer
        ..clear()
        ..add(delta);
      return true;
    }
    final bids = Map<int, int>.of(_bids), asks = Map<int, int>.of(_asks);
    _apply(bids, delta.bids);
    _apply(asks, delta.asks);
    if (!_valid(bids, asks)) {
      synchronized = false;
      recoveries++;
      _buffer.clear();
      return true;
    }
    _bids = bids;
    _asks = asks;
    sequence = delta.sequence;
    return false;
  }

  bool install(BookSnapshot snapshot) {
    if (snapshot.streamId != streamId) return false;
    final bids = {for (final l in snapshot.bids) l.$1: l.$2};
    final asks = {for (final l in snapshot.asks) l.$1: l.$2};
    var next = snapshot.sequence;
    for (final d in _buffer) {
      // Snapshot watermark already includes these trades/book changes.
      if (d.sequence <= snapshot.sequence) continue;
      if (d.sequence == next) continue;
      if (d.previous != next || d.sequence != next + 1) {
        recoveries++;
        _buffer.clear();
        return false;
      }
      _apply(bids, d.bids);
      _apply(asks, d.asks);
      if (bids.length > maxLevels || asks.length > maxLevels) {
        _buffer.clear();
        return false;
      }
      next = d.sequence;
    }
    if (!_valid(bids, asks)) {
      _buffer.clear();
      return false;
    }
    _bids = bids;
    _asks = asks;
    sequence = next;
    synchronized = true;
    _buffer.clear();
    return true;
  }

  static void _apply(Map<int, int> target, List<Level> changes) {
    for (final (price, quantity) in changes) {
      if (quantity == 0) {
        target.remove(price);
      } else {
        target[price] = quantity;
      }
    }
  }

  bool _valid(Map<int, int> bids, Map<int, int> asks) =>
      bids.length >= MarketLimits.minimumBookLevels &&
      asks.length >= MarketLimits.minimumBookLevels &&
      bids.length <= maxLevels &&
      asks.length <= maxLevels &&
      bids.keys.reduce((a, b) => a > b ? a : b) <
          asks.keys.reduce((a, b) => a < b ? a : b);
}
