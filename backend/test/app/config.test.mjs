import test from 'node:test';
import assert from 'node:assert/strict';
import { loadConfig, resolveConfig } from '../../src/app/config.mjs';
import { DeliveryPolicy } from '../../src/features/market/domain/delivery_policy.mjs';

test('invalid runtime options fail before opening sockets or starting timers', () => {
  for (const options of [{ port: NaN }, { warmup: -1 }, { maxClients: 0 },
    { market: { symbol: 'ETH-USD' } }, { policy: { periods: { full: 0 } } },
    { policy: { degradedRtt: 100 } }, { unexpected: 1 }]) {
    assert.throws(() => resolveConfig(options));
  }
  assert.throws(() => loadConfig({ DEBUG_CONTROLS: 'yes' }));
});
test('production disables debug controls and explicit environment overrides are validated', () => {
  assert.equal(loadConfig({ NODE_ENV: 'production' }).debug, false);
  const config = loadConfig({ PORT: '9000', SEED: '91', MAX_CLIENTS: '40', DEBUG_CONTROLS: '0' });
  assert.equal(config.port, 9000);
  assert.equal(config.seed, 91);
  assert.equal(config.maxClients, 40);
  assert.equal(config.debug, false);
});
test('custom policy controls both transitions and delivery rates', () => {
  const { policy } = resolveConfig({ policy: { downgradeReports: 3, periods: { degraded: 750 } } });
  const p = new DeliveryPolicy(0, policy);
  p.report(400, 90, 2000); p.report(400, 90, 4000);
  assert.equal(p.tier, 'full');
  p.report(400, 90, 6000);
  assert.equal(p.tier, 'degraded'); assert.equal(p.period, 750);
});

test('schemas reject unknown nested fields and malformed settings without coercion', () => {
  for (const options of [null, [], 'config', { port: '8080' }, { debug: 1 }, { host: ' ' },
    { market: [] }, { market: { unexpected: 1 } }, { market: { name: ' ' } },
    { policy: [] }, { policy: { periods: [] } }, { policy: { typo: 1 } },
    { policy: { periods: { turbo: 100 } } }, { policy: { dwellMs: 1.5 } },
    { policy: { maxMetricMs: Infinity } }, { maxClients: 513 },
    { headersTimeoutMs: 20000 }, { policy: { heartbeatTimeoutMs: 10000 } }]) {
    assert.throws(() => resolveConfig(options), JSON.stringify(options));
  }
});
test('partial nested configuration retains frozen defaults without mutating input', () => {
  const input = { port: 0, origin: 0, policy: { periods: { degraded: 750 } }, market: { name: 'Demo Bitcoin' } };
  const original = structuredClone(input);
  const config = resolveConfig(input);
  assert.deepEqual(input, original);
  assert.deepEqual(config.policy.periods, { full: 100, degraded: 750, minimal: 2000 });
  assert.equal(config.policy.downgradeReports, 2);
  assert.equal(config.market.symbol, 'BTC-USD');
  assert.equal(config.market.name, 'Demo Bitcoin');
  assert.equal(config.origin, 0);
  assert.equal(config.port, 0);
  for (const object of [config, config.market, config.policy, config.policy.periods]) assert.ok(Object.isFrozen(object));
  assert.equal(resolveConfig().policy.periods.degraded, 500);
});
