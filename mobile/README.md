# Tick mobile

Flutter app for the Node-backed synthetic BTC-USD market, organized by feature with `domain`, `data`, and `presentation` layers. `presentation/bloc` owns typed events and immutable UI state; `BlocProvider` owns the feature lifetime. `app/di` wires constructor dependencies; `core` contains the shared theme and network transport.

See the [project README](../README.md) for setup and builds, and the [architecture guide](../docs/ARCHITECTURE.md) for the file map, dependency rules, state ownership, and tests.
