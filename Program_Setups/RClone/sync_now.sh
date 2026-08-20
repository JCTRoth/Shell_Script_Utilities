#!/usr/bin/env bash
# ==============================================================================
# Rclone Direct Sync — run the sync immediately, no interactive setup
# ==============================================================================
# Usage:
#   ./sync.sh                     # auto-select first remote
#   ./sync.sh <remote_name>       # use specified remote
#   ./sync.sh <remote_name> --dry-run   # preview only
# ==============================================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
SYNC_LOCAL="$HOME/00_Sync"
UPLOAD_LOCAL="$HOME/00_Upload_Images"
SYNC_REMOTE_PATH="00_Sync"
UPLOAD_REMOTE_PATH="00_Upload_Images"

RCLONE_OPTS="--transfers 4 --low-level-retries 10"
DRY_RUN=false

# ── Helpers ───────────────────────────────────────────────────────────────────

info()  { printf "  \e[36m▶\e[0m %s\n" "$*"; }
ok()    { printf "  \e[32m✓\e[0m %s\n" "$*"; }
warn()  { printf "  \e[33m⚠\e[0m %s\n" "$*"; }
fail()  { printf "  \e[31m✗\e[0m %s\n" "$*"; }
header(){ printf "\n\e[1;34m─── %s ───\e[0m\n" "$*"; }

# ── Main ─────────────────────────────────────────────────────────────────────

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              RCLONE DIRECT SYNC                             ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# Parse arguments
REMOTE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        -*) 
            fail "Unknown option: $1"
            exit 1
            ;;
        *) 
            if [ -n "$REMOTE" ]; then
                fail "Multiple remotes specified: $REMOTE and $1"
                exit 1
            fi
            REMOTE="$1"
            ;;
    esac
    shift
done

# 1. Check rclone
header "Checking Rclone"
if ! command -v rclone &>/dev/null; then
    fail "rclone not found — install it first: sudo apt install rclone"
    exit 1
fi
ok "rclone found: $(rclone version 2>&1 | head -1)"

# 2. Select remote
header "Selecting Remote"
if [ -z "$REMOTE" ]; then
    REMOTE=$(rclone listremotes 2>/dev/null | head -1 | sed 's/:$//')
fi
if [ -z "$REMOTE" ]; then
    fail "No rclone remotes configured. Run: rclone config"
    exit 1
fi
ok "Remote: $REMOTE"

SYNC_REMOTE="$REMOTE:$SYNC_REMOTE_PATH"
UPLOAD_REMOTE="$REMOTE:$UPLOAD_REMOTE_PATH"

# 3. Check local folders
header "Checking Local Folders"
for dir in "$SYNC_LOCAL" "$UPLOAD_LOCAL"; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        info "Created: $dir"
    else
        ok "$dir"
    fi
done

# 4. Check remote connectivity
header "Testing Remote Connectivity"
if ! rclone lsd "$REMOTE:" &>/dev/null; then
    fail "Cannot reach remote '$REMOTE' — check credentials or network"
    exit 1
fi
ok "Connection OK"

# 5. Ensure remote directories exist
header "Ensuring Remote Directories"
for path in "$SYNC_REMOTE_PATH" "$UPLOAD_REMOTE_PATH"; do
    full="$REMOTE:$path"
    if ! rclone lsf "$full" &>/dev/null; then
        rclone mkdir "$full"
        info "Created remote: $full"
    else
        ok "Exists: $full"
    fi
done

# 6. sync
header "Job 1: Bidirectional Sync (sync)"
echo "   Local:  $SYNC_LOCAL"
echo "   Remote: $SYNC_REMOTE"
echo ""

# Build tracking file path
safe_local=$(echo "$SYNC_LOCAL" | sed 's|[/:]|_|g; s|^_||')
safe_remote=$(echo "$SYNC_REMOTE" | sed 's|[/:]|_|g')
sync_DIR="$HOME/.cache/rclone/sync"
sync_prefix="${safe_local}..${safe_remote}"
sync_track="$sync_DIR/${sync_prefix}.path1.lst"

# Ensure tracking directory exists
mkdir -p "$sync_DIR"

# Initialize job return codes
job1_rc=0
job2_rc=0

# Check for .lck lock file (running or interrupted sync)
if [ -f "$sync_DIR/${sync_prefix}.lck" ]; then
    warn "Stale sync lock file (.lck) found — removing it"
    rm -f "$sync_DIR/${sync_prefix}.lck"
fi

# Check for -err tracking files (crashed with error state)
if [ -f "${sync_track}-err" ]; then
    warn "Stale sync error state detected"
    rm -f "${sync_track}-err" \
          "$sync_DIR/${sync_prefix}.path2.lst-err"
    rm -f "$sync_track" "$sync_DIR/${sync_prefix}.path2.lst"
fi

sync_ARGS=("$SYNC_LOCAL" "$SYNC_REMOTE" $RCLONE_OPTS "--stats-one-line" "--stats" "5s")
if [ "$DRY_RUN" = true ]; then
    sync_ARGS+=("--dry-run")
fi

if [ "$DRY_RUN" = true ]; then
    info "DRY-RUN: rclone sync ${sync_ARGS[*]}"
else
    rclone sync "${sync_ARGS[@]}" 2>&1 || {
        job1_rc=$?
        fail "sync failed (exit: $job1_rc)"
    }
fi
echo ""

# 7. Upload & Delete
header "Job 2: Upload & Delete Local"
echo "   Local:  $UPLOAD_LOCAL"
echo "   Remote: $UPLOAD_REMOTE"
echo ""

if [ ! -d "$UPLOAD_LOCAL" ] || [ -z "$(ls -A "$UPLOAD_LOCAL" 2>/dev/null)" ]; then
    info "Nothing to upload — local folder is empty or does not exist"
else
    MOVE_ARGS=("$UPLOAD_LOCAL" "$UPLOAD_REMOTE" $RCLONE_OPTS "--delete-empty-src-dirs" "-P" "--stats-one-line" "--stats" "5s")
    if [ "$DRY_RUN" = true ]; then
        MOVE_ARGS+=("--dry-run")
        info "DRY-RUN: rclone move ${MOVE_ARGS[*]}"
    else
        rclone move "${MOVE_ARGS[@]}" 2>&1 || {
            job2_rc=$?
            fail "Upload failed (exit: $job2_rc)"
        }
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
# Determine job results
result1="ok"
result2="ok"
OVERALL_RC=0
if [ -n "${job1_rc+x}" ] && [ "$job1_rc" -ne 0 ]; then
    result1="failed ($job1_rc)"
    OVERALL_RC=$job1_rc
fi
if [ -n "${job2_rc+x}" ] && [ "$job2_rc" -ne 0 ]; then
    result2="failed ($job2_rc)"
    [ "$OVERALL_RC" -eq 0 ] && OVERALL_RC=$job2_rc
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                      SYNC COMPLETE                          ║"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║ Remote: %-52s ║\n" "$REMOTE"
printf "║ Job 1 (sync):  %-46s ║\n" "$result1"
printf "║ Job 2 (upload):  %-46s ║\n" "$result2"
if [ "$DRY_RUN" = true ]; then
    printf "║ %-60s ║\n" "⚠ DRY-RUN — no files were actually transferred"
fi
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

exit "$OVERALL_RC"
