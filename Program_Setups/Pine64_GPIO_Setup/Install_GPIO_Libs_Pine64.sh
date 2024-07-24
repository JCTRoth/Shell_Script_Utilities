#!/bin/bash

# Path to the other scripts
PREPARE_HARDWARE_SCRIPT="./Prepare_Hardware_Access.sh"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root or with sudo."
    exit 1
fi

# Check if the required script exist
if [ ! -f "$PREPARE_HARDWARE_SCRIPT" ]; then
    echo "Error: $PREPARE_HARDWARE_SCRIPT not found."
    exit 1
fi

echo "Running $PREPARE_HARDWARE_SCRIPT..."
bash "$PREPARE_HARDWARE_SCRIPT"

# Install required packages
sudo apt install git python3-pip python3-dev rpi.gpio-common

# Clone lib from github
git clone https://github.com/JCTRoth/RPi.GPIO-PineA64-Python3.git
cd RPi.GPIO-PineA64-Python3/

# Install the lib in the system
# Than check if installation was made
sudo python3 setup.py install

sudo pip3 install RPi.GPIO --break-system-packages
if [ $? -ne 0 ]; then
    echo "Error: Failed to install the RPi.GPIO package."
    exit 1
fi

# Run Tests
echo "Run GPIO Tests."
sudo python3 ./test/test.py

echo "Setup complete. Please reboot your system for the changes to take effect."