#!/bin/sh

# Check if ntfs-3g is installed, install if it is not
if ! command -v ntfs-3g &> /dev/null; then
    echo "ntfs-3g not found. Installing ntfs-3g..."
    brew install ntfs-3g
else
    echo "ntfs-3g is already installed."
fi

echo "Scanning for NTFS drives..."

# Get a list of NTFS partitions
NTFS_PARTITIONS=$(diskutil list | grep Windows_NTFS | awk '{print $NF}')

echo "Scanning for already mounted NTFS drives..."

# Get a list of mounted NTFS partitions
MOUNTED_NTFS_PARTITIONS=$(mount | grep ntfs | awk '{print $1}')

# Unmount each NTFS partition found
for PARTITION in $MOUNTED_NTFS_PARTITIONS; do
    echo "Unmounting $PARTITION..."
    sudo umount "$PARTITION"
    
    # Verify the unmount
    if mount | grep "$PARTITION" > /dev/null; then
        echo "Failed to unmount $PARTITION."
    else
        echo "$PARTITION unmounted successfully."
    fi
done

echo "All NTFS drives mounted my macOS -> unmounted"


# Mount each NTFS partition found
MOUNT_INDEX=1
for PARTITION in $NTFS_PARTITIONS; do
    MOUNT_POINT="/Volumes/mountPoint${MOUNT_INDEX}"
    
    # Create the mount point directory if it doesn't exist
    if [ ! -d "$MOUNT_POINT" ]; then
        echo "Creating mount point directory at $MOUNT_POINT..."
        sudo mkdir -p "$MOUNT_POINT"
    fi

    # Mount the NTFS partition with ntfs-3g
    echo "Mounting $PARTITION to $MOUNT_POINT..."
    sudo /usr/local/bin/ntfs-3g /dev/$PARTITION "$MOUNT_POINT" -olocal -oallow_other -oauto_xattr

    # Verify the mount
    if mount | grep "$MOUNT_POINT" > /dev/null; then
        echo "Drive mounted successfully at $MOUNT_POINT."
    else
        echo "Failed to mount the drive $PARTITION."
    fi

    MOUNT_INDEX=$((MOUNT_INDEX + 1))
done
