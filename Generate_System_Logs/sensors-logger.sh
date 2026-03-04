#!/usr/bin/env bash
# Rotating logger for `sensors` output.
# Writes timestamped `sensors` output every INTERVAL seconds into rotating logs.
# Configure via env vars: LOG_DIR, BASE, INTERVAL, MAX_SIZE, MAX_FILES

set -u

LOG_DIR="${LOG_DIR:-./logs}"
BASE="${BASE:-sensors.log}"
INTERVAL="${INTERVAL:-5}"
MAX_SIZE="${MAX_SIZE:-10485760}" # bytes, default 10MB
MAX_FILES="${MAX_FILES:-5}"

mkdir -p "$LOG_DIR"
current="$LOG_DIR/$BASE"

rotate() {
  local max i
  max=$((MAX_FILES))
  if (( max <= 1 )); then
    # simple truncate if only one file
    : > "$current"
    return
  fi

  for ((i=max-1;i>=1;i--)); do
    if [[ -f "$LOG_DIR/$BASE.$i" ]]; then
      mv -f "$LOG_DIR/$BASE.$i" "$LOG_DIR/$BASE.$((i+1))"
    fi
  done

  if [[ -f "$current" ]]; then
    mv -f "$current" "$LOG_DIR/$BASE.1"
  fi
}

cleanup() {
  exit 0
}

trap cleanup SIGINT SIGTERM

if ! command -v sensors >/dev/null 2>&1; then
  echo "Error: 'sensors' not found in PATH. Install lm-sensors." >&2
  exit 2
fi

echo "Starting sensors logger: interval=${INTERVAL}s, log=${current}, rotate after ${MAX_SIZE} bytes, keep ${MAX_FILES} files"

while true; do
  # ensure log file exists
  touch "$current"

  # rotate if size exceeded
  if [[ -f "$current" ]]; then
    size=$(stat -c%s "$current" 2>/dev/null || echo 0)
    if (( size >= MAX_SIZE )); then
      rotate
    fi
  fi

  printf "==== %s ====%s" "$(date -Iseconds)" "\n" >> "$current"
  sensors >> "$current" 2>&1
  printf "\n" >> "$current"

  sleep "$INTERVAL"
done
