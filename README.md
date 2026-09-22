# Tick — every tick accounted for

A Flutter Android trading screen backed by a deterministic **Node.js** market simulator. One synthetic market (BTC-USD by default), native candlesticks, a synchronized order book, and server-owned delivery tiers for each WebSocket connection. No accounts, exchange API keys, chart WebViews, or third-party market data.

<img src="docs/market.png" alt="Tick running on Android" width="360" />

[Watch the Android demonstration](docs/demo.mp4) · [Architecture guide](docs/ARCHITECTURE.md) · [Configuration and limits](docs/CONFIGURATION.md) · [Protocol reference](docs/PROTOCOL.md) · [Verification](docs/VERIFICATION.md)

## Run it

Requires **Node.js 22+**, **Flutter 3.35.7 / Dart 3.9.2 or compatible**, and an Android SDK. The Flutter app uses `flutter_bloc` for state management and `fl_chart` for native chart rendering. Node uses `ws` for WebSockets and Zod for startup configuration validation. Lockfiles are included; the new packages are pinned to `fl_chart 1.2.0` and `zod 4.6.5`.

From the repository root, one command installs the locked backend dependencies and starts the feed:

```sh
./scripts/start-backend.sh
```

In another terminal:

```sh
cd mobile
flutter pub get
flutter run -d <android-device-id>
```

Server identity, tier policy, and resource limits are configurable through a validated JSON file or environment overrides. Market labels are supplied by the backend. See [configuration and operating limits](docs/CONFIGURATION.md).

The default backend address is `http://10.0.2.2:8080`, Android Emulator's route to your host. The server listens on port 8080 on all interfaces. Verify it with `curl http://localhost:8080/health`.

For a physical Android device, connect it to the same LAN and use your computer's LAN address:

```sh
flutter run --dart-define=API_URL=http://192.168.1.10:8080
```

Alternatively use USB forwarding with `adb reverse tcp:8080 tcp:8080` and `API_URL=http://127.0.0.1:8080`. The **Connection lab** (sliders icon, top right) also lets you change the backend address without rebuilding. Allow the port through your computer's firewall if needed.

Build a standalone, installable APK (no Flutter tool or Metro connection required to use it):

```sh
cd mobile
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

The local handoff also contains `artifacts/tick-android.apk`; build outputs are excluded from Git. The APK still needs the Node backend running. Release builds use a development signing key for this assignment; use your own release key for store distribution. Local HTTP is enabled in the Android manifest for this demo.

## Architecture and state

Both projects use **feature-first clean architecture**. Each market feature owns its layers; `app` composes dependencies and `core` contains only shared infrastructure or styling.

```text
mobile/lib/
  app/                      App lifecycle and constructor-based dependency injection
  core/                     Generic HTTP/WebSocket transport and app theme
  features/market/
    domain/                 Entities, repository ports, services, session use case
    data/                   Remote data source, DTO validation, repository adapter
    presentation/           Bloc/events/state, page, chart/book widgets, formatters
backend/src/
  main.mjs                  Process configuration and shutdown
  app/                      Server composition, clocks, feed timer
  features/market/
    domain/                 Seeded feed, candles/book, tier policy, delivery buffer
    application/            MarketService and per-client ClientSession
    infrastructure/         HTTP routes and WebSocket adapter
