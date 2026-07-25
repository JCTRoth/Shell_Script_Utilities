#!/usr/bin/env bash
# ==============================================================================
# Non-interactive wrapper for Setup_rsync.sh (used by cron / launchd)
# - Skips interactive prompts (auto-selects first remote)
# - Suppresses clear/ANSI codes
# - Logs to journal + log file
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$HOME/00_Sync/.rclone_sync.log"

# Redirect all output to log file
exec > >(tee -a "$LOG_FILE") 2>&1

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  RCLONE SYNC (automatic – cron / launchd)"
echo "  $(date "+%Y-%m-%d %H:%M:%S")"
echo "═══════════════════════════════════════════════════════════════"

# 1. Check rclone
if ! command -v rclone &> /dev/null; then
    echo "ERROR: rclone not found."
    exit 1
fi
echo "✓ Rclone found: $(rclone version 2>&1 | head -1)"

# 2. Auto-select first remote (no prompt)
REMOTE=$(rclone listremotes 2>/dev/null | head -1 | sed 's/:$//')
if [ -z "$REMOTE" ]; then
    echo "ERROR: No remotes configured."
    exit 1
fi
# Shared rclone optimization flags
# --transfers 4:         parallel file transfers
# --low-level-retries 10: survive minor network drops
# --rc / --rc-enable-metrics: optional remote control for monitoring
RCLONE_OPTS="--transfers 4 --low-level-retries 10"

echo "✓ Remote: $REMOTE"

# 3. Paths
SYNC_LOCAL="$HOME/00_Sync"
UPLOAD_LOCAL="$HOME/00_Upload_Images"
SYNC_REMOTE_PATH="00_Sync"
UPLOAD_REMOTE_PATH="00_Upload_Images"
SYNC_REMOTE="$REMOTE:$SYNC_REMOTE_PATH"
UPLOAD_REMOTE="$REMOTE:$UPLOAD_REMOTE_PATH"

# 4. Check local folders
for dir in "$SYNC_LOCAL" "$UPLOAD_LOCAL"; do
    if [ ! -d "$dir" ]; then
        echo "  Creating: $dir"
        mkdir -p "$dir"
    fi
done

# 5. Check remote folders
for path in "$SYNC_REMOTE_PATH" "$UPLOAD_REMOTE_PATH"; do
    full="$REMOTE:$path"
    if ! rclone lsf "$full" &> /dev/null; then
        echo "  Creating remote: $full"
        rclone mkdir "$full"
    fi
done

# 6. Bisync (with or without --resync)
echo ""
echo "▶ Job 1: Bisync  $SYNC_LOCAL  ↔  $SYNC_REMOTE"
safe_local=$(echo "$SYNC_LOCAL" | sed 's|[/:]|_|g; s|^_||')
safe_remote=$(echo "$SYNC_REMOTE" | sed 's|[/:]|_|g')
bisync_track="$HOME/.cache/rclone/bisync/${safe_local}..${safe_remote}.path1.lst"

if [ -f "$bisync_track" ]; then
    echo "   Tracking exists – normal bisync"
    rclone bisync "$SYNC_LOCAL" "$SYNC_REMOTE" $RCLONE_OPTS
else
    echo "   No tracking – initial sync with --resync"
    rclone bisync "$SYNC_LOCAL" "$SYNC_REMOTE" $RCLONE_OPTS --resync
fi

# 7. Move/Upload
echo ""
echo "▶ Job 2: Move  $UPLOAD_LOCAL  →  $UPLOAD_REMOTE"
if [ -z "$(ls -A "$UPLOAD_LOCAL" 2>/dev/null)" ]; then
    echo "   Local folder empty – nothing to upload"
else
    rclone move "$UPLOAD_LOCAL" "$UPLOAD_REMOTE" $RCLONE_OPTS --delete-empty-src-dirs -P
fi

echo ""
echo "✅ Sync completed at $(date "+%Y-%m-%d %H:%M:%S")"
