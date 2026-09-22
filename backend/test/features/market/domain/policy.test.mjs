import test from 'node:test';
import assert from 'node:assert/strict';
import { DeliveryPolicy, PERIOD } from '../../../../src/features/market/domain/delivery_policy.mjs';
import { ChartDelivery } from '../../../../src/features/market/domain/chart_delivery.mjs';
import { Market } from '../../../../src/features/market/domain/market.mjs';

test('hysteresis rejects spikes, downgrades after two reports, recovers after four', () => {
  const p = new DeliveryPolicy(0);
  p.report(400, 90, 2000); assert.equal(p.tier, 'full');
  p.report(50, 5, 4000); p.report(400, 90, 6000); assert.equal(p.tier, 'full');
  p.report(400, 90, 8000); assert.equal(p.tier, 'degraded');
  for (const now of [10000, 12000, 14000]) p.report(50, 5, now);
  assert.equal(p.tier, 'degraded');
  p.report(50, 5, 16000); assert.equal(p.tier, 'full');
});
test('five-second dwell blocks rapid reversal; minimal recovers one tier at a time', () => {
  const p = new DeliveryPolicy(0);
  p.report(900, 300, 1000); p.report(900, 300, 2000);
  assert.equal(p.tier, 'minimal');
  for (const now of [2500, 3000, 3500, 4000]) p.report(50, 2, now);
  assert.equal(p.tier, 'minimal');
  p.report(50, 2, 7000); assert.equal(p.tier, 'degraded');
  for (const now of [9000, 11000, 13000, 15000]) p.report(50, 2, now);
  assert.equal(p.tier, 'full');
});
test('jitter alone can degrade, invalid metrics cannot refresh report deadline', () => {
  const p = new DeliveryPolicy(0);
  p.report(50, 100, 2000); p.report(50, 100, 4000); assert.equal(p.tier, 'degraded');
  p.report(NaN, 0, 18000); p.report(0, -1, 18000);
  p.tick(19000); assert.equal(p.tier, 'minimal');
});
test('missing reports fail safe at 15 seconds; overrides remain per connection', () => {
  const a = new DeliveryPolicy(0), b = new DeliveryPolicy(0);
  a.force('full'); a.tick(15000); b.tick(14999);
  assert.equal(a.tier, 'full'); assert.equal(a.automatic, 'minimal'); assert.equal(b.tier, 'full');
  a.force(null); assert.equal(a.tier, 'minimal');
  b.report(20, 2, 15000); assert.equal(b.tier, 'full');
  assert.throws(() => a.force('anything'));
});
test('all delivery tiers preserve final OHLCV, including candle rollover', () => {
  for (const [interval, duration, steps] of [['1m', 60000, 1850], ['5m', 300000, 6100]]) {
  const market = new Market({ origin: 0, warmup: 0, seed: 42 });
  const tiers = Object.keys(PERIOD);
  const delivery = Object.fromEntries(tiers.map(t => [t, new ChartDelivery()]));
  const received = Object.fromEntries(tiers.map(t => [t, new Map()]));
  const counts = Object.fromEntries(tiers.map(t => [t, 0]));
  const expected = new Map();
  for (let i = 0; i < steps; i++) {
    const t = market.step(), start = Math.floor(t.time / duration) * duration;
    const bucket = expected.get(start) ?? { start, open: t.price, high: t.price, low: t.price, close: t.price, volume: 0, lastTradeId: t.id };
    bucket.high = Math.max(bucket.high, t.price); bucket.low = Math.min(bucket.low, t.price);
    bucket.close = t.price; bucket.volume += t.quantity; bucket.lastTradeId = t.id; expected.set(start, bucket);
    for (const tier of tiers) {
      delivery[tier].collect(market.candles[interval].at(-1));
      const batch = delivery[tier].flush(t.time, PERIOD[tier]);
      if (batch) { counts[tier]++; for (const c of batch) received[tier].set(c.start, c); }
    }
  }
  for (const tier of tiers) {
    for (const c of delivery[tier].flush(steps * 100 + 3000, PERIOD[tier]) ?? []) received[tier].set(c.start, c);
    assert.deepEqual([...received[tier].values()], [...expected.values()]);
  }
  assert.ok(counts.full > counts.degraded * 4);
  assert.ok(counts.degraded > counts.minimal * 3);
  }
});
test('seed and time origin repeat exactly; publishing books does not perturb trades', () => {
  const a = new Market({ origin: 0, seed: 72, warmup: 0 });
  const b = new Market({ origin: 0, seed: 72, warmup: 0 });
  for (let i = 0; i < 1000; i++) { assert.deepEqual(a.step(), b.step()); a.updateBook(); }
  assert.deepEqual(a.candles, b.candles);
});
test('book deltas reconstruct the full snapshot including removals', () => {
  const m = new Market({ origin: 0, warmup: 0 });
  const bids = new Map(m.snapshot.bids), asks = new Map(m.snapshot.asks);
  let sequence = m.sequence;
  for (let i = 0; i < 100; i++) {
    m.step(); const d = m.updateBook();
    assert.equal(d.previous, sequence); assert.equal(d.sequence, sequence + 1); sequence = d.sequence;
    for (const [side, values] of [[bids, d.bids], [asks, d.asks]]) for (const [p, q] of values) { if (q === 0) side.delete(p); else side.set(p, q); }
    assert.deepEqual([...bids].sort(), [...m.snapshot.bids].sort());
    assert.deepEqual([...asks].sort(), [...m.snapshot.asks].sort());
    assert.equal(bids.size, 20); assert.equal(asks.size, 20);
    assert.ok(Math.max(...bids.keys()) < Math.min(...asks.keys()));
  }
});
test('delivery sends nothing without an event and preserves immutable bucket snapshots', () => {
  const delivery = new ChartDelivery();
  assert.equal(delivery.flush(10000, 100), null);
  const c = { start: 0, close: 20 };
  delivery.collect(c); c.close = 500;
  assert.equal(delivery.flush(10000, 100)[0].close, 20);
  assert.equal(delivery.flush(20000, 100), null);
});