```

Flutter dependencies point inward: **presentation → domain ← data**. `MarketSession` owns synchronization, subscriptions, recovery, cached state, and connection lifetime. It consumes a domain-owned `MarketRepository` interface and typed events, without importing Flutter, JSON parsing, or transport implementations. `RemoteMarketRepository` validates wire data and implements that interface. The app's composition root injects the concrete adapter through constructors.

`MarketBloc` consumes typed UI/lifecycle events and emits immutable `MarketState` snapshots through `BlocBuilder`. A feature-scoped `BlocProvider` owns and closes the Bloc; the connection lab receives the same instance. `bloc_concurrency` processes commands in one ordered queue, while network opening runs outside that queue so pause/offline commands remain responsive. Session changes are coalesced to at most 10 Hz; user actions emit immediately, and Equatable suppresses equal states. Immutable candle/trade values and atomic book replacement avoid exposing partial updates. The chart is in a `RepaintBoundary`; crosshair interaction lives in its own widget state and updates immediately, independently of network delivery. There are only 48 visible candles, 20 book rows, and 8 displayed recent trades.

The Node dependency direction is **infrastructure → application → domain**. `MarketService` advances one shared market; each `ClientSession` owns its own delivery policy and candle buffer. The application takes an injected channel and explicit time values, so its behavior can be tested without real sockets or timers. HTTP routing, JSON serialization, socket backpressure, process environment, and scheduling stay outside the inner layers. Over 256 KiB of queued socket data closes the slow consumer with code 1013; recovery then starts from a snapshot.

Tests mirror the feature layers and include automated dependency-boundary checks. See the [architecture guide](docs/ARCHITECTURE.md) for the full file map, ownership, and how to add a feature.

## Package choices and assignment boundaries

| Package | Responsibility | Application-owned behavior |
| --- | --- | --- |
| [`flutter_bloc` 9.1.1](https://pub.dev/packages/flutter_bloc), [`bloc_concurrency` 0.3.0](https://pub.dev/packages/bloc_concurrency), [`equatable` 2.1.0](https://pub.dev/packages/equatable) | Bloc/provider lifecycle, ordered event processing, state equality | Immutable market snapshots, UI commands, 100 ms market-update batching; domain recovery remains framework-independent |
| [`fl_chart` 1.2.0](https://pub.dev/packages/fl_chart) | Native candle/volume rendering, axes, hit testing, crosshair drawing | Fetch history, choose intervals, merge/version candles, retain caches, select timestamps, display stale state |
| [Zod 4.6.5](https://zod.dev/) | Strict startup schemas, type/range checks, nested defaults, readable errors, immutable parsed settings | Market identity constraints, tier hysteresis relationships, environment precedence |
| [`ws`](https://github.com/websockets/ws) (existing) | Node WebSocket protocol implementation | Per-client tiers, RTT/jitter reports, candle cadence, command limits, recovery and backpressure policy |

The assignment permits chart libraries that render app-supplied values. `fl_chart` receives only our candle and volume values; it performs no fetching or market aggregation. Plot interpolation is disabled, and unchanged candle data reuses the existing plot during book/trade updates. Zod stays in `app/config.mjs`; neither domain imports a package.

Packages handle rendering, state delivery/lifecycle and structural validation. Typed Bloc events and immutable snapshots add explicit presentation models while the domain algorithms remain independent. Package adoption reduces custom infrastructure responsibility; it does not guarantee fewer total lines or a smaller binary. The packages are MIT licensed.

The SDK HTTP/WebSocket transport, small Node HTTP router and constructor injection remain sufficient here. The domain still owns generation guards, complete OHLCV, snapshot replay and delivery policy. Lockfiles and package-boundary regression tests make upgrades deliberate.

## Repeatable synthetic market

A 32-bit xorshift PRNG (default seed 42) creates a mean-reverting random walk around a moving price anchor and integer trade sizes. The server warms up six hours of 100 ms trades, so both 1m and 5m history are available immediately. It retains 500 candles per interval and 40 recent trades. The UI uses a rolling 360 one-minute-bucket reference window, labeled **6h** (the active minute is partial).

Each trade has a strictly increasing `id`, a millisecond UTC timestamp, a cent-denominated price, and satoshi-denominated quantity. Ordering is `(streamId, id)`; restarting the server creates a new UUID `streamId`. Logical market time advances exactly 100 ms per generated trade. If the Node event loop stalls, simulated time slows rather than skipping trades or manufacturing a catch-up burst. This clock can drift behind wall time under load.

```sh
SEED=72 START_MS=1767225600000 ./scripts/start-backend.sh
```

`START_MS` is the time origin **before** the six-hour warmup. Same seed, origin, and number of steps reproduce identical trades and OHLCV. Book generation uses no trade RNG. Every 200 ms it generates 20 non-crossing levels per side around the latest price and emits changed levels/removals. This is a plausible synthetic depth display, not a matching engine or order-execution service.

## Candle correctness and interval changes

The engine folds **every trade** into the 1m and 5m OHLCV aggregates before considering delivery. The client consumes complete candle values, not price samples. Per-client buffers retain the latest complete value for each changed bucket; at rollover, the final closed candle and new active candle can travel in the same message. Minimal delivery therefore retains all highs, lows, and volume between messages.

The app subscribes to the chosen interval, buffers arriving candles, and fetches REST history. It merges by bucket start, taking the greater `lastTradeId`. Duplicate candles are idempotent. Each subscription has a revision; HTTP requests also capture the session generation and selected interval. A late old request, old socket, or old subscription cannot replace the current chart. Empty history displays a waiting state and live trades can fill it. A failed history request retries with exponential backoff starting at two seconds, capped at 16 seconds plus 0–250 ms jitter. Cached candles remain visibly stale until fresh history succeeds.

Tap, hold, or drag horizontally on the native chart to inspect date/time and OHLC. Volume bars and the current candle's volume are also shown. Prices use integers for all protocol/state calculations; floating point is used only for plotting, percentage presentation, and timing statistics.

## Order-book synchronization

1. Open the WebSocket, read the stream epoch, subscribe, and begin buffering deltas.
2. Fetch a REST snapshot with its `sequence` watermark.
3. Discard buffered deltas already covered by the snapshot; replay later deltas in arrival order. Each must satisfy `previous == localSequence` and `sequence == localSequence + 1`.
4. Atomically publish the complete replayed book. A zero quantity deletes a level. Sort locally and show the best 10 per side.
5. An exact repeat of the current sequence is ignored. A backward sequence, gap, invalid/crossed book, or buffer overflow marks the book unsynchronized and starts a fresh snapshot. Cached levels remain visible with a stale/syncing label. Snapshot requests are coalesced, with exponential retry backoff starting at 500 ms and capped at 16 seconds plus jitter. Request generations prevent older snapshots winning.

The buffer is capped at 512 deltas, and each local book side is capped at 500 levels. A new epoch invalidates synchronization and clears prior chart caches. The same handshake runs after each reconnect; a missing or incompatible hello is timed out. Use **Skip a delta** in Connection lab to deliberately omit one server delta for this socket; the recovery counter should increase and the book return to synchronized.

## RTT, jitter, tiers, and hysteresis

Every two seconds, the app sends a nonce-bearing application ping on the same WebSocket. The server immediately echoes its nonce. A monotonic `Stopwatch` measures full round-trip time (not one-way latency). Only outstanding nonces are accepted.

- Reported RTT: first sample initializes the estimate; then `RTT = 0.25 × sample + 0.75 × previousEstimate`.
- Reported jitter: mean absolute difference between adjacent raw RTT samples in the most recent 10 samples (0 until two samples exist).
- The app reports both values after each pong. The server accepts at most one report per second and validates finite values in `[0, 60000]` ms.

| State | Target chart rate | Automatic transitions |
| --- | --- | --- |
| Full | 10 Hz / 100 ms | RTT > 250 ms **or** jitter > 80 ms → degraded; RTT > 700 ms **or** jitter > 200 ms → minimal |
| Degraded | 2 Hz / 500 ms | Severe thresholds above → minimal; RTT < 180 ms **and** jitter < 50 ms → full |
| Minimal | 0.5 Hz / 2 seconds | RTT < 550 ms **and** jitter < 140 ms → degraded |

Downgrades require **2 consecutive qualifying reports**, upgrades **4**, and any report-driven transition requires a **5-second minimum dwell**. A neutral/opposite report resets the candidate. Minimal recovers one tier at a time. The distinct entry/exit thresholds plus slower recovery prevent oscillation. These rates balance a responsive local chart with progressively less frequent chart rendering on variable links; trade and book channels are not throttled.

Connections start full, with a 15-second report grace period. At **15 seconds without a valid report**, the automatic policy immediately falls back to minimal, bypassing dwell. Overrides affect only the effective tier: the automatic state machine continues running underneath, so turning Auto back on uses its current decision. A disconnected session is discarded; reconnect starts a fresh automatic policy. An intentional app debug override is re-sent to the new connection.

The main screen shows the server-acknowledged tier and target Hz. Connection lab additionally shows **actual delivered messages per second over the last five seconds** (or the connection age during startup), RTT, jitter, and decision reason. Timers are not hard real-time; the effective rate can be lower than the target. No chart packet is invented if no candle changed.

## Lifecycle, reconnection, and debugging

Socket errors/closures mark all displayed data stale and reconnect after 1, 2, 4, 8, then 16 seconds, plus 0–250 ms jitter. The retry count resets only once history and book have synchronized. An unanswered ping or no incoming messages for over eight seconds also triggers recovery; the server closes clients with no messages for 30 seconds. Consequently, a broken link is usually detected before the missing-report tier fallback. The latter protects clients still connected but no longer reporting metrics.

The app closes sockets, cancels subscriptions/timers, and invalidates requests on background/hidden/detached transitions and on disposal. It reconnects and refreshes data on resume. Brief `inactive` transitions do not churn the connection. Caches survive within this app process, not process termination. Malformed messages are counted and ignored; the book is conservatively resynchronized when a frame cannot be trusted.

Connection lab controls:

- **Auto / Full / Degraded / Minimal**: ask the server for a connection-local override; UI changes only after its acknowledgement.
- **Go offline / Reconnect**: suspend the app's connection until manually restored; useful to observe frozen, stale values.
- **Drop socket & auto-reconnect**: server closes just this connection and the normal backoff/recovery path runs.
- **Skip a delta**: omit the next book delta for this connection and trigger gap recovery.
- **Backend address**: change hosts without recompiling.

Debug controls default off when `NODE_ENV=production`. Set `DEBUG_CONTROLS=0` when starting the backend to disable tier overrides, server disconnect/skip controls, and delayed REST responses. The server is designed for trusted local development: it has no authentication or TLS termination. Deploying it publicly requires those protections.

Bonus deep link: `tick://market/<symbol>` (for example `tick://market/BTC-USD`) opens the single trading screen on Android:

