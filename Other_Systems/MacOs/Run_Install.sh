#!/bin/bash

# Define variables
OPT_DIR="/opt/ntfsdrives"
EJECT_SCRIPT_NAME="Eject_All_Ntfs_Drives.sh"
EJECT_SCRIPT_PATH="$OPT_DIR/$EJECT_SCRIPT_NAME"
MOUNT_SCRIPT_NAME="Mount_All_Ntfs_Drives.sh"
MOUNT_SCRIPT_PATH="$OPT_DIR/$MOUNT_SCRIPT_NAME"
EJECT_PLIST_NAME="info.mailbase.ejectntfsdrives.plist"
EJECT_PLIST_PATH="/Library/LaunchDaemons/$EJECT_PLIST_NAME"
MOUNT_PLIST_NAME="info.mailbase.mountntfsdrives.plist"
MOUNT_PLIST_PATH="/Library/LaunchDaemons/$MOUNT_PLIST_NAME"

# Function to log messages to the terminal
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Check if the script is being run as root
if [[ $EUID -ne 0 ]]; then
    log "This script must be run as root. Exiting."
    exit 1
fi

log "Starting setup for NTFS drives scripts"

# Create the /opt/ntfsdrives directory
log "Creating directory $OPT_DIR"
mkdir -p "$OPT_DIR"
if [ $? -eq 0 ]; then
    log "Directory $OPT_DIR created successfully"
else
    log "Failed to create directory $OPT_DIR"
    exit 1
fi

# Check if the Eject_All_Ntfs_Drives.sh script exists and copy it to /opt/ntfsdrives
if [ -f "./$EJECT_SCRIPT_NAME" ]; then
    log "Found $EJECT_SCRIPT_NAME, copying to $EJECT_SCRIPT_PATH"
    cp "./$EJECT_SCRIPT_NAME" "$EJECT_SCRIPT_PATH"
    if [ $? -eq 0 ]; then
        log "$EJECT_SCRIPT_NAME copied successfully"
    else
        log "Failed to copy $EJECT_SCRIPT_NAME"
        exit 1
    fi
else
    log "Error: $EJECT_SCRIPT_NAME does not exist in the current directory"
    exit 1
fi

# Check if the Mount_All_Ntfs_Drives.sh script exists and copy it to /opt/ntfsdrives
if [ -f "./$MOUNT_SCRIPT_NAME" ]; then
    log "Found $MOUNT_SCRIPT_NAME, copying to $MOUNT_SCRIPT_PATH"
    cp "./$MOUNT_SCRIPT_NAME" "$MOUNT_SCRIPT_PATH"
    if [ $? -eq 0 ]; then
        log "$MOUNT_SCRIPT_NAME copied successfully"
    else
        log "Failed to copy $MOUNT_SCRIPT_NAME"
        exit 1
    fi
else
    log "Error: $MOUNT_SCRIPT_NAME does not exist in the current directory"
    exit 1
fi

# Make the scripts executable
log "Making $EJECT_SCRIPT_PATH and $MOUNT_SCRIPT_PATH executable"
chmod +x "$EJECT_SCRIPT_PATH" "$MOUNT_SCRIPT_PATH"
if [ $? -eq 0 ]; then
    log "Scripts are now executable"
else
    log "Failed to make the scripts executable"
    exit 1
fi

# Create the plist file for the eject script launch daemon
log "Creating plist file $EJECT_PLIST_PATH"
bash -c "cat << EOF > $EJECT_PLIST_PATH
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC '-//Apple//DTD PLIST 1.0//EN' 'http://www.apple.com/DTDs/PropertyList-1.0.dtd'>
<plist version=\"1.0\">
<dict>
    <key>Label</key>
    <string>info.mailbase.ejectntfsdrives</string>
    <key>ProgramArguments</key>
    <array>
        <string>$EJECT_SCRIPT_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>WatchPaths</key>
    <array>
        <string>/var/run/system-shutdown</string>
    </array>
</dict>
</plist>
EOF"
if [ $? -eq 0 ]; then
    log "Plist file $EJECT_PLIST_PATH created successfully"
else
    log "Failed to create plist file $EJECT_PLIST_PATH"
    exit 1
fi

# Create the plist file for the mount script launch daemon
log "Creating plist file $MOUNT_PLIST_PATH"
bash -c "cat << EOF > $MOUNT_PLIST_PATH
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC '-//Apple//DTD PLIST 1.0//EN' 'http://www.apple.com/DTDs/PropertyList-1.0.dtd'>
<plist version=\"1.0\">
<dict>
    <key>Label</key>
    <string>info.mailbase.mountntfsdrives</string>
    <key>ProgramArguments</key>
    <array>
        <string>$MOUNT_SCRIPT_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>LaunchOnlyOnce</key>
    <true/>
</dict>
</plist>
EOF"
if [ $? -eq 0 ]; then
    log "Plist file $MOUNT_PLIST_PATH created successfully"
else
    log "Failed to create plist file $MOUNT_PLIST_PATH"
    exit 1
fi

# Load the eject launch daemon
log "Loading the eject launch daemon"
launchctl load "$EJECT_PLIST_PATH"
if [ $? -eq 0 ]; then
    log "Eject launch daemon loaded successfully"
else
    log "Failed to load eject launch daemon"
    exit 1
fi

# Load the mount launch daemon
log "Loading the mount launch daemon"
launchctl load "$MOUNT_PLIST_PATH"
if [ $? -eq 0 ]; then
    log "Mount launch daemon loaded successfully"
else
    log "Failed to load mount launch daemon"
    exit 1
fi

log "Setup complete. The scripts will now run at the appropriate times."
