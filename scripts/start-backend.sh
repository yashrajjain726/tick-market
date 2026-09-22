#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/../backend"
npm ci --no-audit --no-fund
exec npm start
