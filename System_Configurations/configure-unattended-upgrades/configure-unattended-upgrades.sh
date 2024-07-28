#!/bin/bash

# Function to display usage information
usage() {
    echo "Usage: $0 --enable <enable|disable> --email <email> --reboot <true|false> --reboot-if-required <true|false> --reboot-time <HH:MM>"
    echo "  --enable: Enable or disable unattended-upgrades (default: enable)"
    echo "  --email: Email address for notifications (default: none)"
    echo "  --reboot: Enable or disable automatic reboot (default: false)"
    echo "  --reboot-if-required: Enable or disable automatic reboot only if required (default: false)"
    echo "  --reboot-time: Time to perform the reboot (default: none, format: HH:MM)"
    exit 1
}

# Default values
ENABLE="enable"
EMAIL=""
AUTO_REBOOT="false"
AUTO_REBOOT_IF_REQUIRED="false"
REBOOT_TIME=""

# Parse input parameters
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --enable)
            ENABLE="$2"
            shift 2
            ;;
        --email)
            EMAIL="$2"
            shift 2
            ;;
        --reboot)
            AUTO_REBOOT="$2"
            shift 2
            ;;
        --reboot-if-required)
            AUTO_REBOOT_IF_REQUIRED="$2"
            shift 2
            ;;
        --reboot-time)
            REBOOT_TIME="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

# Validate input parameters
if [[ "$ENABLE" != "enable" && "$ENABLE" != "disable" ]]; then
    echo "Invalid value for --enable. Must be 'enable' or 'disable'."
    usage
fi

if [[ "$AUTO_REBOOT" != "true" && "$AUTO_REBOOT" != "false" ]]; then
    echo "Invalid value for --reboot. Must be 'true' or 'false'."
    usage
fi

if [[ "$AUTO_REBOOT_IF_REQUIRED" != "true" && "$AUTO_REBOOT_IF_REQUIRED" != "false" ]]; then
    echo "Invalid value for --reboot-if-required. Must be 'true' or 'false'."
    usage
fi

if [[ -n "$REBOOT_TIME" && ! "$REBOOT_TIME" =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]]; then
    echo "Invalid value for --reboot-time. Must be in format HH:MM."
    usage
fi

# Install unattended-upgrades if not already installed
if ! dpkg -l | grep -q unattended-upgrades; then
    sudo apt-get update
    sudo apt-get install -y unattended-upgrades
fi

# Preconfigure unattended-upgrades to automatically install updates
echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | sudo debconf-set-selections

# Enable or disable unattended-upgrades
if [[ "$ENABLE" == "enable" ]]; then
    sudo dpkg-reconfigure --frontend=noninteractive unattended-upgrades
else
    sudo systemctl stop unattended-upgrades
    sudo systemctl disable unattended-upgrades
fi

# Configure unattended-upgrades settings
sudo bash -c "cat > /etc/apt/apt.conf.d/50unattended-upgrades" <<EOF
Unattended-Upgrade::Mail "${EMAIL}";
Unattended-Upgrade::Automatic-Reboot "${AUTO_REBOOT}";
Unattended-Upgrade::Automatic-Reboot-WithUsers "${AUTO_REBOOT_IF_REQUIRED}";
Unattended-Upgrade::Automatic-Reboot-Time "${REBOOT_TIME}";
EOF

# Restart the unattended-upgrades service if enabled
if [[ "$ENABLE" == "enable" ]]; then
    sudo systemctl restart unattended-upgrades
fi

echo "Configuration of unattended-upgrades completed."

