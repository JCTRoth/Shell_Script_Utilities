#!/bin/sh

# Path to the log file on the desktop
LOG_FILE="$HOME/Desktop/ntfs_eject.log"

notify() {
    osascript -e "display notification \"$1\" with title \"NTFS Drive Eject\""
}

log() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo "$message" | tee -a "$LOG_FILE"  # Log to file and stdout
    notify "$1"
}

log "Scanning for mounted NTFS drives..."

# Get a list of mounted NTFS partitions
MOUNTED_NTFS_PARTITIONS=$(mount | grep ntfs | awk '{print $1}')

# Unmount each NTFS partition found
for PARTITION in $MOUNTED_NTFS_PARTITIONS; do
    log "Unmounting $PARTITION..."
    umount "$PARTITION"
    
    # Verify the unmount
    if mount | grep "$PARTITION" > /dev/null; then
        log "Failed to unmount $PARTITION."
    else
        log "$PARTITION unmounted successfully."
    fi
done

log "All NTFS drives have been unmounted."