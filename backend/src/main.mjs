import { createMarketServer } from './app/create_market_server.mjs';
import { loadConfig } from './app/config.mjs';

let app;
try {
  const config = loadConfig();
  app = createMarketServer(config);
  const port = await app.listen();
  console.log(`Tick market · http://${config.host}:${port} · ${config.market.symbol} · seed ${config.seed}`);
  for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, async () => { await app.close(); process.exit(0); });
} catch (error) {
  await app?.close();
  console.error(`Unable to start Tick: ${error.message}`);
  process.exitCode = 1;
}
