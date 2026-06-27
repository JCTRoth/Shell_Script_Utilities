#!/bin/bash

# Fedora: dnf statt apt
if rpm -q brltty &>/dev/null; then
    echo "Removing brltty..."
    sudo dnf remove -y brltty
else
    echo "brltty not installed, skipping..."
fi

# Download udev rules
wget -q https://raw.githubusercontent.com/platformio/platformio-core/develop/platformio/assets/system/99-platformio-udev.rules || { echo "Failed to download."; exit 1; }

# Install with correct permissions (644 statt 755, udev rules müssen nicht ausführbar sein)
sudo install -m 644 99-platformio-udev.rules /etc/udev/rules.d/ || { echo "Failed to copy."; exit 1; }

rm 99-platformio-udev.rules

# Reload rules
sudo udevadm control --reload-rules
sudo udevadm trigger

# Fedora: systemd-udevd statt udev
sudo systemctl restart systemd-udevd || { echo "Failed to restart udev service."; exit 1; }

echo "All done - now connect the device."