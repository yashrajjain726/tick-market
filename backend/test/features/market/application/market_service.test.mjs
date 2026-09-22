import test from 'node:test';
import assert from 'node:assert/strict';
import { Market } from '../../../../src/features/market/domain/market.mjs';
import { MarketService } from '../../../../src/features/market/application/market_service.mjs';

class MemoryChannel {
  events = [];
  closes = [];
  send(event) { this.events.push(structuredClone(event)); return true; }
  close(code, reason) { this.closes.push({ code, reason }); }
  ofType(type) { return this.events.filter(event => event.type === type); }
}
const service = (options) => new MarketService(new Market({ seed: 42, origin: 0, warmup: 20 }), options);

test('application drives independent clients using only an in-memory channel and explicit time', () => {
  const app = service();
  const full = new MemoryChannel(), minimal = new MemoryChannel();
  const a = app.open(full, 0), b = app.open(minimal, 0);
  for (const client of [a, b]) client.receive({ type: 'subscribe', interval: '1m', revision: 1 }, 0);
  b.receive({ type: 'override', tier: 'minimal' }, 0);
  for (let now = 100; now <= 4000; now += 100) app.advance(now);
  assert.equal(full.ofType('candles').length, 40);
  assert.equal(minimal.ofType('candles').length, 3);
  assert.deepEqual(full.ofType('candles').at(-1).candles, minimal.ofType('candles').at(-1).candles);
  assert.deepEqual(full.ofType('book'), minimal.ofType('book'));
  assert.deepEqual(full.ofType('trades'), minimal.ofType('trades'));
  assert.equal(app.health.clients, 2);
});

test('disconnect detaches delivery while the shared market keeps advancing', () => {
  const app = service();
  const channel = new MemoryChannel();
  const client = app.open(channel, 0);
  client.receive({ type: 'subscribe', interval: '5m', revision: 4 }, 0);
  app.advance(100);
  const count = channel.events.length, id = app.market.id;
  app.disconnect(client);
  app.advance(200);
  assert.equal(channel.events.length, count);
  assert.equal(app.market.id, id + 1);
  assert.equal(app.health.clients, 0);
  assert.equal(app.history('5m').candles.at(-1).lastTradeId, id + 1);
  assert.throws(() => app.history('__proto__'), /Use 1m or 5m/);
});

test('application enforces debug restrictions and heartbeat expiry without a real socket', () => {
  const app = service({ debug: false });
  const channel = new MemoryChannel();
  const client = app.open(channel, 0);
  assert.throws(() => client.receive({ type: 'override', tier: 'minimal' }, 0), /Unknown command/);
  assert.throws(() => client.receive({ type: 'debug', action: 'skip_book' }, 0), /Unknown command/);
  app.advance(30001);
  assert.deepEqual(channel.closes, [{ code: 4001, reason: 'Heartbeat timeout' }]);
});

test('one throwing client cannot stop the shared feed or another subscriber', () => {
  const app = service(), broken = new MemoryChannel(), healthy = new MemoryChannel();
  const a = app.open(broken, 0), b = app.open(healthy, 0);
  a.receive({ type: 'subscribe', interval: '1m', revision: 1 }, 0);
  b.receive({ type: 'subscribe', interval: '1m', revision: 1 }, 0);
  broken.send = () => { throw new Error('Broken channel'); };
  const before = app.market.id;
  app.advance(100); app.advance(200);
  assert.equal(app.market.id, before + 2);
  assert.equal(app.clients.size, 1);
  assert.equal(healthy.ofType('trades').at(-1).trades[0].id, before + 2);
  assert.equal(broken.closes[0].code, 1011);
});
