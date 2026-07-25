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
# Streams output live to the terminal while also writing to the log file.
# Uses --stats-one-line to force rclone to print progress even when not a TTY.
run_and_log() {
    local label="$1"
    shift
    echo "" >> "$LOG_FILE"
    log_msg "▶ START: $label"

    local rc=0
    # Stream output to both terminal and log file via tee
    "$@" --stats-one-line --stats 5s 2>&1 | tee -a "$LOG_FILE" || rc=${PIPESTATUS[0]}

    log_msg "⏹ END: $label (exit code: $rc)"
    return "$rc"
}

# ==============================================================================
# FUNCTIONS
# ==============================================================================

setup_sync_timer() {
    local interval="${1:-2min}"
    local script_dir
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    local headless_script="$script_dir/setup_ryclone_headless.sh"
    local service_dir="$HOME/.config/systemd/user"
    local service_file="$service_dir/rclone-sync.service"
    local timer_file="$service_dir/rclone-sync.timer"

    echo "   Setting up automatic sync every $interval..."

    # Ensure headless script exists and is executable
    if [ ! -f "$headless_script" ]; then
        echo "   ✗ Headless script not found: $headless_script"
        return 1
    fi
    chmod +x "$headless_script"

    # Create systemd user directory if needed
    mkdir -p "$service_dir"

    # Create service file
    cat > "$service_file" << EOF
[Unit]
Description=Rclone Sync Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$headless_script
WorkingDirectory=$script_dir
StandardOutput=journal
StandardError=journal
Restart=on-failure
RestartSec=30
EOF

    # Create timer file
    cat > "$timer_file" << EOF
[Unit]
Description=Run Rclone Sync Every $interval

[Timer]
OnBootSec=1min
OnUnitActiveSec=$interval
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Reload, enable, and start
    systemctl --user daemon-reload
    systemctl --user enable rclone-sync.timer 2>/dev/null || true
    systemctl --user start rclone-sync.timer

    # Verify
    if systemctl --user is-active --quiet rclone-sync.timer; then
        echo "   ✓ Timer active – sync will run every $interval"
        echo "   ✓ Service: $service_file"
        echo "   ✓ Timer:   $timer_file"
    else
        echo "   ✗ Timer failed to start. Check: systemctl --user status rclone-sync.timer"
        return 1
    fi
}

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

test_connection() {
    echo "   Testing connection to $REMOTE ..."
    echo ""

    # Test 1: Read access (list directories)
    echo -n "   [1/2] Read access ... "
    if rclone lsd "$REMOTE:" &> /dev/null; then
        echo "OK"
    else
        echo "FAILED"
        _show_connection_error
        return 1
    fi

    # Test 2: Write access (copy a test file to remote – mimics bisync behavior)
    echo -n "   [2/2] Write access ... "
    local test_dir=".rclone_test"
    local test_file="connectivity_test_$$_$(date +%s).txt"
    local test_src
    test_src=$(mktemp)
    echo "rclone connectivity test $(date)" > "$test_src"
    if rclone mkdir "$REMOTE:$test_dir" &> /dev/null && \
       rclone copyto "$test_src" "$REMOTE:$test_dir/$test_file" &> /dev/null; then
        # Verify we can read it back
        if rclone cat "$REMOTE:$test_dir/$test_file" &> /dev/null; then
            echo "OK"
        else
            echo "WARN (write OK but read-back failed)"
        fi
        # Clean up
        rclone delete "$REMOTE:$test_dir/$test_file" &> /dev/null || true
        rclone rmdir "$REMOTE:$test_dir" &> /dev/null || true
    else
        # Clean up partial test artifacts
        rclone delete "$REMOTE:$test_dir/$test_file" &> /dev/null || true
        rclone rmdir "$REMOTE:$test_dir" &> /dev/null || true
        rm -f "$test_src"
        echo "FAILED"
        echo ""
        echo "   Your remote credentials may be invalid or expired."
        echo "   The listing API worked, but file uploads are blocked."
        echo "   You may need to re-authenticate:"
        echo "     rclone config update $REMOTE"
        _show_connection_error
        return 1
    fi
    rm -f "$test_src"

    # Show quota info if available
    local about
    about=$(rclone about "$REMOTE:" 2>/dev/null || true)
    if [ -n "$about" ]; then
        echo ""
        echo "   Quota info:"
        echo "$about" | sed 's/^/     /'
    fi

    echo ""
    echo "   ✓ Connection OK (read + write verified)"
    return 0
}

_show_connection_error() {
    echo ""
    echo "   ✗ Connection test failed for remote: $REMOTE"
    echo ""
    echo "   Possible causes:"
    echo "     - Wrong credentials or expired token"
    echo "     - Network connectivity issues"
    echo "     - Remote misconfiguration"
    echo "     - Insufficient write permissions"
    echo ""
    while true; do
        read -rp "   [E]dit remote config  [R]etry connection  [Q]uit: " choice
        case "$choice" in
            [Ee])
                echo ""
                echo "   Opening rclone config editor..."
                rclone config
                echo ""
                echo "   Retesting connection..."
                test_connection
                return $?
                ;;
            [Rr])
                echo ""
                test_connection
                return $?
                ;;
            [Qq])
                echo "   Quitting."
                exit 1
                ;;
            *)
                echo "   Invalid selection."
                ;;
        esac
    done
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

echo "=== [1/6] Checking Rclone ==="
check_rclone

echo ""
echo "=== [2/6] Selecting Remote ==="
select_remote
SYNC_REMOTE="$REMOTE:$SYNC_REMOTE_PATH"
UPLOAD_REMOTE="$REMOTE:$UPLOAD_REMOTE_PATH"

echo ""
echo "=== [3/6] Testing Connection ==="
test_connection

echo ""
echo "=== [4/6] Checking Folders ==="
echo "Local:"
ensure_local "$SYNC_LOCAL"
ensure_local "$UPLOAD_LOCAL"
echo "Remote:"
ensure_remote_dir "$SYNC_REMOTE_PATH"
ensure_remote_dir "$UPLOAD_REMOTE_PATH"

echo ""
echo "=== [5/6] Executing Sync Jobs ==="
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
        job1_rc=$?
    else
        echo "   No tracking state – using --resync for initial sync"
        run_and_log "bisync $SYNC_REMOTE (resync)" rclone bisync "$SYNC_LOCAL" "$SYNC_REMOTE" $RCLONE_OPTS --resync
        job1_rc=$?
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
    job2_rc=$?
fi

# --- Report failures ---
has_failures=false
if [ "${job1_rc:-0}" -ne 0 ]; then
    echo ""
    echo "   ✗ Bisync failed (exit code: $job1_rc)"
    echo "   Common fixes:"
    echo "     - Check remote credentials / token expiry"
    echo "     - Run: rclone config update $REMOTE"
    echo "     - For bisync reset: rm ~/.cache/rclone/bisync/${safe_local}..${safe_remote}.path1.lst"
    has_failures=true
fi
if [ "${job2_rc:-0}" -ne 0 ]; then
    echo ""
    echo "   ✗ Upload job failed (exit code: $job2_rc)"
    has_failures=true
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
echo "=== [6/6] Setting Up Automatic Sync ==="
echo ""
setup_sync_timer "2min"

echo ""
if [ "$has_failures" = true ]; then
    echo "⚠️  Completed with errors. Check the messages above for details."
    exit 1
else
    echo "✅ All operations completed!"
fi