#!/bin/bash

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root or with sudo."
    exit 1
fi

# Create gpio group if it doesn't exist
if ! getent group gpio > /dev/null; then
    echo "Creating gpio group..."
    groupadd gpio
else
    echo "gpio group already exists."
fi

# Add the current user to the gpio group
CURRENT_USER=$(logname)
if id -nG "$CURRENT_USER" | grep -qw gpio; then
    echo "$CURRENT_USER is already a member of gpio group."
else
    echo "Adding $CURRENT_USER to gpio group..."
    usermod -aG gpio $CURRENT_USER
fi

# Create the udev rules file
UDEV_RULES_FILE='/etc/udev/rules.d/99-gpio.rules'

echo "Creating udev rules file at $UDEV_RULES_FILE..."

cat <<EOF > $UDEV_RULES_FILE
SUBSYSTEM=="bcm2835-gpiomem", KERNEL=="gpiomem", GROUP="gpio", MODE="0660"
SUBSYSTEM=="gpio", KERNEL=="gpiochip*", ACTION=="add", PROGRAM="/bin/sh -c 'chown root:gpio /sys/class/gpio/export /sys/class/gpio/unexport ; chmod 220 /sys/class/gpio/export /sys/class/gpio/unexport'"
SUBSYSTEM=="gpio", KERNEL=="gpio*", ACTION=="add", PROGRAM="/bin/sh -c 'chown root:gpio /sys%p/active_low /sys%p/direction /sys%p/edge /sys%p/value ; chmod 660 /sys%p/active_low /sys%p/direction /sys%p/edge /sys%p/value'"
EOF

echo "Udev rules file created."

# Reload udev rules
echo "Reloading udev rules..."
udevadm control --reload-rules && udevadm trigger

echo "Setup complete. Please reboot your system for the changes to take effect."
