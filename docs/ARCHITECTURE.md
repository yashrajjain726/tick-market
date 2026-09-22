# Feature-first clean architecture

The market is the application's single business feature. Its domain rules, data access, and user interface live together under `features/market`, with dependencies pointing toward the domain. New features get sibling folders instead of expanding global `controllers`, `models`, or `services` directories.

## Flutter

```text
mobile/lib/
├── main.dart                             Bootstrap and system appearance
├── app/
│   ├── tick_app.dart                     MaterialApp and lifecycle adapter
│   ├── config/app_config.dart           Validated build settings and injected policies
│   └── di/dependencies.dart              Composition root
├── core/
│   ├── network/network_policy.dart      HTTP limits and timeouts
│   ├── network/json_transport.dart       Generic dart:io HTTP/WebSocket transport
│   └── theme/app_theme.dart              Shared colors, theme, text styles
└── features/market/
    ├── domain/
    │   ├── configuration/market_policy.dart  Session timing and resource bounds
    │   ├── entities/
    │   │   ├── market_entities.dart       Fixed-point values and snapshot types
    │   │   └── market_event.dart          Typed connection events
    │   ├── repositories/
    │   │   └── market_repository.dart     Repository and connection interfaces
    │   ├── services/
    │   │   ├── book_sync.dart             Ordered replay and atomic book recovery
    │   │   ├── candle_store.dart          Version-aware candle merge
    │   │   └── latency.dart               RTT/jitter calculation
    │   └── use_cases/
    │       └── market_session.dart        Stateful session orchestration
    ├── data/
    │   ├── datasources/
    │   │   └── market_remote_data_source.dart  Endpoint paths and transport calls
    │   ├── models/
    │   │   └── market_dto.dart            Wire validation and entity/event mapping
    │   └── repositories/
    │       └── remote_market_repository.dart  Domain port implementation
    └── presentation/
        ├── market_view_policy.dart        Visible-item and UI update budgets
        ├── bloc/market_bloc.dart          Events, domain commands, coalesced snapshots
        ├── bloc/market_event.dart         Typed UI/lifecycle events
        ├── bloc/market_state.dart         Immutable Equatable view state
        ├── pages/market_screen.dart       Market screen composition
        ├── formatters/market_formatters.dart   Price, quantity, time formatting
        └── widgets/
            ├── candle_chart.dart         fl_chart adapter and local touch inspector
            ├── connection_status.dart    Live/syncing/stale status
            ├── diagnostics_sheet.dart    Connection lab controls
            ├── market_stat.dart          Compact statistic
            └── order_book.dart           Bid/ask depth rows
```

### Dependency rule

```text
presentation ──> domain <── data ──> core/network
       │
       └──> core/theme

app/di composes the concrete objects
```

- **Domain** imports only pure Dart and its own domain files. It does not import Flutter, `dart:io`, JSON codecs, data classes, or widgets. Entities contain market values, not wire deserializers.
- **Data** knows the domain interfaces and generic transport. `MarketDto` rejects invalid wire values before they enter the use case. Invalid socket frames become typed `InvalidMarketMessage` events; REST failures remain errors handled by the use case's retry policy.
- **Presentation** knows the session use case and domain values. It cannot construct or import the data adapter. Display formatting and chart pointer state stay here.
- **Core** is feature independent. Price formatting remains within the market feature because it depends on the market's fixed-point units.
- **App** is the composition root: `IoJsonTransport → MarketRemoteDataSource → RemoteMarketRepository → MarketSession → MarketBloc`. Constructor injection makes each seam replaceable without a service locator or global singleton.

### State and lifecycle ownership

`MarketSession` is a long-lived use case because order-book replay, interval revisions, history requests, heartbeats, and reconnects share one connection generation. Splitting each action into a one-method class would scatter this shared lifetime. The stateless algorithms remain separate domain services.

The session exposes a change stream. `MarketBloc` captures immutable value snapshots for the presentation layer; widgets never receive the session, `BookSync`, `CandleStore`, or `LatencyWindow`. Lists are copied and unmodifiable; Equatable suppresses equal snapshots. State contains connection/sync/loading/error flags alongside cached values so a stale transition does not discard the visible chart.

UI actions dispatch `MarketStarted`, `IntervalSelected`, `TierOverrideRequested`, `OfflineChanged`, `ServerChanged`, `BookGapRequested`, or `SocketDropRequested`. The app dispatches `LifecyclePausedChanged` for background/resume. A single sequential event registration preserves ordering across event types. Starting asynchronous I/O does not block this queue: domain generation guards still invalidate late completions. Invalid backend addresses become Bloc state errors, and tier controls remain server-acknowledged.

