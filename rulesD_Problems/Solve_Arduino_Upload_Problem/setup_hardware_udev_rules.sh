#!/bin/bash

# Download the udev rules file
wget -q https://raw.githubusercontent.com/platformio/platformio-core/develop/platformio/assets/system/99-platformio-udev.rules || { echo "Failed to download udev rules file."; exit 1; }

# Copy to the destination with correct permissions
sudo install -m 755 99-platformio-udev.rules /etc/udev/rules.d/ || { echo "Failed to copy udev rules file."; exit 1; }

# Delete the downloaded file
rm 99-platformio-udev.rules || { echo "Failed to delete temporary udev rules file."; exit 1; }

# Reload udev rules
sudo udevadm control --reload-rules || { echo "Failed to reload udev rules."; exit 1; }

# Restart the udev service (optional, for full effect)
sudo systemctl restart udev || { echo "Failed to restart udev service."; exit 1; }

# End of script
echo "All done - now connect the device to the computer."


