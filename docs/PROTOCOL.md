# Tick protocol v1

Base URL: `http://localhost:8080`. WebSocket: `ws://localhost:8080/v1/stream`. Production HTTPS requires WSS. JSON UTF-8, one object per WebSocket frame. One configured symbol per server; `BTC-USD` is the default. Examples and cadence values below use the default configuration.

## Units and identity

- `price`, OHLC, bid/ask price: integer **quote-currency cents** (`6742012` = $67,420.12).
- `quantity`, `volume`, book size: integer **1e-8 base-asset units** (`100000000` = 1 BTC for the default market).
- `time`, `start`: Unix milliseconds, UTC. Bucket start = `floor(time / duration) * duration`.
- `id`, `lastTradeId`, `sequence`, `previous`, `revision`: safe JSON integers.
- `streamId`: UUID for this running server. Identity/order is `(streamId, id)` for trades and `(streamId, sequence)` for books. Never combine different epochs.
- Book quantities are absolute replacements, never arithmetic deltas. Zero deletes a price level.
- Integer precision is preserved in Node (`Number.isSafeInteger` range) and Dart integers. A 5-minute candle has at most 3,000 generated trades, far below the safe-integer volume limit.

## REST

All endpoints accept GET and return `Cache-Control: no-store`. Invalid intervals return 400, unknown paths 404, other HTTP methods 405.

| Path | Response |
| --- | --- |
| `/health` | `ok`, `symbol`, `streamId`, `clients` |
| `/v1/market` | Effective market descriptor (also included in `hello.market`) |
| `/v1/book` | `streamId`, `sequence`, `bids`, `asks` (20 levels per side by default) |
| `/v1/candles?interval=1m` | `streamId`, `interval`, `candles` (up to 120, ascending start) |
| `/v1/candles?interval=5m` | Same shape, 5-minute buckets |
| `/v1/trades` | `streamId`, `trades` (up to 40, newest first) |

With debug enabled, `?delay=1000` delays a REST response up to 2,500 ms. The JSON snapshot is captured **before** the delay. This deliberately creates the snapshot/delta race for tests.

```json
{"streamId":"epoch","sequence":23,"bids":[[6742000,12000000]],"asks":[[6742400,9000000]]}
```

Only one level is illustrated above; the default snapshots include twenty per side.

```json
{"start":1767225600000,"open":6742000,"high":6743000,"low":6741000,"close":6742500,"volume":78200000,"lastTradeId":216040}
```

## Client → server

```json
{"type":"subscribe","interval":"1m","revision":1}
{"type":"ping","nonce":123}
{"type":"metrics","rtt":84.5,"jitter":11.0}
{"type":"override","tier":"minimal"}
{"type":"override","tier":"auto"}
{"type":"debug","action":"skip_book"}
{"type":"debug","action":"disconnect"}
```

Subscriptions replace the active interval for this connection. `revision` must be a positive safe integer; the client increments it each subscription, including reconnect. The same subscription receives trades, book deltas, status, and chart messages. Override accepts `auto`, `full`, `degraded`, `minimal`. Debug messages affect only the sending socket. `DEBUG_CONTROLS=0` disables overrides and debug messages.

Incoming frames are capped at 8 KiB and 30 messages per second. Metrics are accepted at most once per second; RTT/jitter must be finite numbers from 0 through 60,000 ms. Invalid messages receive an error response without crashing the server or changing the market stream.

## Server → client

Immediately after upgrade:

```json
{"type":"hello","streamId":"epoch","symbol":"BTC-USD","serverTime":1767225600000,"debug":true,"market":{"symbol":"BTC-USD","name":"Bitcoin","baseAsset":"BTC","quoteAsset":"USD","quoteSign":"$","badge":"₿","priceScale":100,"quantityScale":100000000,"intervals":["1m","5m"],"summaryWindow":"6h"}}
```

After subscribe:

```json
{"type":"subscribed","interval":"1m","revision":1}
```

The server also sends recent trades and current tier status immediately. Chart history is fetched separately over REST.

Ordered book changes, normally 5 Hz:

```json
{"type":"book","streamId":"epoch","sequence":24,"previous":23,"bids":[[6741800,0],[6741600,3400000]],"asks":[[6742400,9800000]]}
```

The client must buffer before snapshot completion, check continuity, and apply a whole update atomically. Snapshot order is not relied on; the client sorts bids descending and asks ascending. Gaps and backwards updates cause resnapshot, not best-effort interpolation.

Trades, normally 10 Hz; arrays may include several trades in the initial recent snapshot:

```json
{"type":"trades","streamId":"epoch","trades":[{"id":216040,"time":1767225604000,"price":6742500,"quantity":340000,"side":"buy"}]}
```

At subscribe and approximately once per second this envelope also includes `summary` with integer `reference`, `price`, `high`, `low`, `volume`, and `window: "6h"`. The summary uses the latest 360 one-minute buckets (including a partial current bucket).

Adaptive chart delivery:

```json
{"type":"candles","streamId":"epoch","interval":"1m","revision":1,"candles":[{"start":1767225600000,"open":6742000,"high":6743000,"low":6741000,"close":6742500,"volume":78200000,"lastTradeId":216040}]}
```

Each candle is a **complete, authoritative OHLCV value**, not a patch. Multiple buckets can arrive together at a boundary. Keep the highest `lastTradeId` for each bucket, ignore old subscription revisions/epochs, and never sum the volume of repeated candle messages.

Server-owned delivery state, at subscribe, after valid metrics/overrides, on tier changes, and approximately once per second:

```json
{"type":"status","tier":"degraded","targetHz":2,"effectiveHz":1.8,"override":null,"reason":"Sustained latency or jitter"}
```

`effectiveHz` counts successfully enqueued chart frames in the last five seconds, divided by five (or connection age in seconds during startup, with a one-second minimum). It is a server delivery measurement; it does not claim an independent on-device render measurement. `override` is null in automatic mode. Thresholds and transition rules are in the README.

Pong and errors:

```json
{"type":"pong","nonce":123}
{"type":"error","message":"Invalid message ignored"}
```

## Recovery and limits

- Client heartbeat watchdog: over 8 seconds without an incoming frame or an expected pong → stale and reconnect.
- Server inactivity timeout: no client messages for over 30 seconds → close code 4001.
- Backpressure: socket send queue > 256 KiB → close code 1013; a fresh snapshot is required after reconnect.
- Debug disconnect: close code 4000.
- Close/error: retain cached values, invalidate all request generations, cancel timers/subscriptions, then exponential retry with jitter.
- Process restart: a new stream UUID prevents old book sequences/candle versions from being treated as current.

## Market metadata

`GET /v1/market` returns the configured descriptor. The WebSocket `hello` includes the same object under `market` (along with its existing `symbol`, `streamId`, `serverTime`, and `debug`). The Flutter client requires this descriptor before initializing the session.

```json
{"symbol":"BTC-USD","name":"Bitcoin","baseAsset":"BTC","quoteAsset":"USD","quoteSign":"$","badge":"₿","priceScale":100,"quantityScale":100000000,"intervals":["1m","5m"],"summaryWindow":"6h"}
```

Metadata is validated before entering the domain. Unsupported precision, unknown intervals, missing metadata, or inconsistent identifiers are rejected. Update both app and server together. This protocol serves one configured market; URL deep links open that market and do not select a separate feed.

The server returns HTTP 503 with `Retry-After: 5` when the WebSocket connection limit is reached. Runtime defaults and configurable limits are documented in [CONFIGURATION.md](CONFIGURATION.md).