Session notifications are batched at 100 ms before producing a snapshot; actions update state immediately. `BlocBuilder` consumes the emitted state in the screen and diagnostics sheet. `BlocProvider` creates and closes the feature Bloc, while the modal reuses it through `BlocProvider.value`. Closing cancels the batching timer/subscription and disposes the domain session, transport and timers. Queued events and late I/O cannot publish after close. Chart selection and the address text controller remain local transient widget state.

The domain still uses Dart timers, a monotonic stopwatch, and retry jitter; framework independence does not mean every standard-library primitive needs another interface. Typed repository ports isolate the external I/O.

## Node.js

```text
backend/src/
├── main.mjs                              Environment, startup, signal handling
├── app/
│   ├── config.mjs                        Zod JSON/environment schemas
│   └── create_market_server.mjs           Dependency wiring, clocks, feed timer
└── features/market/
    ├── domain/
    │   ├── market_definition.mjs         Market descriptor and simulator constants
    │   ├── delivery_config.mjs           Tier defaults and consistency rules
    │   ├── market.mjs                    Deterministic trades, OHLCV, book
    │   ├── delivery_policy.mjs           Per-client hysteresis and tier choice
    │   └── chart_delivery.mjs            Complete candle buffering and cadence
    ├── application/
    │   ├── market_service.mjs            Queries, connection registry, feed step
    │   └── client_session.mjs            Subscription, commands, per-client output
    └── infrastructure/
        ├── http/market_http_handler.mjs  REST routing and response serialization
        └── websocket/market_websocket_gateway.mjs
                                          JSON, rate/payload limits, backpressure
```

```text
HTTP / WebSocket adapters ──> application ──> domain
app/create_market_server wires them and injects clocks
```

The domain has no Node framework, filesystem, socket, timer, or wall-clock dependency. `Market` receives its seed and logical time origin. `DeliveryPolicy` and `ChartDelivery` receive explicit times.

The application exposes market queries and handles semantic connection commands. A `ClientSession` receives a small channel port: `send(event) → boolean` and `close(code, reason)`. Its WebSocket implementation lives in infrastructure; tests provide an in-memory implementation. No interface-only JavaScript class is necessary for this structural contract.

The WebSocket gateway parses JSON, applies frame/rate/backpressure limits, and delegates commands to the session. The HTTP adapter maps URLs and status codes to service queries. The composition root creates the HTTP server, injects monotonic and wall clocks, and schedules one market step every 100 ms. Disconnection removes the client session; closing the server stops the timer and terminates sockets.

The wire protocol remains documented separately in [PROTOCOL.md](PROTOCOL.md).

## Tests and extension points

Tests mirror the production feature layers:

| Location | What it protects |
| --- | --- |
| `mobile/test/architecture_test.dart` | Inward dependencies and feature-independent core |
| `mobile/test/features/market/domain/` | Book replay, recovery, candle versions, RTT/jitter |
| `mobile/test/features/market/data/` | Wire validation, REST mapping, typed events and commands |
| `mobile/test/features/market/presentation/` | Bloc events/snapshots, session races, lifecycle, narrow-screen widgets |
| `mobile/integration_test/` | Android UI against a real Node server |
| `backend/test/architecture.test.mjs` | Domain/application import direction and infrastructure globals |
| `backend/test/features/market/domain/` | Determinism, exact OHLCV, hysteresis, book reconstruction |
| `backend/test/features/market/application/` | Independent sessions, disconnect lifetime, debug restrictions |
| `backend/test/features/market/integration/` | Real REST and simultaneous WebSocket clients |

For a future watchlist, add `features/watchlist` with its own domain/data/presentation layers and wire it in `app/di`. For a second market-data provider, implement the existing `MarketRepository` and select it in the composition root. A new backend transport implements the channel port and calls `MarketService`; the feed and delivery policy remain reusable.

Keep shared code in `core` only when it is feature independent. Do not import another feature's data or presentation internals. If features later share market identifiers or prices, promote a deliberate common value contract rather than moving the whole market feature into a generic utilities folder.

## Design assessment

Feature-first clean architecture is a suitable baseline for this scope: the domain is independently testable, adapters can change without rewriting synchronization, and new features have an explicit home. It is not a universal best architecture or a substitute for operational engineering. The stateful session is intentional because connection generations coordinate multiple asynchronous streams. Avoid adding wrappers, a service locator, or distributed infrastructure without a concrete need.

Runtime settings, market metadata, typed failures, bounded I/O, coalesced recovery, and capacity limits are described in [Configuration and operating limits](CONFIGURATION.md). That document also distinguishes codebase extensibility from horizontal server scalability.
