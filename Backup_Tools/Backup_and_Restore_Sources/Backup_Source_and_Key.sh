#!/bin/bash

# Backup APT sources and trusted keys
# Date format for backup name
DATE=$(date +"%Y-%m-%d_%H-%M")

function doBackup() {
    local backup_name="$1"
    local backup_dir="$backup_name"

    # Create backup directory
    if ! mkdir -p "$backup_dir"; then
        echo "Error: Failed to create directory $backup_dir" >&2
        return 1
    fi

    echo "Creating backup in $backup_dir..."

    # Backup sources.list files
    # Find all .list files in /etc/apt/sources.list.d/ and /etc/apt/sources.list
    find /etc/apt/sources.list* -type f -name '*.list' -exec sh -c '
        echo -e "\n## $1"
        grep "^[[:space:]]*[^#[:space:]]" "$1"
    ' -- {} \; > "$backup_dir/$backup_name.list"

    # Backup trusted keys
    if sudo cp /etc/apt/trusted.gpg "$backup_dir/trusted-keys.gpg"; then
        echo "Backup completed: $backup_name"
    else
        echo "Error: Failed to copy trusted keys" >&2
        return 1
    fi
}

# Input menu
echo "Do you want to use the current date as backup name? (Y/n)"
read -r input
if [[ $input =~ ^[Yy]$|^$ ]]; then
    doBackup "$DATE"
else
    read -p "Enter the name of the backup file: " input
    doBackup "$input"
fi


