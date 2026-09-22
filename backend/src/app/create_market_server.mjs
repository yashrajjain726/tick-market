import http from 'node:http';
import { randomUUID } from 'node:crypto';
import { resolveConfig } from './config.mjs';
import { Market } from '../features/market/domain/market.mjs';
import { FEED } from '../features/market/domain/market_definition.mjs';
import { MarketService } from '../features/market/application/market_service.mjs';
import { createMarketHttpHandler } from '../features/market/infrastructure/http/market_http_handler.mjs';
import { attachMarketWebSocketGateway } from '../features/market/infrastructure/websocket/market_websocket_gateway.mjs';

export function createMarketServer({ monotonicNow = () => performance.now(), wallNow = () => Date.now(), ...options } = {}) {
  const config = resolveConfig(options);
  const market = new Market({ seed: config.seed, warmup: config.warmup, settings: config.market,
    origin: config.origin ?? Math.floor(wallNow() / FEED.stepMs) * FEED.stepMs - config.warmup * FEED.stepMs,
    streamId: randomUUID() });
  const service = new MarketService(market, config);
  const server = http.createServer(createMarketHttpHandler(service, config));
  server.maxConnections = config.maxHttpConnections;
  server.headersTimeout = config.headersTimeoutMs;
  server.requestTimeout = config.requestTimeoutMs;
  const gateway = attachMarketWebSocketGateway(server, service, { monotonicNow, wallNow, config });
  const timer = setInterval(() => service.advance(monotonicNow()), config.tickMs);
  let closing;
  return {
    server, market, config, clients: service.clients,
    async listen(port = config.port, host = config.host) {
      await new Promise((resolve, reject) => {
        server.once('error', reject);
        server.listen(port, host, () => { server.off('error', reject); resolve(); });
      });
      return server.address().port;
    },
    close() {
      return closing ??= (async () => {
        clearInterval(timer);
        gateway.close();
        await new Promise(resolve => {
          server.close(resolve);
          server.closeAllConnections();
        });
      })();
    },
  };
}
