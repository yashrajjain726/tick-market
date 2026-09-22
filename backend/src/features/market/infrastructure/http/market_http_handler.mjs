/** HTTP routing and response serialization are outside the application layer. */
export function createMarketHttpHandler(service, { debug }) {
  return (req, res) => {
    let url;
    try { url = new URL(req.url, 'http://localhost'); }
    catch { res.writeHead(400).end(); return; }
    res.setHeader('Content-Type', 'application/json');
    res.setHeader('Cache-Control', 'no-store');
    if (req.method !== 'GET') {
      res.writeHead(405).end(JSON.stringify({ error: 'GET required' }));
      return;
    }
    let data;
    if (url.pathname === '/health') data = service.health;
    else if (url.pathname === '/v1/market') data = service.definition;
    else if (url.pathname === '/v1/book') data = service.book;
    else if (url.pathname === '/v1/candles') {
      try { data = service.history(url.searchParams.get('interval') ?? '1m'); }
      catch { res.writeHead(400).end(JSON.stringify({ error: 'Use 1m or 5m' })); return; }
    } else if (url.pathname === '/v1/trades') data = service.trades;
    else { res.writeHead(404).end(JSON.stringify({ error: 'Not found' })); return; }
    // Capture before delaying to exercise the snapshot/delta race.
    const delay = debug ? Math.min(2500, Math.max(0, Number(url.searchParams.get('delay')) || 0)) : 0;
    const body = JSON.stringify(data);
    if (delay) setTimeout(() => { if (!res.destroyed) res.end(body); }, delay).unref();
    else res.end(body);
  };
}
