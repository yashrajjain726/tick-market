# Configuration and operating limits

Live prices, book levels, candles, trades, connection measurements, and delivery rates come from the backend. The Flutter screen also reads the market's name, symbol, base/quote assets, currency sign, badge, summary window, and supported intervals from the server handshake. It displays placeholders until that metadata arrives.

Defaults are necessary for a reproducible assignment. They are named, centralized, and separate from live data. Protocol precision, simulator mathematics, and design tokens are intentional code constants; arbitrary values should not become environment variables just to remove literals.

## Node configuration

Run the defaults:

```sh
./scripts/start-backend.sh
```

Or edit a copy of `backend/config.example.json` and pass it to the same command:

```sh
CONFIG_FILE=config.example.json ./scripts/start-backend.sh
```

The script changes into `backend`, so relative configuration paths are resolved from that directory. An absolute path also works. Zod schemas in `src/app/config.mjs` reject unknown options, invalid types, out-of-range values, inconsistent market identifiers, or thresholds that break hysteresis before sockets or timers are created. Nested partial settings retain the remaining defaults; parsed configuration and its nested objects are frozen. The domain keeps its own policy consistency rules without importing Zod.

Environment values override the JSON file:

| Variable | Purpose | Default |
| --- | --- | --- |
| `CONFIG_FILE` | JSON configuration file | No file; built-in defaults |
| `HOST` / `PORT` | Bind address and port | `0.0.0.0` / `8080` |
| `SEED` | Deterministic PRNG seed, unsigned nonzero 32-bit integer | `42` |
| `START_MS` | Logical time origin before warmup | Current time minus warmup |
| `MAX_CLIENTS` | Maximum simultaneous WebSocket connections | `250` |
| `DEBUG_CONTROLS` | Explicitly enable (`1`) or disable (`0`) demo controls | Enabled locally; disabled under `NODE_ENV=production` |

The file also accepts:

- `market`: `symbol`, `name`, `baseAsset`, `quoteAsset`, `quoteSign`, `badge`, `initialPrice` (integer cents), and `bookLevels` (10–100 per side).
- `policy`: tier `periods`, RTT/jitter entry and recovery thresholds, required report counts, dwell, missing-report timeout, report interval, heartbeat timeout, status interval, and rate window. See `src/features/market/domain/delivery_config.mjs` for the named defaults. Periods must be ordered and between 100 and 60,000 ms; entry/recovery thresholds must preserve hysteresis.
- Server resources: `maxHttpConnections`, `maxPayloadBytes`, `maxBufferedBytes`, `messagesPerSecond`, `closeGraceMs`, `headersTimeoutMs`, and `requestTimeoutMs`.
- Simulator startup: `warmup` and `tickMs`. Logical trades advance 100 ms each; changing the scheduler interval changes simulation speed relative to wall time.

`GET /v1/market` and the WebSocket `hello.market` object publish the effective market descriptor. A configuration such as Ether/EUR updates mobile labels without rebuilding Flutter. This is still **one configured market per server**, not a multi-market subscription API. Version 1 retains two fixed intervals (1m/5m), two price decimal places, and eight quantity decimal places. Supporting different precision or new interval types requires a deliberate protocol update on both sides.

## Flutter configuration

The composition root reads `app/config/app_config.dart` once and injects policies into networking and the domain session. No service locator or screen-level networking is involved.

```sh
cd mobile
flutter run \
  --dart-define=API_URL=http://10.0.2.2:8080 \
  --dart-define=REQUEST_TIMEOUT_MS=4000 \
  --dart-define=HANDSHAKE_TIMEOUT_MS=5000 \
  --dart-define=RECONNECT_MAX_MS=16000
```

`API_URL` must be an HTTP/HTTPS origin without credentials, query, fragment, or non-root path. The Connection lab can change it at runtime. Deployment duration values are validated; bad build configuration fails during startup rather than silently selecting an unintended server.

Other explicit policies live close to their owners:

| File | Policy |
| --- | --- |
| `core/network/network_policy.dart` | Whole-request timeout, handshake timeout, close timeout, 1 MB HTTP response cap, four connections per host |
| `features/market/domain/configuration/market_policy.dart` | Heartbeat, stale/hello deadlines, retry/backoff/jitter, bounded caches and wire validation limits |
| `features/market/presentation/market_view_policy.dart` | 48 visible candles, 10 book rows, 8 trades, 100 ms UI notification batching |
| `core/theme/app_theme.dart` | Shared colors and typography |

The session accepts injected policy values and retry randomness for deterministic tests. HTTP retries and reconnects use capped exponential backoff with jitter. Domain failures are typed and translated to user-facing copy in presentation.

## Failure behavior

- An unavailable server causes bounded, jittered reconnect attempts; cached values remain stale.
- Repeated starts cannot open parallel sockets. A connection that completes after pause/disposal is closed.
- A missing or incompatible `hello` times out even if other frames arrive. Upgrade the app and backend together; the mobile client requires the market metadata contract.
- An HTTP request has one deadline covering headers and body, aborts on timeout, and rejects oversized streamed bodies. Error responses fail immediately without waiting for their bodies to finish.
- Invalid frames, sequence gaps, and buffer overflow mark the book unsynchronized. Recovery requests are coalesced so one snapshot is outstanding at a time, with backoff for retries.
- Book sides, candle history, buffered deltas, and recent trades have explicit retention limits. A new stream epoch invalidates old chart data; changing servers clears the prior market and book.
- Invalid client commands are ignored with a protocol error. Oversized frames and excessive command rates close that client.
- A full server rejects additional WebSocket upgrades with HTTP 503. A socket exceeding its outbound buffer budget is closed; unresponsive close handshakes are terminated after the configured grace period.
- A client delivery exception is isolated from other subscribers. Shutdown stops the feed and closes HTTP/WebSocket connections; repeated shutdown calls are safe.

## Scalability: measured scope and next boundary

`npm --prefix backend run load-check` starts an isolated ephemeral server and 250 mixed-tier clients for five seconds. The checked-in [result](load-check.json) records the environment, messages, event-loop delay, and observed gaps/errors. Customize the bounded check with `CLIENTS` and `DURATION_MS` (3–10 seconds). Both server and clients run in the same local process, so its memory and event-loop measurements include the load generator.

This proves the tested short concurrent flow, not unlimited capacity, WAN reliability, a long soak, or a production SLA. The 250-client default is an admission limit, not a hardware-independent throughput promise.

The current architecture scales by adding features and replacing adapters. The backend remains a single process with an in-memory authoritative feed and O(client count) fan-out. Independent replicas would generate different stream epochs and cannot safely share REST snapshots and WebSocket deltas through arbitrary load balancing. Before horizontal deployment, introduce a shared ordered feed/epoch and snapshot source, route both transports to the same stream, and persist/replay data where required. Add deployment authentication/TLS, rate limits at the edge, monitoring, and long-duration load/failure testing for the actual target environment. These are deployment requirements, not implemented claims.

Caches survive reconnects within one app process, not app termination. No offline disk persistence, multi-market routing, production trading, or exchange integration is provided. iOS and physical-device validation remain outside the verified Android emulator scope.
