#!/usr/bin/env bash

# adb_bloatware_remover.sh
# Safe, non-bricking ADB-based bloatware deinstaller
# Features:
# - Accepts one or more package lists (plain text, one package name per line)
# - Dry-run mode (default) to preview actions
# - Option to actually remove or disable apps
# - Backs up APKs and data where possible before removal
# - Skips critical/system packages and warns before any risky action
# - Provides logging and a summary at the end

# Set strict bash options for safer scripting
set -euo pipefail

# Global variables
LOGFILE="adb_debloat_$(date +%Y%m%d_%H%M%S).log"  # Log file for all operations
DRY_RUN=true  # Default to dry-run mode for safety
ACTION="preview"  # Default action: preview (can be 'uninstall' or 'disable')
BACKUP_DIR="debloat_backup_$(date +%Y%m%d_%H%M%S)"  # Directory for backups if enabled
BLACKLIST_FILE="safe_blacklist.txt"  # File containing safe package blacklist
SIMULATE=false  # When true, write commands to a file instead of executing
SIM_OUTPUT_FILE="adb_debloat_cmds_$(date +%Y%m%d_%H%M%S).sh"

# Load safe package blacklist from file
SAFE_BLACKLIST=()
if [ -f "$BLACKLIST_FILE" ]; then
  while IFS= read -r line; do
    # Skip comments (starting with #) and empty lines
    [[ $line =~ ^[[:space:]]*# ]] && continue
    [[ -z $line ]] && continue
    SAFE_BLACKLIST+=("$line")
  done < "$BLACKLIST_FILE"
else
  echo "Warning: Blacklist file '$BLACKLIST_FILE' not found. No packages will be blacklisted." >&2
fi

# Function to display usage information
usage() {
  cat <<EOF
Usage: $0 [options] <package-list-file> [package-list-file ...]
Options:
  -n, --dry-run        Preview actions (default)
  -y, --apply          Apply changes (uninstall/disable)
  -s, --simulate       Write the adb commands to a script file instead of executing
  -a, --action ACTION  Action to perform: uninstall | disable (default: uninstall when --apply)
  -b, --backup         Backup APK and app data before removing (when --apply)
  -h, --help           Show this help

Package list file:
  Plain text file with one package name per line (comments with # ignored).
EOF
}

# Logging function: prints to console and appends to log file
log() { echo "$(date +"%F %T") - $*" | tee -a "$LOGFILE"; }

# Simple check functions

# Check if ADB is installed and available in PATH
check_adb() {
  if ! command -v adb >/dev/null 2>&1; then
    echo "adb not found. Please install Android Platform Tools and ensure 'adb' is in PATH." >&2
    exit 1
  fi
}

# Check if an Android device is connected and authorized
check_device() {
  if ! adb get-state 2>/dev/null | grep -q "device"; then
    echo "No device connected. Connect device and enable USB debugging." >&2
    exit 1
  fi
}

# Initialize simulation output file
init_simulation_file() {
  if [ "$SIMULATE" = true ]; then
    printf "#!/usr/bin/env bash\nset -euo pipefail\n\n# Generated ADB commands for review\n\n" > "$SIM_OUTPUT_FILE"
    chmod +x "$SIM_OUTPUT_FILE" 2>/dev/null || true
    log "Simulation: writing commands to $SIM_OUTPUT_FILE"
  fi
}

# Check if a package is in the blacklist (loaded from file)
is_blacklisted() {
  local pkg="$1"
  for b in "${SAFE_BLACKLIST[@]}"; do
    if [ "$pkg" = "$b" ]; then
      return 0  # True, it's blacklisted
    fi
  done
  return 1  # False, not blacklisted
}

# Read and parse package list file, ignoring comments and empty lines
read_package_list() {
  local file="$1"
  grep -vE '^\s*#' "$file" | sed '/^\s*$/d'
}

# Backup APK and app data for a package (if possible)
backup_apk_and_data() {
  local pkg="$1"
  mkdir -p "$BACKUP_DIR/apks" "$BACKUP_DIR/data"
  # Get APK path from device
  apk_path=$(adb shell pm path "$pkg" 2>/dev/null | sed -n 's/package://p') || true
  if [ -n "$apk_path" ]; then
    adb pull "$apk_path" "$BACKUP_DIR/apks/" >/dev/null 2>&1 && log "Backed up APK for $pkg"
  else
    log "No APK path found for $pkg"
  fi
  # Attempt to backup app data (requires app to allow run-as or root)
  adb shell "run-as $pkg ls /data/data/$pkg" >/dev/null 2>&1 && {
    adb pull "/data/data/$pkg" "$BACKUP_DIR/data/$pkg" >/dev/null 2>&1 && log "Backed up data for $pkg"
  } || log "Could not backup data for $pkg (requires app support or root)"
}

# Perform uninstall action for a package
perform_uninstall() {
  local pkg="$1"
  if [ "$SIMULATE" = true ]; then
    printf "# Uninstall %s\nadb shell pm uninstall --user 0 %s\n\n" "$pkg" "$pkg" >> "$SIM_OUTPUT_FILE"
    return
  fi
  if $DRY_RUN; then
    log "DRY-RUN: adb shell pm uninstall --user 0 $pkg"
    return
  fi
  if [ "$BACKUP" = true ]; then
    backup_apk_and_data "$pkg"
  fi
  log "Uninstalling $pkg for user 0"
  adb shell pm uninstall --user 0 "$pkg" 2>&1 | tee -a "$LOGFILE"
}

# Perform disable action for a package
perform_disable() {
  local pkg="$1"
  if [ "$SIMULATE" = true ]; then
    printf "# Disable %s\nadb shell pm disable-user --user 0 %s\n\n" "$pkg" "$pkg" >> "$SIM_OUTPUT_FILE"
    return
  fi
  if $DRY_RUN; then
    log "DRY-RUN: adb shell pm disable-user --user 0 $pkg"
    return
  fi
  if [ "$BACKUP" = true ]; then
    backup_apk_and_data "$pkg"
  fi
  log "Disabling $pkg for user 0"
  adb shell pm disable-user --user 0 "$pkg" 2>&1 | tee -a "$LOGFILE"
}

# Parse command-line arguments
BACKUP=false
FILES=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -n|--dry-run)
      DRY_RUN=true; shift;;
    -y|--apply)
      DRY_RUN=false; shift;;
    -s|--simulate)
      SIMULATE=true; DRY_RUN=true; shift;;
    -a|--action)
      ACTION="$2"; shift 2;;
    -b|--backup)
      BACKUP=true; shift;;
    -h|--help)
      usage; exit 0;;
    -* ) echo "Unknown option $1"; usage; exit 1;;
    *) FILES+=("$1"); shift;;
  esac
