import { WebSocketServer, WebSocket } from 'ws';

export function attachMarketWebSocketGateway(server, service, { monotonicNow, wallNow, config }) {
  const wss = new WebSocketServer({ noServer: true, maxPayload: config.maxPayloadBytes, perMessageDeflate: false });
  server.on('upgrade', (req, socket, head) => {
    socket.on('error', () => {});
    let path;
    try { path = new URL(req.url, 'http://localhost').pathname; }
    catch { socket.destroy(); return; }
    if (path !== '/v1/stream') { socket.destroy(); return; }
    if (wss.clients.size >= config.maxClients) {
      socket.end('HTTP/1.1 503 Service Unavailable\r\nConnection: close\r\nRetry-After: 5\r\nContent-Length: 0\r\n\r\n');
      return;
    }
    wss.handleUpgrade(req, socket, head, ws => wss.emit('connection', ws));
  });
  wss.on('connection', ws => {
    let closeTimer;
    const channel = {
      send(event) {
        if (ws.readyState !== WebSocket.OPEN) return false;
        if (ws.bufferedAmount > config.maxBufferedBytes) { this.close(1013, 'Slow consumer: resynchronize'); return false; }
        ws.send(JSON.stringify(event));
        return true;
      },
      close(code, reason) {
        if (closeTimer || ws.readyState === WebSocket.CLOSED) return;
        ws.close(code, reason);
        closeTimer = setTimeout(() => ws.terminate(), config.closeGraceMs).unref();
      },
    };
    const session = service.open(channel, monotonicNow());
    ws.on('error', () => {});
    ws.on('close', () => { clearTimeout(closeTimer); service.disconnect(session); });
    channel.send({ type: 'hello', streamId: service.market.streamId,
      symbol: service.definition.symbol, market: service.definition, serverTime: wallNow(), debug: service.debug });
    let second = 0, messages = 0;
    ws.on('message', raw => {
      const now = monotonicNow();
      try {
        const currentSecond = Math.floor(now / 1000);
        if (currentSecond !== second) { second = currentSecond; messages = 0; }
        if (++messages > config.messagesPerSecond) { channel.close(1008, 'Message rate exceeded'); return; }
        const command = JSON.parse(raw.toString());
        if (!command || typeof command !== 'object' || Array.isArray(command)) throw new Error('Expected object');
        session.receive(command, now);
      } catch {
        channel.send({ type: 'error', message: 'Invalid message ignored' });
      }
    });
  });
  return {
    close() {
      for (const ws of wss.clients) ws.terminate();
      wss.close();
    },
  };
}
