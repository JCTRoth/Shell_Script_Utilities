#!/bin/bash

# Define the output file name with timestamp
output_file="output_$(date +%Y%m%d_%H%M%S).txt"

{
    echo "--------------------------------------------------"
    echo "System Information"
    echo "--------------------------------------------------"
    echo ""
    echo "Date and Time: $(date)"
    echo "Hostname: $(hostname)"
    echo "Uptime: $(uptime)"
    echo "CPU: $(grep -m 1 'model name' /proc/cpuinfo | awk -F: '{print $2}')"
    echo "$(free -h)"
    echo "Network: $(ip a | awk '/inet / {print $2}')"
    echo ""
    echo "--------------------------------------------------"
    echo ""
    echo "Disk Usage:"
    echo ""
    if ! command -v discus &> /dev/null; then
        echo "Discus is not installed. Installing now..."
        sudo apt-get update
        sudo apt-get install -y discus
        echo "Discus installed successfully."
    else
        discus -c -s -d
    fi
    echo ""
    echo "--------------------------------------------------"
    echo ""
    echo "USB Devices:"
    echo ""
    lsusb
    echo "--------------------------------------------------"
    echo ""
    echo "Loaded Kernel Modules:"
    echo ""
    lsmod
    echo "--------------------------------------------------"
    echo ""
    echo "Running Tasks:"
    echo ""
    ps aux
    echo "--------------------------------------------------"
    echo ""
    echo "Bash History:"
    echo ""
    history
    echo ""
    echo "--------------------------------------------------"
    echo ""
    echo "Additionally Installed Programs:"
    echo ""
    dpkg --get-selections | awk '!/deinstall/{print $1}'
    echo "--------------------------------------------------"
    echo ""
    echo "Folders in Home Directory:"
    echo ""
    find ~ -type d 2>/dev/null
    echo "--------------------------------------------------"
} > "$output_file"

echo "System information has been saved to $output_file"
