import 'dart:async';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/use_cases/market_session.dart';
import '../market_view_policy.dart';
import 'market_state.dart';
export '../../domain/use_cases/market_session.dart' show LinkState;
export 'market_state.dart';
part 'market_event.dart';

/// Presentation commands and immutable snapshots. Recovery stays in the domain.
final class MarketBloc extends Bloc<MarketEvent, MarketState> {
  final MarketSession _session;
  late final StreamSubscription<void> _subscription;
  Timer? _notification;
  String? _addressError;
  bool _closing = false;
  Future<void>? _closeFuture;

  MarketBloc(this._session) : super(MarketState.fromSession(_session)) {
    // One queue preserves ordering across all action types, including lifecycle.
    on<MarketEvent>(_onEvent, transformer: sequential());
    _subscription = _session.changes.listen((_) {
      if (_closing || _notification?.isActive == true) return;
      _notification = Timer(MarketViewPolicy.notificationInterval, () {
        if (!_closing) add(const _SessionChanged());
      });
    });
  }

  void _onEvent(MarketEvent event, Emitter<MarketState> emit) {
    if (_closing) return;
    switch (event) {
      case MarketStarted():
        // Do not hold the event queue during I/O: pause/offline must win promptly.
        unawaited(_session.start());
      case IntervalSelected():
        _session.selectInterval(event.interval);
      case TierOverrideRequested():
        _session.setOverride(event.tier);
      case OfflineChanged():
        _session.setOffline(event.offline);
      case LifecyclePausedChanged():
        _session.setPaused(event.paused);
      case ServerChanged():
        try {
          _session.changeServer(event.address);
          _addressError = null;
        } on FormatException {
          _addressError = 'Use an HTTP or HTTPS server address, without a path';
        }
      case BookGapRequested():
        if (_session.debugEnabled && _session.connected) {
          _session.skipBookDelta();
        }
      case SocketDropRequested():
        if (_session.debugEnabled && _session.connected) {
          _session.serverDisconnect();
        }
      case _SessionChanged():
        break;
    }
    emit(MarketState.fromSession(_session, addressError: _addressError));
  }

  @override
  Future<void> close() {
    if (_closeFuture != null) return _closeFuture!;
    _closing = true;
    _notification?.cancel();
    _session.dispose();
    return _closeFuture = Future.wait([
      _subscription.cancel(),
      super.close(),
    ]).then((_) {});
  }
}
