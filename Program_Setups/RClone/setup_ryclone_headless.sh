#!/usr/bin/env bash
# ==============================================================================
# Non-interactive wrapper for setup_ryclone.sh (used by cron / launchd)
# - Skips interactive prompts (auto-selects first remote)
# - Suppresses clear/ANSI codes
# - Logs to journal + log file
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$HOME/00_Sync/.rclone_sync.log"

# Collect output in memory – only write to log file on failure
OUTPUT=""
log() { OUTPUT+="$*\n"; }

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

log ""
log "═══════════════════════════════════════════════════════════════"
log "  RCLONE SYNC (automatic – cron / launchd)"
log "  $(timestamp)"
log "═══════════════════════════════════════════════════════════════"

OVERALL_RC=0

# 1. Check rclone
if ! command -v rclone &> /dev/null; then
    log "ERROR: rclone not found."
    OVERALL_RC=1
    exit 1
fi
log "✓ Rclone found: $(rclone version 2>&1 | head -1)"

# 2. Auto-select first remote (no prompt)
REMOTE=$(rclone listremotes 2>/dev/null | head -1 | sed 's/:$//')
if [ -z "$REMOTE" ]; then
    log "ERROR: No remotes configured."
    exit 1
fi
RCLONE_OPTS="--transfers 4 --low-level-retries 10"

log "✓ Remote: $REMOTE"

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
        log "  Creating: $dir"
        mkdir -p "$dir"
    fi
done

# 5. Connection test
if ! rclone lsd "$REMOTE:" &> /dev/null; then
    log "✗ Read access FAILED – remote unreachable"
    exit 1
fi

# 6. Check remote folders
for path in "$SYNC_REMOTE_PATH" "$UPLOAD_REMOTE_PATH"; do
    full="$REMOTE:$path"
    if ! rclone lsf "$full" &> /dev/null; then
        rclone mkdir "$full"
    fi
done

# 7. Auto-resolve bisync locks: clean stale tracking state
BISYNC_DIR="$HOME/.cache/rclone/bisync"
safe_local=$(echo "$SYNC_LOCAL" | sed 's|[/:]|_|g; s|^_||')
safe_remote=$(echo "$SYNC_REMOTE" | sed 's|[/:]|_|g')
bisync_prefix="${safe_local}..${safe_remote}"
bisync_track="$BISYNC_DIR/${bisync_prefix}.path1.lst"

# If previous sync crashed, clean error tracking files and force --resync
needs_resync=false
if [ -f "${bisync_track}-err" ]; then
    log "  Cleaning stale bisync error state – will use --resync"
    rm -f "$BISYNC_DIR/${bisync_prefix}.path1.lst-err" \
          "$BISYNC_DIR/${bisync_prefix}.path2.lst-err"
    # Also remove old tracking so --resync is triggered
    rm -f "$bisync_track" "$BISYNC_DIR/${bisync_prefix}.path2.lst"
    needs_resync=true
fi

# 8. Bisync
job1_rc=0
if [ -f "$bisync_track" ] && [ "$needs_resync" = false ]; then
    rclone bisync "$SYNC_LOCAL" "$SYNC_REMOTE" $RCLONE_OPTS --stats-one-line --stats 5s 2>&1 || job1_rc=$?
else
    rclone bisync "$SYNC_LOCAL" "$SYNC_REMOTE" $RCLONE_OPTS --resync --stats-one-line --stats 5s 2>&1 || job1_rc=$?
fi

# 9. Move/Upload
job2_rc=0
UPLOAD_FILES=$(ls -A "$UPLOAD_LOCAL" 2>/dev/null || true)
if [ -z "$UPLOAD_FILES" ]; then
    : # nothing to upload – silent
else
    rclone move "$UPLOAD_LOCAL" "$UPLOAD_REMOTE" $RCLONE_OPTS --delete-empty-src-dirs -P --stats-one-line --stats 5s 2>&1 || job2_rc=$?
fi

# 10. Write log file only on failure
if [ "$job1_rc" -ne 0 ] || [ "$job2_rc" -ne 0 ]; then
    log "⚠️  Errors: bisync=$job1_rc  move=$job2_rc"
    OVERALL_RC=1
fi

if [ "$OVERALL_RC" -ne 0 ]; then
    # Append collected output to log file
    echo -e "$OUTPUT" >> "$LOG_FILE"
fi

exit "$OVERALL_RC"

# 9. Summary
echo ""
if [ "$job1_rc" -ne 0 ] || [ "$job2_rc" -ne 0 ]; then
    echo "⚠️  Sync completed with errors (bisync: $job1_rc, move: $job2_rc)" | tee -a "$LOG_FILE"
else
    echo "✅ Sync completed at $(date "+%Y-%m-%d %H:%M:%S")" | tee -a "$LOG_FILE"
fi
