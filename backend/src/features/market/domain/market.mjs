import { INTERVALS, MARKET_DEFAULTS, FEED, SIMULATION } from './market_definition.mjs';
export { INTERVALS } from './market_definition.mjs';

export class Market {
  constructor({ origin = 0, streamId = 'test', seed = 42, warmup = 216000, settings = MARKET_DEFAULTS } = {}) {
    this.settings = settings;
    this.origin = origin;
    this.streamId = streamId; this.rng = seed || 42; this.id = 0;
    this.price = settings.initialPrice; this.sequence = 0; this.recent = [];
    this.bids = new Map(); this.asks = new Map();
    this.candles = { '1m': [], '5m': [] };
    for (let i = 0; i < warmup; i++) this.step();
    this.updateBook();
  }
  random(n) {
    this.rng ^= this.rng << 13; this.rng ^= this.rng >>> 17; this.rng ^= this.rng << 5;
    this.rng >>>= 0;
    return this.rng % n;
  }
  step() {
    this.id++;
    const anchor = this.settings.initialPrice + Math.round(SIMULATION.longWaveAmplitude * Math.sin(this.id / SIMULATION.longWavePeriod)) + Math.round(SIMULATION.shortWaveAmplitude * Math.sin(this.id / SIMULATION.shortWavePeriod));
    const previous = this.price;
    this.price = Math.max(SIMULATION.minimumPrice, this.price + this.random(SIMULATION.noiseRange) - SIMULATION.noiseMidpoint + Math.round((anchor - this.price) * SIMULATION.meanReversion));
    const t = { id: this.id, time: this.origin + this.id * FEED.stepMs, price: this.price,
      quantity: SIMULATION.minimumQuantity + this.random(SIMULATION.quantityRange), side: this.price >= previous ? 'buy' : 'sell' };
    this.recent.unshift(t); this.recent.length = Math.min(this.recent.length, FEED.retainedTrades);
    for (const [key, duration] of Object.entries(INTERVALS)) {
      const list = this.candles[key], start = Math.floor(t.time / duration) * duration;
      const last = list.at(-1);
      if (!last || last.start !== start) {
        list.push({ start, open: t.price, high: t.price, low: t.price, close: t.price,
          volume: t.quantity, lastTradeId: t.id });
        if (list.length > FEED.retainedCandles) list.shift();
      } else {
        last.high = Math.max(last.high, t.price); last.low = Math.min(last.low, t.price);
        last.close = t.price; last.volume += t.quantity; last.lastTradeId = t.id;
      }
    }
    return t;
  }
  updateBook() {
    const mid = Math.floor(this.price / SIMULATION.bookPriceIncrement) * SIMULATION.bookPriceIncrement, bids = new Map(), asks = new Map();
    for (let i = 0; i < this.settings.bookLevels; i++) {
      // Book quantities do not consume the trade RNG: publication never alters replay.
      bids.set(mid - SIMULATION.bookSpread - i * SIMULATION.bookStep, SIMULATION.bookMinimumQuantity + ((this.id * 193 + i * 7919) % SIMULATION.bookBidCycle));
      asks.set(mid + SIMULATION.bookSpread + i * SIMULATION.bookStep, SIMULATION.bookMinimumQuantity + ((this.id * 283 + i * 3571) % SIMULATION.bookAskCycle));
    }
    const diff = (old, next) => [
      ...[...old.keys()].filter(p => !next.has(p)).map(p => [p, 0]),
      ...[...next].filter(([p, q]) => old.get(p) !== q),
    ];
    const delta = { streamId: this.streamId, sequence: this.sequence + 1,
      previous: this.sequence, bids: diff(this.bids, bids), asks: diff(this.asks, asks) };
    this.sequence++; this.bids = bids; this.asks = asks;
    return delta;
  }
  get snapshot() { return { streamId: this.streamId, sequence: this.sequence, bids: [...this.bids], asks: [...this.asks] }; }
  get summary() {
    const candles = this.candles['1m'].slice(-FEED.summaryBuckets), first = candles[0], latest = candles.at(-1);
    return { reference: first?.open ?? this.price, price: latest?.close ?? this.price,
      high: candles.length ? Math.max(...candles.map(c => c.high)) : this.price,
      low: candles.length ? Math.min(...candles.map(c => c.low)) : this.price,
      volume: candles.reduce((v, c) => v + c.volume, 0), window: FEED.summaryWindow };
  }
}
