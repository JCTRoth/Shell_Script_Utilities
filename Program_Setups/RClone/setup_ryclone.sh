#!/usr/bin/env bash
# Universal Rclone Sync Manager
# Neutral naming, interactive remote selection, sync summary

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================
BASE_DIR="$HOME"

# Local folders
SYNC_LOCAL="$BASE_DIR/00_Sync"
UPLOAD_LOCAL="$BASE_DIR/00_Upload_Images"

# Remote paths (provider-agnostic)
SYNC_REMOTE_PATH="00_Sync"
UPLOAD_REMOTE_PATH="00_Upload_Images"

# Log file for the monitor script
LOG_FILE="$HOME/00_Sync/.rclone_sync.log"

# Shared rclone optimization flags (applied to all rclone commands)
# --transfers 4:          4 parallel file transfers
# --low-level-retries 10:  survive minor network drops without failing
RCLONE_OPTS="--transfers 4 --low-level-retries 10"

# Helper: log a message with timestamp
log_msg() {
    local msg="$1"
    local ts
    ts=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$ts] $msg" >> "$LOG_FILE"
}

# Helper: run a command and log its output
run_and_log() {
    local label="$1"
    shift
    echo "" >> "$LOG_FILE"
    log_msg "▶ START: $label"
    # Run the command, show output live AND capture to log.
    # rclone disables progress when stdout is a pipe, so we use a workaround:
    # write to a temp file and replay it.
    local tmp_log
    tmp_log=$(mktemp)
    "$@" > "$tmp_log" 2>&1
    local rc=$?
    if [ -s "$tmp_log" ]; then
        cat "$tmp_log"
        cat "$tmp_log" >> "$LOG_FILE"
    fi
    rm -f "$tmp_log"
    log_msg "⏹ END: $label (exit code: $rc)"
    return "$rc"
}

# ==============================================================================
# FUNCTIONS
# ==============================================================================

check_rclone() {
    if ! command -v rclone &> /dev/null; then
        echo "ERROR: rclone not found. Install it first:"
        echo "  sudo apt install rclone   # Ubuntu/Debian"
        echo "  sudo dnf install rclone   # Fedora"
        exit 1
    fi
    
    if ! rclone help 2>/dev/null | grep "bisync" > /dev/null 2>&1; then
        echo "ERROR: Your rclone version is too old (bisync missing)."
        echo "Run this to update:"
        echo "  curl https://rclone.org/install.sh | sudo bash"
        exit 1
    fi
    echo "✓ Rclone ready (bisync supported)"
}

