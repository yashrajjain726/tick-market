part of 'market_bloc.dart';

sealed class MarketEvent {
  const MarketEvent();
}

final class MarketStarted extends MarketEvent {
  const MarketStarted();
}

final class IntervalSelected extends MarketEvent {
  final String interval;
  const IntervalSelected(this.interval);
}

final class TierOverrideRequested extends MarketEvent {
  final String tier;
  const TierOverrideRequested(this.tier);
}

final class OfflineChanged extends MarketEvent {
  final bool offline;
  const OfflineChanged(this.offline);
}

final class LifecyclePausedChanged extends MarketEvent {
  final bool paused;
  const LifecyclePausedChanged(this.paused);
}

final class ServerChanged extends MarketEvent {
  final String address;
  const ServerChanged(this.address);
}

final class BookGapRequested extends MarketEvent {
  const BookGapRequested();
}

final class SocketDropRequested extends MarketEvent {
  const SocketDropRequested();
}

// Private to the Bloc library: views cannot manufacture session updates.
final class _SessionChanged extends MarketEvent {
  const _SessionChanged();
}
