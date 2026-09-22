import { readFileSync } from 'node:fs';
import { z } from 'zod';
import { MARKET_DEFAULTS } from '../features/market/domain/market_definition.mjs';
import { DEFAULT_DELIVERY, deliverySettingsConsistent } from '../features/market/domain/delivery_config.mjs';

const DEFAULTS = Object.freeze({
  host: '0.0.0.0', port: 8080, seed: 42, warmup: 216000, origin: undefined,
  debug: true, tickMs: 100, maxClients: 250, maxHttpConnections: 512,
  maxPayloadBytes: 8192, maxBufferedBytes: 262144, messagesPerSecond: 30,
  closeGraceMs: 2000, headersTimeoutMs: 10000, requestTimeoutMs: 15000,
});
const bounds = {
  port: [0, 65535], seed: [1, 4294967295], warmup: [0, 2160000],
  origin: [0, Number.MAX_SAFE_INTEGER - 1e12], tickMs: [10, 1000],
  maxClients: [1, 10000], maxHttpConnections: [1, 20000],
  maxPayloadBytes: [256, 65536], maxBufferedBytes: [1024, 16777216],
  messagesPerSecond: [1, 1000], closeGraceMs: [100, 10000],
  headersTimeoutMs: [1000, 60000], requestTimeoutMs: [1000, 120000],
};
const integer = (min, max) => z.int().min(min).max(max);
const text = (max) => z.string().min(1).max(max).refine(value => value.trim().length > 0);
const asset = z.string().regex(/^[A-Z0-9-]{1,20}$/);
const marketSchema = z.strictObject(Object.fromEntries(Object.entries({
  symbol: asset, baseAsset: asset, quoteAsset: asset, name: text(32), quoteSign: text(4), badge: text(4),
  initialPrice: integer(100000, 1e10), bookLevels: integer(10, 100),
}).map(([key, schema]) => [key, schema.default(MARKET_DEFAULTS[key])])))
  .refine(m => m.symbol === `${m.baseAsset}-${m.quoteAsset}`, 'Symbol must match baseAsset-quoteAsset').readonly();
const periodsSchema = z.strictObject(Object.fromEntries(Object.entries(DEFAULT_DELIVERY.periods)
  .map(([tier, period]) => [tier, integer(100, 60000).default(period)]))).readonly();
const policySchema = z.strictObject(Object.fromEntries(Object.entries(DEFAULT_DELIVERY)
  .map(([key, value]) => [key, key === 'periods' ? periodsSchema.prefault({}) : integer(1, 60000).default(value)])))
  .refine(deliverySettingsConsistent, 'Delivery thresholds must preserve hysteresis and heartbeat timing').readonly();
const configSchema = z.strictObject({
  ...Object.fromEntries(Object.entries(bounds).map(([key, [min, max]]) =>
    [key, key === 'origin' ? integer(min, max).optional() : integer(min, max).default(DEFAULTS[key])])),
  host: z.string().trim().min(1).default(DEFAULTS.host), debug: z.boolean().default(DEFAULTS.debug),
  market: marketSchema.prefault({}), policy: policySchema.prefault({}),
}).refine(c => c.maxHttpConnections >= c.maxClients && c.headersTimeoutMs <= c.requestTimeoutMs,
  'Inconsistent server capacity or timeouts').readonly();

export const resolveConfig = (overrides = {}) => configSchema.parse(overrides);
export function loadConfig(env = process.env) {
  const fromFile = env.CONFIG_FILE ? z.record(z.string(), z.unknown()).parse(JSON.parse(readFileSync(env.CONFIG_FILE, 'utf8'))) : {};
  const overrides = { ...fromFile };
  const mappings = { PORT: 'port', HOST: 'host', SEED: 'seed', START_MS: 'origin', MAX_CLIENTS: 'maxClients' };
  for (const [variable, key] of Object.entries(mappings)) {
    if (env[variable] !== undefined) overrides[key] = key === 'host' ? env[variable] : Number(env[variable]);
  }
  if (env.DEBUG_CONTROLS !== undefined) {
    if (!['0', '1'].includes(env.DEBUG_CONTROLS)) throw new Error('DEBUG_CONTROLS must be 0 or 1');
    overrides.debug = env.DEBUG_CONTROLS === '1';
  } else if (env.NODE_ENV === 'production') overrides.debug = false;
  return resolveConfig(overrides);
}
