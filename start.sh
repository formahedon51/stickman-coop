#!/usr/bin/env bash
# Запуск игрового сервера STICKMAN CO-OP.
#   TUNNEL=1 (по умолчанию) — поднять публичный cloudflared-туннель.
#   TUNNEL=0                 — только локальная сеть.
#   NO_BROWSER=1             — не открывать браузер.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
PORT="${PORT:-9000}"
TUNNEL="${TUNNEL:-1}"
URL="http://127.0.0.1:${PORT}/"
HEALTH="http://127.0.0.1:${PORT}/healthz"
PUBLIC_URL=""
PUBLIC_OK=0

if [ ! -d node_modules ]; then
  echo "Первый запуск: устанавливаю зависимости…"
  npm install --no-audit --no-fund
fi

# ---------- локальный сервер ----------
if curl -fsS "$HEALTH" >/dev/null 2>&1; then
  echo "Сервер уже запущен: $URL"
else
  mkdir -p "$DIR/logs"
  setsid nohup node "$DIR/server.js" >>"$DIR/logs/server.log" 2>&1 &
  echo $! >"$DIR/server.pid"

  ok=0
  for _ in $(seq 1 80); do
    if curl -fsS "$HEALTH" >/dev/null 2>&1; then ok=1; break; fi
    sleep 0.1
  done
  if [ "$ok" != "1" ]; then
    echo "Не удалось запустить сервер. Посмотрите $DIR/logs/server.log"
    exit 1
  fi
  echo "Сервер запущен: $URL"
fi

# ---------- публичный туннель ----------
tunnel_alive() {
  [ -f "$DIR/tunnel.pid" ] || return 1
  local pid
  pid="$(cat "$DIR/tunnel.pid" 2>/dev/null || true)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

if [ "$TUNNEL" = "1" ]; then
  if [ ! -x "$DIR/bin/cloudflared" ]; then
    echo "cloudflared не найден — запускаю установку…"
    "$DIR/install.sh" || true
  fi

  if [ -x "$DIR/bin/cloudflared" ]; then
    # Уже есть живой туннель? Проверим, что он реально отвечает.
    if tunnel_alive && [ -s "$DIR/logs/tunnel.url" ]; then
      PUBLIC_URL="$(cat "$DIR/logs/tunnel.url")"
      if curl -fsS --max-time 5 "$PUBLIC_URL/healthz" >/dev/null 2>&1; then
        PUBLIC_OK=1
      else
        PUBLIC_URL=""
        kill "$(cat "$DIR/tunnel.pid")" 2>/dev/null || true
        rm -f "$DIR/tunnel.pid" "$DIR/logs/tunnel.url"
      fi
    fi

    if [ -z "$PUBLIC_URL" ]; then
      : >"$DIR/logs/tunnel.log"
      setsid nohup "$DIR/bin/cloudflared" tunnel \
        --url "http://127.0.0.1:${PORT}" \
        --no-autoupdate \
        --protocol http2 >>"$DIR/logs/tunnel.log" 2>&1 &
      echo $! >"$DIR/tunnel.pid"

      # Ждём появления публичного адреса в логе.
      for _ in $(seq 1 160); do
        PUBLIC_URL="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$DIR/logs/tunnel.log" 2>/dev/null | head -1 || true)"
        [ -n "$PUBLIC_URL" ] && break
        sleep 0.25
      done

      if [ -n "$PUBLIC_URL" ]; then
        echo "Туннель создан: $PUBLIC_URL"
        echo "Жду, пока он станет доступен из интернета…"
        for _ in $(seq 1 120); do
          if curl -fsS --max-time 5 "$PUBLIC_URL/healthz" >/dev/null 2>&1; then
            PUBLIC_OK=1
            break
          fi
          sleep 0.5
        done
        echo "$PUBLIC_URL" >"$DIR/logs/tunnel.url"
      else
        echo "Не удалось получить публичную ссылку. Смотрите $DIR/logs/tunnel.log"
      fi
    fi
  fi
fi

# ---------- публикуем адрес signaling для GitHub Pages ----------
if [ -n "$PUBLIC_URL" ] && [ "$PUBLIC_OK" = "1" ] && [ -d "$DIR/.git" ]; then
  python3 - "$PUBLIC_URL" "$DIR/public/servers.json" <<'PY'
import json, sys, urllib.parse, time
url, out = sys.argv[1], sys.argv[2]
u = urllib.parse.urlparse(url)
signals = [{"host": u.hostname, "port": 443, "path": "/peerjs", "secure": True}]
old = {}
try:
    old = json.load(open(out, encoding="utf-8"))
except Exception:
    pass
updated = old.get("updated", int(time.time())) if old.get("signals") == signals else int(time.time())
data = {"signals": signals, "updated": updated}
open(out, "w", encoding="utf-8").write(json.dumps(data, ensure_ascii=False, indent=2))
PY
  if git -C "$DIR" add public/servers.json 2>/dev/null; then
    if ! git -C "$DIR" diff --cached --quiet 2>/dev/null; then
      git -C "$DIR" commit -q -m "Update public signaling URL" 2>/dev/null || true
      git -C "$DIR" push -q origin main 2>/dev/null || true
    fi
  fi
fi

# ---------- что открыть ----------
if [ -n "$PUBLIC_URL" ]; then
  if [ "$PUBLIC_OK" = "1" ]; then
    echo "Публичная ссылка: $PUBLIC_URL/"
    OPEN_URL="$PUBLIC_URL/"
  else
    echo "Публичная ссылка (пока недоступна): $PUBLIC_URL/"
    echo "Открываю локально. Обновите страницу через минуту или проверьте $DIR/logs/tunnel.log"
    OPEN_URL="$URL"
  fi
else
  OPEN_URL="$URL"
  [ "$TUNNEL" = "1" ] && echo "Публичный туннель не поднялся — открываю локально."
fi

if [ "${NO_BROWSER:-0}" != "1" ]; then
  xdg-open "$OPEN_URL" >/dev/null 2>&1 || true
fi
