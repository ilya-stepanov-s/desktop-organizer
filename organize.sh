#!/bin/bash
# organize.sh — sorts desktop files into date folders.
#
# Daily part: everything that appeared on the desktop yesterday (and on
# missed days, up to CATCH_UP_DAYS back) is moved into a folder named after
# the date it appeared, e.g. "2026-08-01". Files that appeared today are
# left untouched.
#
# Monthly part: date folders from past months are moved into a
# "YYYY <month>" folder, e.g. "2026 июль". This kicks in on the 1st of the
# month, or — if the computer was off that day — on the next run.
#
# Usage: ./organize.sh [--force] [--dry-run] [--daily] [--monthly]
#   --force   — ignore the time check and the "already ran today" stamp
#               (manual runs, debugging)
#   --dry-run — show what would be done without moving anything
#   --daily   — run only the daily part
#   --monthly — run only the monthly part

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
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

mkdir -p "$STATE_DIR" "$(dirname "$LOG_FILE")"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"; }

TODAY="$(date +%Y-%m-%d)"

# The agent fires not only on schedule but also at login and once an hour
# (to catch up on a run missed because the computer was off). So the script
# itself decides whether it is time to work: no earlier than
# RUN_HOUR:RUN_MINUTE and no more than once a day.
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

# Names for the monthly archive folders ("2026 июль").
MONTHS_RU=(январь февраль март апрель май июнь июль август сентябрь октябрь ноябрь декабрь)

is_month_folder() {
  local n="$1" m
  for m in "${MONTHS_RU[@]}"; do
    # shellcheck disable=SC2254
    case "$n" in [0-9][0-9][0-9][0-9]" $m") return 0 ;; esac
  done
  return 1
}

move_item() { # $1 = source, $2 = destination folder
  local src="$1" dest_dir="$2" name
  name="$(basename "$src")"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] $name -> $dest_dir/"
    return 0
  fi
  if ! mkdir -p "$dest_dir" 2>>"$LOG_FILE"; then
    log "SKIP: could not create folder $dest_dir"
    return 1
  fi
  if [ -e "$dest_dir/$name" ]; then
    log "SKIP: $dest_dir/$name already exists"
    return 1
  fi
  if mv "$src" "$dest_dir/" 2>>"$LOG_FILE"; then
    log "$name -> $dest_dir/"
  else
    log "SKIP: could not move $name (file busy or no permission)"
    return 1
  fi
}

# Date the file appeared in the folder (YYYY-MM-DD). The Spotlight attribute
# kMDItemDateAdded covers both creating a file and copying it into the
# folder; if it is unavailable, fall back to the file creation date.
date_added() {
  local raw
  raw="$(mdls -raw -name kMDItemDateAdded "$1" 2>/dev/null)"
  if [ -n "$raw" ] && [ "$raw" != "(null)" ]; then
    date -jf "%Y-%m-%d %H:%M:%S %z" "$raw" +%Y-%m-%d 2>/dev/null && return
  fi
  stat -f %SB -t %Y-%m-%d "$1" 2>/dev/null
}

# --- Daily part: yesterday's files -> "YYYY-MM-DD" folders ---
if [ "$DO_DAILY" -eq 1 ]; then
  CUTOFF="$(date -v-"${CATCH_UP_DAYS}"d +%Y-%m-%d)"
  log "Sorting files that appeared between $CUTOFF and yesterday inclusive"
  for item in "$DESKTOP_DIR"/*; do
    { [ -e "$item" ] || [ -L "$item" ]; } || continue
    name="$(basename "$item")"
    [ "$name" = ".DS_Store" ] && continue
    if [ -d "$item" ]; then
      # leave our own archive folders (YYYY-MM-DD and "YYYY <month>") alone
      case "$name" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) continue ;;
      esac
      is_month_folder "$name" && continue
    fi
    added="$(date_added "$item")"
    if [ -z "$added" ]; then
      log "SKIP: could not determine the date $name appeared"
      continue
    fi
    if [[ "$added" < "$TODAY" && ! "$added" < "$CUTOFF" ]]; then
      move_item "$item" "$ARCHIVE_DIR/$added"
    fi
  done
fi

# --- Monthly part: date folders from past months -> "YYYY <month>" ---
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
log "Done"
