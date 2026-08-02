#!/bin/bash
# install.sh — устанавливает (или обновляет) launchd-агент.
# Запускайте заново после изменения времени в config.env.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
source "$SCRIPT_DIR/config.env"

PLIST="$HOME/Library/LaunchAgents/$LAUNCHD_LABEL.plist"
LOG_FILE="$HOME/Library/Logs/desktop-organizer.log"

mkdir -p "$HOME/Library/LaunchAgents"

sed -e "s|__LABEL__|$LAUNCHD_LABEL|g" \
    -e "s|__SCRIPT__|$SCRIPT_DIR/organize.sh|g" \
    -e "s|__HOUR__|$RUN_HOUR|g" \
    -e "s|__MINUTE__|$RUN_MINUTE|g" \
    -e "s|__LOG__|$LOG_FILE|g" \
    "$SCRIPT_DIR/com.desktop-organizer.plist.template" > "$PLIST"

chmod +x "$SCRIPT_DIR/organize.sh"

launchctl bootout "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

printf 'Готово: агент %s установлен, запуск ежедневно в %02d:%02d.\n' \
  "$LAUNCHD_LABEL" "$((10#$RUN_HOUR))" "$((10#$RUN_MINUTE))"
echo "Лог: $LOG_FILE"