```sh
adb shell am start -a android.intent.action.VIEW -d 'tick://market/BTC-USD' dev.tickmarket.tick_market
```

## Tests and recording

```sh
./scripts/check.sh
# With the backend running and an Android device connected:
cd mobile
flutter test integration_test/market_flow_test.dart -d <android-device-id>
```

The backend suite enforces architecture boundaries and tests application sessions without networking, tier hysteresis/dwell, missing metrics, client isolation, deterministic replay, exact OHLCV across tiers including rollover, book reconstruction, and real REST/WebSocket races/errors/reconnection. The Flutter suite enforces architecture boundaries and covers repository mapping, the actual book recovery class, fixed-point validation, candle versions, latency statistics, late interval responses, lifecycle/disposal, and narrow-screen chart/diagnostics layout. The Android integration test exercises the full UI against the real Node server. The suite also covers HTTP deadlines and response limits, concurrent starts, hello deadlines, bounded recovery, configuration validation, capacity rejection, client failure isolation, and dynamic market labels at 320/360/800 logical-pixel widths. See [verification details](docs/VERIFICATION.md).

For a paced recording, add `--dart-define=RECORD_DEMO=true` to the Android integration command and record the emulator screen. `DEMO_READY` precedes the flow by 15 seconds; `DEMO_COMPLETE` marks its end. The included recording shows chart inspection, interval selection, book/trades, all three forced tiers, skipped-delta recovery, stale cached values, and manual/automatic reconnect.

## iOS approach and limits

The UI, Bloc, pure Dart state, and `dart:io` transport are portable to iOS; an iOS scaffold is included. Use your signing team, point `API_URL` at the Mac/LAN backend, add an appropriate local-network usage description and narrowly scoped development transport exception (or use HTTPS/WSS), and register the `tick` URL scheme. Verify safe areas, background/resume behavior, reconnects, and gestures on physical iOS hardware. **No iOS build or device test is claimed.**

Deliberate scope: one configured symbol per server, two intervals, 48 visible candles, no chart zoom/history pagination, no persistent disk cache, no order placement, and no watchlist reordering. The chart has a semantic description and a touch inspector; full screen-reader candle traversal remains future work. The seed is deterministic per logical tick, not per wall-clock schedule. Debug controls are intentionally visible for interview demonstrations.

The backend is an in-memory single-process service. A short 250-client local smoke check is included; horizontal scaling and production availability require a shared ordered feed, durable state as needed, and deployment testing. See [measured scope and next boundary](docs/CONFIGURATION.md#scalability-measured-scope-and-next-boundary).