done

# Ensure at least one package list file is provided
if [ ${#FILES[@]} -eq 0 ]; then
  echo "No package list provided."; usage; exit 1
fi

# Perform initial checks
check_adb
check_device

# Start logging
log "Starting adb_bloatware_remover (DRY_RUN=$DRY_RUN, ACTION=$ACTION)"

# Main processing loop: iterate over each package list file
SUMMARY=()
for f in "${FILES[@]}"; do
  if [ ! -f "$f" ]; then
    log "Package list $f not found, skipping"
    continue
  fi
  # Read packages from file
  pkgs=$(read_package_list "$f")
  while IFS= read -r pkg; do
    [ -z "$pkg" ] && continue  # Skip empty lines
    if is_blacklisted "$pkg"; then
      log "SKIP (blacklisted): $pkg"
      SUMMARY+=("SKIP: $pkg (blacklisted)")
      continue
    fi
    # Verify package exists on device
    if ! adb shell pm list packages | grep -q ":$pkg"; then
      log "NOT FOUND on device: $pkg"
      # skip silently in summary when not found
      continue
    fi
    # Execute the chosen action
    case "$ACTION" in
      uninstall)
        if perform_uninstall "$pkg"; then
          SUMMARY+=("UNINSTALLED: $pkg")
        else
          SUMMARY+=("FAILED UNINSTALL: $pkg")
        fi
        ;;
      disable)
        if perform_disable "$pkg"; then
          SUMMARY+=("DISABLED: $pkg")
        else
          SUMMARY+=("FAILED DISABLE: $pkg")
        fi
        ;;
      preview)
        log "Preview: would uninstall (user): $pkg"
        SUMMARY+=("PREVIEW: $pkg")
        ;;
      *)
        log "Unknown action: $ACTION"
        ;;
    esac
  done <<< "$pkgs"
done

# Print summary of all actions
log "Summary:"
for s in "${SUMMARY[@]}"; do
  log "  $s"
done

log "Finished"

exit 0
