import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { WebSocket } from 'ws';
import { createMarketServer } from '../../../../src/app/create_market_server.mjs';

const waitFor = (ws, predicate, timeout = 3000) => new Promise((resolve, reject) => {
  const timer = setTimeout(() => { ws.off('message', listener); reject(new Error('Message timed out')); }, timeout);
  const listener = raw => { const m = JSON.parse(raw); if (predicate(m)) { clearTimeout(timer); ws.off('message', listener); resolve(m); } };
  ws.on('message', listener);
});
const send = (ws, value) => ws.send(JSON.stringify(value));

test('real REST + two WebSocket clients: independent tiers, malformed input, gap, reconnect', async t => {
  const app = createMarketServer({ warmup: 50, tickMs: 10 });
  const port = await app.listen(0, '127.0.0.1');
  t.after(() => app.close());
  const base = `http://127.0.0.1:${port}`;
  const a = new WebSocket(`ws://127.0.0.1:${port}/v1/stream`);
  const b = new WebSocket(`ws://127.0.0.1:${port}/v1/stream`);
  const hello = waitFor(a, m => m.type === 'hello');
  await Promise.all([once(a, 'open'), once(b, 'open')]);
  const epoch = (await hello).streamId;
  send(a, { type: 'subscribe', interval: '1m', revision: 1 });
  send(b, { type: 'subscribe', interval: '5m', revision: 2 });
  const changed = waitFor(a, m => m.type === 'status' && m.tier === 'minimal');
  send(a, { type: 'override', tier: 'minimal' });
  assert.equal((await changed).targetHz, 0.5);
  const unchanged = waitFor(b, m => m.type === 'status');
  send(b, { type: 'metrics', rtt: 20, jitter: 3 });
  assert.equal((await unchanged).tier, 'full');
  const error = waitFor(a, m => m.type === 'error'); a.send('{broken'); await error;
  const pong = waitFor(a, m => m.type === 'pong'); send(a, { type: 'ping', nonce: 1 }); assert.equal((await pong).nonce, 1);
  const deltas = [];
  const listener = raw => { const m = JSON.parse(raw); if (m.type === 'book') deltas.push(m); };
  a.on('message', listener);
  const snap = await (await fetch(`${base}/v1/book?delay=100`)).json();
  const buffered = deltas.filter(d => d.sequence > snap.sequence);
  assert.ok(buffered.length > 0, 'WS messages arrived while REST snapshot was in flight');
  let sequence = snap.sequence;
  for (const d of buffered) { assert.equal(d.previous, sequence); sequence = d.sequence; }
  a.off('message', listener);
  const prior = await waitFor(a, m => m.type === 'book');
  send(a, { type: 'debug', action: 'skip_book' });
  const gap = await waitFor(a, m => m.type === 'book'); assert.equal(gap.sequence, prior.sequence + 2);
  const fresh = await (await fetch(`${base}/v1/book`)).json(); assert.ok(fresh.sequence >= gap.sequence);
  const history = await (await fetch(`${base}/v1/candles?interval=5m`)).json(); assert.equal(history.interval, '5m');
  assert.equal((await fetch(`${base}/v1/candles?interval=__proto__`)).status, 400);
  const closed = once(a, 'close'); send(a, { type: 'debug', action: 'disconnect' }); await closed;
  const reconnected = new WebSocket(`ws://127.0.0.1:${port}/v1/stream`);
  assert.equal((await waitFor(reconnected, m => m.type === 'hello')).streamId, epoch);
  reconnected.close(); b.close();
});

test('capacity rejects excess sockets, releases slots, and publishes configured market metadata', async t => {
  const app = createMarketServer({ warmup: 20, maxClients: 1, market: {
    name: 'Ether', symbol: 'ETH-EUR', baseAsset: 'ETH', quoteAsset: 'EUR', quoteSign: '€', badge: 'Ξ', initialPrice: 300000,
  } });
  t.after(() => app.close());
  const port = await app.listen(0, '127.0.0.1');
  const url = `ws://127.0.0.1:${port}/v1/stream`;
  const first = new WebSocket(url);
  const hello = await waitFor(first, event => event.type === 'hello');
  assert.equal(hello.market.name, 'Ether');
  const definition = await (await fetch(`http://127.0.0.1:${port}/v1/market`)).json();
  assert.deepEqual(definition, hello.market);
  const rejected = new WebSocket(url);
  const status = await new Promise((resolve, reject) => {
    rejected.once('error', reject);
    rejected.once('unexpected-response', (_req, res) => { resolve(res.statusCode); res.resume(); rejected.terminate(); });
    // terminate after an unexpected HTTP response can emit an expected local error.
    rejected.on('error', () => {});
  });
  assert.equal(status, 503);
  first.close(); await once(first, 'close');
  // The server's close callback is asynchronous relative to the client's event.
  for (let i = 0; i < 20 && app.clients.size; i++) await new Promise(r => setTimeout(r, 5));
  const next = new WebSocket(url);
  assert.equal((await waitFor(next, event => event.type === 'hello')).symbol, 'ETH-EUR');
  next.close();
  await app.close(); await app.close();
});
