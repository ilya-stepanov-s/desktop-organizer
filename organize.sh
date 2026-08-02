#!/bin/bash
# organize.sh — раскладывает файлы с рабочего стола по папкам-датам.
#
# Ежедневная часть: всё, что появилось на рабочем столе вчера (и в пропущенные
# дни, до CATCH_UP_DAYS назад), перемещается в папку с датой появления,
# например "2026-08-01". Файлы, появившиеся сегодня, не трогаются.
#
# Месячная часть: папки-даты за прошедшие месяцы перемещаются в папку
# "ГГГГ месяц", например "2026 июль". Срабатывает 1-го числа, а если в этот
# день компьютер был выключен — при первом же следующем запуске.
#
# Запуск: ./organize.sh [--force] [--dry-run] [--daily] [--monthly]
#   --force   — игнорировать проверку времени и отметку «уже выполнялось
#               сегодня» (ручной запуск, отладка)
#   --dry-run — показать, что будет сделано, ничего не перемещая
#   --daily   — выполнить только ежедневную часть
#   --monthly — выполнить только месячную часть

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
source "$SCRIPT_DIR/config.env"

STATE_DIR="$HOME/.local/state/desktop-organizer"
STAMP_FILE="$STATE_DIR/last-run"
LOG_FILE="${LOG_FILE:-$HOME/Library/Logs/desktop-organizer.log}"

FORCE=0
DRY_RUN=0
DO_DAILY=1
DO_MONTHLY=1
for arg in "$@"; do
  case "$arg" in
    --force)   FORCE=1 ;;
    --dry-run) DRY_RUN=1; FORCE=1 ;;
    --daily)   DO_MONTHLY=0; FORCE=1 ;;
    --monthly) DO_DAILY=0; FORCE=1 ;;
    *) echo "Неизвестный аргумент: $arg" >&2; exit 2 ;;
  esac
done

mkdir -p "$STATE_DIR" "$(dirname "$LOG_FILE")"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"; }

TODAY="$(date +%Y-%m-%d)"

# Агент запускается не только по расписанию, но и при входе в систему и раз
# в час (чтобы «догнать» пропущенный из-за выключенного компьютера запуск).
# Поэтому сам скрипт решает, пора ли работать: не раньше RUN_HOUR:RUN_MINUTE
# и не чаще одного раза в день.
if [ "$FORCE" -eq 0 ]; then
  if [ -f "$STAMP_FILE" ] && [ "$(cat "$STAMP_FILE")" = "$TODAY" ]; then
    exit 0
  fi
  now_min=$((10#$(date +%H) * 60 + 10#$(date +%M)))
  run_min=$((10#$RUN_HOUR * 60 + 10#$RUN_MINUTE))
  if [ "$now_min" -lt "$run_min" ]; then
    exit 0
  fi
fi

MONTHS_RU=(январь февраль март апрель май июнь июль август сентябрь октябрь ноябрь декабрь)

is_month_folder() {
  local n="$1" m
  for m in "${MONTHS_RU[@]}"; do
    # shellcheck disable=SC2254
    case "$n" in [0-9][0-9][0-9][0-9]" $m") return 0 ;; esac
  done
  return 1
}

move_item() { # $1 = что переместить, $2 = папка назначения
  local src="$1" dest_dir="$2" name
  name="$(basename "$src")"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] $name -> $dest_dir/"
    return 0
  fi
  if ! mkdir -p "$dest_dir" 2>>"$LOG_FILE"; then
    log "ПРОПУСК: не удалось создать папку $dest_dir"
    return 1
  fi
  if [ -e "$dest_dir/$name" ]; then
    log "ПРОПУСК: $dest_dir/$name уже существует"
    return 1
  fi
  if mv "$src" "$dest_dir/" 2>>"$LOG_FILE"; then
    log "$name -> $dest_dir/"
  else
    log "ПРОПУСК: не удалось переместить $name (файл занят или нет прав)"
    return 1
  fi
}

# Дата появления файла в папке (YYYY-MM-DD). Spotlight-атрибут kMDItemDateAdded
# отражает и создание, и копирование в папку; если он недоступен — берём дату
# создания файла.
date_added() {
  local raw
  raw="$(mdls -raw -name kMDItemDateAdded "$1" 2>/dev/null)"
  if [ -n "$raw" ] && [ "$raw" != "(null)" ]; then
    date -jf "%Y-%m-%d %H:%M:%S %z" "$raw" +%Y-%m-%d 2>/dev/null && return
  fi
  stat -f %SB -t %Y-%m-%d "$1" 2>/dev/null
}

# --- Ежедневная часть: вчерашние файлы -> папки "YYYY-MM-DD" ---
if [ "$DO_DAILY" -eq 1 ]; then
  CUTOFF="$(date -v-"${CATCH_UP_DAYS}"d +%Y-%m-%d)"
  log "Раскладываю файлы, появившиеся с $CUTOFF по вчерашний день включительно"
  for item in "$DESKTOP_DIR"/*; do
    { [ -e "$item" ] || [ -L "$item" ]; } || continue
    name="$(basename "$item")"
    [ "$name" = ".DS_Store" ] && continue
    if [ -d "$item" ]; then
      case "$name" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) continue ;;
      esac
      is_month_folder "$name" && continue
    fi
    added="$(date_added "$item")"
    if [ -z "$added" ]; then
      log "ПРОПУСК: не удалось определить дату появления для $name"
      continue
    fi
    if [[ "$added" < "$TODAY" && ! "$added" < "$CUTOFF" ]]; then
      move_item "$item" "$ARCHIVE_DIR/$added"
    fi
  done
fi

# --- Месячная часть: папки-даты прошлых месяцев -> "ГГГГ месяц" ---
if [ "$DO_MONTHLY" -eq 1 ]; then
  CUR_YM="${TODAY:0:7}"
  for dir in "$ARCHIVE_DIR"/*; do
    [ -d "$dir" ] || continue
    name="$(basename "$dir")"
    case "$name" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
      *) continue ;;
    esac
    ym="${name:0:7}"
    if [[ "$ym" < "$CUR_YM" ]]; then
      year="${name:0:4}"
      month_idx=$((10#${name:5:2} - 1))
      move_item "$dir" "$ARCHIVE_DIR/$year ${MONTHS_RU[$month_idx]}"
    fi
  done
fi

if [ "$DRY_RUN" -eq 0 ] && [ "$FORCE" -eq 0 ]; then
  echo "$TODAY" > "$STAMP_FILE"
fi
log "Готово"
