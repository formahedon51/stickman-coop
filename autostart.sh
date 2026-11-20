#!/usr/bin/env bash
# Автозапуск при входе в систему: сервер + туннель, без открытия браузера.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NO_BROWSER=1 "$DIR/start.sh"
