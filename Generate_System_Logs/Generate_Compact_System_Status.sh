#!/bin/bash

# Define the output file name with timestamp
output_file="system_report_$(date +%Y%m%d_%H%M%S).txt"

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
    echo "Network Interfaces:"
    echo ""
    nmcli device status
    echo ""
    echo "Nearby Wireless Networks:"
    echo ""
    nmcli device wifi list
    echo "--------------------------------------------------"
    echo ""
    echo "Users with Roles:"
    echo ""
    getent passwd | while IFS=: read -r username _ uid gid _ home shell; do
        groups=$(id -Gn "$username")
        echo "Username: $username"
        echo "UID: $uid"
        echo "GID: $gid"
        echo "Groups: $groups"
        echo "Home Directory: $home"
        echo "Shell: $shell"
        echo ""
    done
    echo "--------------------------------------------------"
    echo ""
    echo "Open Ports on this Device:"
    echo ""
    netstat -tuln
    echo "--------------------------------------------------"
    echo ""
    echo "Bash History:"
    echo ""
    cat ~/.bash_history
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
