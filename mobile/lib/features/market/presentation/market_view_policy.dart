/// Presentation budgets; these never change the server's complete market state.
abstract final class MarketViewPolicy {
  static const candles = 48;
  static const bookRows = 10;
  static const trades = 8;
  static const notificationInterval = Duration(milliseconds: 100);
}
