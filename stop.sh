#!/usr/bin/env bash
# Остановка игрового сервера и публичного туннеля.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$DIR/tunnel.pid" ]; then
  kill "$(cat "$DIR/tunnel.pid")" 2>/dev/null || true
  rm -f "$DIR/tunnel.pid"
fi
rm -f "$DIR/logs/tunnel.url"
pkill -f "$DIR/bin/cloudflared" 2>/dev/null || true

if [ -f "$DIR/server.pid" ]; then
  kill "$(cat "$DIR/server.pid")" 2>/dev/null || true
  rm -f "$DIR/server.pid"
else
  pkill -f "$DIR/server.js" 2>/dev/null || true
fi

echo "Сервер и туннель остановлены."
