import assert from 'node:assert/strict';
import { monitorEventLoopDelay } from 'node:perf_hooks';
import { WebSocket } from 'ws';
import { createMarketServer } from '../src/app/create_market_server.mjs';

// Local smoke check, not a production capacity benchmark. Both endpoints run here.
const clients = Number(process.env.CLIENTS ?? 250);
const durationMs = Number(process.env.DURATION_MS ?? 5000);
assert.ok(Number.isInteger(clients) && clients > 0 && clients <= 1000);
assert.ok(Number.isInteger(durationMs) && durationMs >= 3000 && durationMs <= 10000);
const app = createMarketServer({ warmup: 500, maxClients: clients, maxHttpConnections: clients + 100 });
const sockets = [], failures = [], counts = [];
const lag = monitorEventLoopDelay({ resolution: 10 });
const before = process.memoryUsage().heapUsed;
try {
  const port = await app.listen(0, '127.0.0.1');
  await Promise.all(Array.from({ length: clients }, (_, index) => new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${port}/v1/stream`);
    sockets.push(ws);
    const count = { book: 0, trades: 0, candles: 0 }; counts.push(count);
    let sequence;
    const deadline = setTimeout(() => reject(new Error('Connection timed out')), 5000);
    ws.on('error', error => { failures.push(error.message); reject(error); });
    ws.on('message', raw => {
      const event = JSON.parse(raw);
      if (event.type === 'hello') {
        ws.send(JSON.stringify({ type: 'subscribe', interval: '1m', revision: 1 }));
        ws.send(JSON.stringify({ type: 'override', tier: ['full', 'degraded', 'minimal'][index % 3] }));
      }
      if (event.type === 'subscribed') { clearTimeout(deadline); resolve(); }
      if (event.type in count) count[event.type]++;
      if (event.type === 'book') {
        if (sequence !== undefined && event.previous !== sequence) failures.push(`Client ${index}: book gap`);
        sequence = event.sequence;
      }
    });
  })));
  lag.enable();
  await new Promise(resolve => setTimeout(resolve, durationMs));
  lag.disable();
  assert.equal(app.clients.size, clients);
  assert.ok(counts.every(count => count.book > 0 && count.trades > 0 && count.candles > 0));
  assert.deepEqual(failures, []);
  console.log(JSON.stringify({ checkedAt: new Date().toISOString(), node: process.version,
    platform: `${process.platform}/${process.arch}`, clients, durationMs,
    mixedTiers: ['full', 'degraded', 'minimal'],
    receivedMessages: counts.reduce((sum, item) => sum + item.book + item.trades + item.candles, 0),
    minimumPerClient: Object.fromEntries(['book', 'trades', 'candles'].map(key => [key, Math.min(...counts.map(c => c[key]))])),
    bookGaps: 0, clientErrors: failures.length,
    eventLoopP99Ms: Number((lag.percentile(99) / 1e6).toFixed(2)),
    combinedClientServerHeapDeltaMiB: Number(((process.memoryUsage().heapUsed - before) / 1048576).toFixed(2)),
    limitation: 'Short localhost smoke check; not a throughput guarantee or long-running soak test.',
  }, null, 2));
} finally {
  lag.disable();
  for (const socket of sockets) socket.terminate();
  await app.close();
}
