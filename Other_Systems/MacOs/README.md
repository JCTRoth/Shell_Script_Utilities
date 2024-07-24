# Mount All Ntfs Drives

This script checks for the installation of `ntfs-3g` on macOS, installs it if necessary, unmounts any already mounted NTFS drives, and then mounts all detected NTFS partitions to specified mount points.

## Requirements

- macOS
- Homebrew (for installing `ntfs-3g`)
- Administrative (sudo) privileges

## Script Overview

1. **Check for `ntfs-3g` installation:**
   - If `ntfs-3g` is not found, it is installed via Homebrew.
   
2. **Detect NTFS partitions:**
   - Uses `diskutil` to list all partitions and filters for NTFS partitions.
   
3. **Unmount any mounted NTFS partitions:**
   - Finds and unmounts currently mounted NTFS partitions.
   
4. **Mount NTFS partitions:**
   - Creates mount points and mounts each NTFS partition using `ntfs-3g`.

## Usage

1. **Clone the Repository:**

   ```sh
   git clone <repository_url>
   cd <repository_directory>
   ```

2. **Run the Script:**

   ```sh
   ./script_name.sh
   ```

   Replace `script_name.sh` with the actual script filename.

## Detailed Steps

### 1. Check for `ntfs-3g` Installation

The script checks if `ntfs-3g` is installed. If not, it installs `ntfs-3g` using Homebrew.

```sh
if ! command -v ntfs-3g &> /dev/null; then
    echo "ntfs-3g not found. Installing ntfs-3g..."
    brew install ntfs-3g
else
    echo "ntfs-3g is already installed."
fi
```

### 2. Detect NTFS Partitions

The script scans for NTFS partitions using `diskutil` and `grep`.

```sh
NTFS_PARTITIONS=$(diskutil list | grep Windows_NTFS | awk '{print $NF}')
```

### 3. Unmount Already Mounted NTFS Partitions

The script scans for mounted NTFS partitions and unmounts them.

```sh
MOUNTED_NTFS_PARTITIONS=$(mount | grep ntfs | awk '{print $1}')

for PARTITION in $MOUNTED_NTFS_PARTITIONS; do
    echo "Unmounting $PARTITION..."
    sudo umount "$PARTITION"
    
    if mount | grep "$PARTITION" > /dev/null; then
        echo "Failed to unmount $PARTITION."
    else
        echo "$PARTITION unmounted successfully."
    fi
done
```

### 4. Mount NTFS Partitions

The script mounts each detected NTFS partition to a specific mount point.

```sh
MOUNT_INDEX=1
for PARTITION in $NTFS_PARTITIONS; do
    MOUNT_POINT="/Volumes/mountPoint${MOUNT_INDEX}"
    
    if [ ! -d "$MOUNT_POINT" ]; then
        echo "Creating mount point directory at $MOUNT_POINT..."
        sudo mkdir -p "$MOUNT_POINT"
    fi

    echo "Mounting $PARTITION to $MOUNT_POINT..."
    sudo /usr/local/bin/ntfs-3g /dev/$PARTITION "$MOUNT_POINT" -olocal -oallow_other -oauto_xattr

    if mount | grep "$MOUNT_POINT" > /dev/null; then
        echo "Drive mounted successfully at $MOUNT_POINT."
    else
        echo "Failed to mount the drive $PARTITION."
    fi

    MOUNT_INDEX=$((MOUNT_INDEX + 1))
done
```

## Notes

- Ensure you have Homebrew installed on your macOS system before running the script.
- Running the script requires administrative (sudo) privileges.
- Adjust the mount point directory names as needed for your specific setup.

## Troubleshooting

- If the script fails to install `ntfs-3g`, ensure Homebrew is correctly installed and configured.
- Verify the NTFS partitions are detected correctly using `diskutil list`.
- Ensure the `ntfs-3g` binary is located in `/usr/local/bin/ntfs-3g` or modify the script to match your installation path.
