#!/usr/bin/env bash
# ==============================================================================
# Rclone Sync Monitor – continuously shows rclone sync activity
# Place in ~/00_Sync/ and run alongside setup_ryclone.sh for live monitoring
# ==============================================================================

set -euo pipefail

REFRESH_INTERVAL=2  # seconds between refreshes

# ------------------------------------------------------------------------------
# Find the main sync script's config (same folder as this monitor)
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/setup_ryclone.sh"

# Parse remote folder names from the setup script (fallback defaults)
if [ -f "$CONFIG_FILE" ]; then
    SYNC_REMOTE_PATH=$(grep "^SYNC_REMOTE_PATH=" "$CONFIG_FILE" | head -1 | cut -d'"' -f2)
    UPLOAD_REMOTE_PATH=$(grep "^UPLOAD_REMOTE_PATH=" "$CONFIG_FILE" | head -1 | cut -d'"' -f2)
    LOG_FILE=$(grep "^LOG_FILE=" "$CONFIG_FILE" | head -1 | cut -d'"' -f2)
fi
SYNC_REMOTE_PATH="${SYNC_REMOTE_PATH:-00_Sync}"
UPLOAD_REMOTE_PATH="${UPLOAD_REMOTE_PATH:-00_Upload_Images}"
LOG_FILE="${LOG_FILE:-$HOME/00_Sync/.rclone_sync.log}"

SYNC_LOCAL_DIR="${HOME}/${SYNC_REMOTE_PATH}"
UPLOAD_LOCAL_DIR="${HOME}/${UPLOAD_REMOTE_PATH}"

# ------------------------------------------------------------------------------
# Helper: print a section header
# ------------------------------------------------------------------------------
header() {
    local label="$1"
    printf "\e[1;34m─── %s ─────────────────────────────────────────────\e[0m\n" "$label"
}

# ------------------------------------------------------------------------------
# Helper: print a labelled value
# ------------------------------------------------------------------------------
info_line() {
    local key="$1" val="$2"
    printf "  \e[1m%-22s\e[0m %s\n" "$key" "$val"
}

# ------------------------------------------------------------------------------
# Detect the first configured remote
# ------------------------------------------------------------------------------
detect_remote() {
    # Simply use the first configured remote (same approach as setup_ryclone.sh)
    rclone listremotes 2>/dev/null | head -1 | sed 's/:$//'
}

# ------------------------------------------------------------------------------
# Show last N lines from the sync log
# ------------------------------------------------------------------------------
show_recent_activity() {
    local logfile="$LOG_FILE"
    local max_lines=8

    if [ -f "$logfile" ] && [ -s "$logfile" ]; then
        echo ""
        header "Recent Activity (last sync run)"
        tail -"$max_lines" "$logfile" | sed 's/^/  /'
    fi
}

# ------------------------------------------------------------------------------
# MAIN DISPLAY LOOP
# ------------------------------------------------------------------------------
cleanup() {
    tput cnorm 2>/dev/null || true
    exit 0
}
trap cleanup SIGINT SIGTERM

tput civis 2>/dev/null || true  # hide cursor
while true; do
    clear

    printf "\e[1;36m╔══════════════════════════════════════════════════════════════╗\n"
    printf "\e[1;36m║  \e[1;37mRCLONE SYNC MONITOR\e[0m  \e[36m%-48s\e[1;36m║\n" "$(date "+%Y-%m-%d %H:%M:%S")"
    printf "\e[1;36m╚══════════════════════════════════════════════════════════════╝\e[0m\n"

    # -- Active Jobs --
    procs=$(ps aux 2>/dev/null | grep "[r]clone" || true)
    if [ -n "$procs" ]; then
        echo ""
        header "Active Jobs"
        while IFS= read -r line; do
            pid=$(echo "$line" | awk '{print $2}')
            cmd=$(echo "$line" | awk '{$1=$2=$3=$4=$5=$6=$7=$8=$9=$10=""; print substr($0,11)}' | sed 's/^ *//')
            printf "  \e[33mPID %-6s\e[0m %s\n" "$pid" "$cmd"
        done <<< "$procs"
    else
        echo ""
        header "Active Jobs"
        echo "  (none – no active rclone process)"
    fi

    # -- Local Storage --
    echo ""
    header "Local Storage"
    if [ -d "$SYNC_LOCAL_DIR" ]; then
        printf "  \e[1m%-22s\e[0m %s (%s)\n" "Sync folder" "$SYNC_LOCAL_DIR" "$(du -sh "$SYNC_LOCAL_DIR" 2>/dev/null | cut -f1)"
    fi
    if [ -d "$UPLOAD_LOCAL_DIR" ]; then
        printf "  \e[1m%-22s\e[0m %s (%s)\n" "Upload folder" "$UPLOAD_LOCAL_DIR" "$(du -sh "$UPLOAD_LOCAL_DIR" 2>/dev/null | cut -f1)"
    fi

    # -- Remote Storage --
    remote=$(detect_remote)
    if [ -n "$remote" ]; then
        echo ""
        header "Cloud Storage  ($remote)"
        rclone about "${remote}:" 2>/dev/null | while IFS= read -r line; do echo "  $line"; done

        for sub in "$SYNC_REMOTE_PATH" "$UPLOAD_REMOTE_PATH"; do
            full="${remote}:${sub}"
            count=$(rclone lsf "$full" 2>/dev/null | wc -l)
            printf "  \e[1m%-22s\e[0m %d items\n" "$full" "$count"
        done
    fi

    # -- Last lines of log --
    if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
        echo ""
        header "Recent Activity"
        tail -8 "$LOG_FILE" | sed 's/^/  /'
    fi

    echo ""
    printf "  \e[2mPress Ctrl+C to stop monitoring (refreshes every ${REFRESH_INTERVAL}s)\e[0m\n"

    sleep "$REFRESH_INTERVAL"
done
