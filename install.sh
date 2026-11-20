#!/usr/bin/env bash
# Установка: зависимости, cloudflared, автозапуск сервера.
# Иконки на рабочий стол НЕ создаются.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

chmod +x start.sh stop.sh autostart.sh

if [ ! -d node_modules ]; then
  echo "Устанавливаю зависимости…"
  npm install --no-audit --no-fund
fi

# cloudflared — бесплатный публичный туннель без аккаунта
mkdir -p "$DIR/bin"
if [ ! -x "$DIR/bin/cloudflared" ]; then
  echo "Скачиваю cloudflared (один раз)…"
  case "$(uname -m)" in
    x86_64|amd64) CF=cloudflared-linux-amd64 ;;
    aarch64|arm64) CF=cloudflared-linux-arm64 ;;
    *) CF=cloudflared-linux-amd64 ;;
  esac
  curl -fL --retry 3 --max-time 180 -o "$DIR/bin/cloudflared" \
    "https://github.com/cloudflare/cloudflared/releases/latest/download/$CF"
  chmod +x "$DIR/bin/cloudflared"
fi

ICON_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"
APPS="$HOME/.local/share/applications"
AUTOSTART="$HOME/.config/autostart"
DESKTOP="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
[ -n "$DESKTOP" ] || DESKTOP="$HOME/Desktop"
mkdir -p "$ICON_DIR" "$APPS" "$AUTOSTART"
cp public/icon.svg "$ICON_DIR/stickman-coop.svg"

write_desktop() {
  local file="$1" name="$2" exec_path="$3" comment="$4"
  cat >"$file" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=$name
Comment=$comment
Exec="$exec_path"
Icon=$ICON_DIR/stickman-coop.svg
Terminal=false
Categories=Game;
StartupNotify=false
EOF
  chmod +x "$file"
}

# Только меню приложений (не рабочий стол) — для ручного открытия/остановки.
write_desktop "$APPS/stickman-coop.desktop" "STICKMAN CO-OP" "$DIR/start.sh" "Открыть игру (сервер запущен)"
write_desktop "$APPS/stickman-coop-stop.desktop" "STICKMAN CO-OP — стоп" "$DIR/stop.sh" "Остановить игровой сервер"

# Автозапуск при входе в систему: сервер + публичный туннель.
cat >"$AUTOSTART/stickman-coop.desktop" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=STICKMAN CO-OP server
Comment=Автозапуск игрового сервера
Exec="$DIR/autostart.sh"
Icon=$ICON_DIR/stickman-coop.svg
Terminal=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
chmod +x "$AUTOSTART/stickman-coop.desktop"

# Убираем ранее созданные иконки с рабочего стола.
rm -f "$DESKTOP/STICKMAN CO-OP.desktop" "$DESKTOP/STICKMAN CO-OP — стоп.desktop"

update-desktop-database "$APPS" 2>/dev/null || true
gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

echo ""
echo "Готово!"
echo "  Автозапуск:    $AUTOSTART/stickman-coop.desktop"
echo "  Сервер стартует автоматически при входе в систему."
echo "  Открыть игру:  http://localhost:${PORT:-9000}/  (или меню приложений » STICKMAN CO-OP)"
echo "  Остановить:    ./stop.sh  (или меню приложений » STICKMAN CO-OP — стоп)"
echo "  Иконки с рабочего стола удалены."
