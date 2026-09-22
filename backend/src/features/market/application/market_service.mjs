import { INTERVALS, FEED, describeMarket } from '../domain/market_definition.mjs';
import { DEFAULT_DELIVERY } from '../domain/delivery_config.mjs';
import { ClientSession } from './client_session.mjs';

/** Use cases for queries, connection lifetime, and one complete feed step. */
export class MarketService {
  constructor(market, { debug = true, policy = DEFAULT_DELIVERY } = {}) {
    this.policy = policy;
    this.market = market;
    this.debug = debug;
    this.clients = new Set();
    this.ticks = 0;
  }
  open(channel, now) {
    const session = new ClientSession({ market: this.market, channel, now, debug: this.debug, policy: this.policy });
    this.clients.add(session);
    return session;
  }
  disconnect(session) { this.clients.delete(session); }
  get health() { return { ok: true, symbol: this.market.settings.symbol, streamId: this.market.streamId, clients: this.clients.size }; }
  get definition() { return describeMarket(this.market.settings); }
  get book() { return this.market.snapshot; }
  get trades() { return { streamId: this.market.streamId, trades: this.market.recent }; }
  history(interval) {
    if (!Object.hasOwn(INTERVALS, interval)) throw new Error('Use 1m or 5m');
    return { streamId: this.market.streamId, interval, candles: this.market.candles[interval].slice(-FEED.historyLimit) };
  }
  advance(now) {
    const trade = this.market.step();
    const book = ++this.ticks % FEED.bookEveryTicks === 0 ? this.market.updateBook() : null;
    const summary = this.ticks % FEED.summaryEveryTicks === 0 ? this.market.summary : null;
    for (const session of this.clients) {
      try { session.publish({ trade, book, summary }, now); }
      catch {
        // A broken client must not take down the shared feed or other clients.
        this.disconnect(session);
        try { session.channel.close(1011, 'Delivery failed'); } catch { /* already broken */ }
      }
    }
  }
}