select_remote() {
    mapfile -t remotes < <(rclone listremotes 2>/dev/null | sed 's/:$//' || true)
    
    if [ ${#remotes[@]} -eq 0 ]; then
        echo "No remotes configured. Starting rclone config..."
        rclone config
        mapfile -t remotes < <(rclone listremotes | sed 's/:$//')
    fi
    
    if [ ${#remotes[@]} -eq 1 ]; then
        REMOTE="${remotes[0]}"
        echo "✓ Auto-selected remote: $REMOTE"
    else
        echo ""
        echo "Available remotes:"
        for i in "${!remotes[@]}"; do
            printf "  [%d] %s\n" "$((i+1))" "${remotes[$i]}"
        done
        printf "  [N] Add new remote\n"
        echo ""
        while true; do
            read -rp "Select remote [1-${#remotes[@]}] or [N]: " choice
            if [[ "$choice" == [Nn] ]]; then
                rclone config
                mapfile -t remotes < <(rclone listremotes | sed 's/:$//')
                REMOTE="${remotes[-1]}"
                break
            elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#remotes[@]} ]; then
                REMOTE="${remotes[$((choice-1))]}"
                break
            fi
            echo "Invalid selection."
        done
    fi
}

ensure_local() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        echo "  Created: $dir"
    else
        local count
        count=$(find "$dir" -maxdepth 1 -type f 2>/dev/null | wc -l)
        local dcount
        dcount=$(find "$dir" -maxdepth 1 -type d 2>/dev/null | wc -l)
        dcount=$((dcount - 1))  # exclude self
        echo "  ✓ $dir  ($count files, $dcount folders)"
    fi
}

ensure_remote_dir() {
    local path="$1"
    local full="$REMOTE:$path"
    if ! rclone lsf "$full" &> /dev/null; then
        echo "  Creating remote: $full"
        rclone mkdir "$full"
    else
        echo "  ✓ Remote exists: $full"
    fi
}

count_remote_items() {
    local path="$1"
    local full="$REMOTE:$path"
    local files dirs
    files=$(rclone lsf "$full" --max-depth 1 --files-only 2>/dev/null | wc -l || echo 0)
    dirs=$(rclone lsf "$full" --max-depth 1 --dirs-only 2>/dev/null | wc -l || echo 0)
    echo "$files files, $dirs folders"
}

show_tree() {
    local path="$1"
    local full="$REMOTE:$path"
    echo ""
    echo "  📁 $full"
    local items
    items=$(rclone lsf "$full" --max-depth 1 2>/dev/null | head -15 || true)
    if [ -z "$items" ]; then
        echo "     (empty)"
    else
        echo "$items" | sed 's/^/     /'
        local total
        total=$(rclone lsf "$full" --max-depth 1 2>/dev/null | wc -l)
        if [ "$total" -gt 15 ]; then
            echo "     ... and $((total - 15)) more items"
        fi
    fi
}

# ==============================================================================
# MAIN
# ==============================================================================

clear
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           RCLONE SYNC MANAGER                               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

echo "=== [1/4] Checking Rclone ==="
check_rclone

echo ""
echo "=== [2/4] Selecting Remote ==="
select_remote
SYNC_REMOTE="$REMOTE:$SYNC_REMOTE_PATH"
UPLOAD_REMOTE="$REMOTE:$UPLOAD_REMOTE_PATH"

echo ""
echo "=== [3/4] Checking Folders ==="
echo "Local:"
ensure_local "$SYNC_LOCAL"
ensure_local "$UPLOAD_LOCAL"
echo "Remote:"
ensure_remote_dir "$SYNC_REMOTE_PATH"
ensure_remote_dir "$UPLOAD_REMOTE_PATH"

echo ""
echo "=== [4/4] Executing Sync Jobs ==="
echo ""

# Initialize log for this run
echo "" >> "$LOG_FILE"
echo "═══════════════════════════════════════════════════════════════" >> "$LOG_FILE"
log_msg "SYNC RUN STARTED (remote: $REMOTE)"

# --- Job 1: Bisync ---
echo "▶ Job 1: Bidirectional Sync"
echo "   Local:  $SYNC_LOCAL"
echo "   Remote: $SYNC_REMOTE"
echo ""
if [ -z "$(ls -A "$SYNC_LOCAL" 2>/dev/null)" ] && [ "$(rclone lsf "$SYNC_REMOTE" 2>/dev/null | wc -l)" -eq 0 ]; then
    echo "   Both sides empty. Skipping bisync."
    log_msg "SKIP: bisync (both sides empty)"
else
    # Build the bisync tracking file name (rclone convention: / → _, : → _)
    safe_local=$(echo "$SYNC_LOCAL" | sed 's|[/:]|_|g; s|^_||')
    safe_remote=$(echo "$SYNC_REMOTE" | sed 's|[/:]|_|g')
    bisync_track="$HOME/.cache/rclone/bisync/${safe_local}..${safe_remote}.path1.lst"

    if [ -f "$bisync_track" ]; then
        echo "   Tracking state exists – running normal bisync"
        run_and_log "bisync $SYNC_REMOTE" rclone bisync "$SYNC_LOCAL" "$SYNC_REMOTE" $RCLONE_OPTS
    else
        echo "   No tracking state – using --resync for initial sync"
        run_and_log "bisync $SYNC_REMOTE (resync)" rclone bisync "$SYNC_LOCAL" "$SYNC_REMOTE" $RCLONE_OPTS --resync
    fi
fi
echo ""

# --- Job 2: Upload & Delete ---
echo "▶ Job 2: Upload & Delete Local"
echo "   Local:  $UPLOAD_LOCAL"
echo "   Remote: $UPLOAD_REMOTE"
echo "   ⚠️  WARNING: Local files will be DELETED after upload!"
echo ""
if [ -z "$(ls -A "$UPLOAD_LOCAL" 2>/dev/null)" ]; then
    echo "   Local folder empty. Nothing to upload."
    log_msg "SKIP: move (local empty)"
else
    run_and_log "move to $UPLOAD_REMOTE" rclone move "$UPLOAD_LOCAL" "$UPLOAD_REMOTE" $RCLONE_OPTS --delete-empty-src-dirs -P
fi

log_msg "SYNC RUN COMPLETED"
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           SYNC CONFIGURATION SUMMARY                        ║"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║ Remote: %-52s ║\n" "$REMOTE"
echo "╠══════════════════════════════════════════════════════════════╣"

echo "║                                                              ║"
echo "║ [BISYNC] Two-way synchronization                             ║"
printf "║   Local:  %-50s ║\n" "$SYNC_LOCAL"
printf "║   Remote: %-50s ║\n" "$SYNC_REMOTE"
printf "║   Status: %-50s ║\n" "$(count_remote_items "$SYNC_REMOTE_PATH")"
echo "║                                                              ║"

echo "║ [UPLOAD] One-way upload → delete local                       ║"
printf "║   Local:  %-50s ║\n" "$UPLOAD_LOCAL"
printf "║   Remote: %-50s ║\n" "$UPLOAD_REMOTE"
printf "║   Status: %-50s ║\n" "$(count_remote_items "$UPLOAD_REMOTE_PATH")"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"

echo ""
echo "📂 Remote contents managed by this script:"
show_tree "$SYNC_REMOTE_PATH"
show_tree "$UPLOAD_REMOTE_PATH"

echo ""
echo "✅ All operations completed!"