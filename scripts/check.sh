#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."
npm --prefix backend ci --no-audit --no-fund
npm --prefix backend test
cd mobile
flutter pub get
flutter analyze
flutter test --reporter expanded
