#!/bin/bash

# Linux Mint, Ubuntu maybe Debian – SMB network discovery helper (no GUI parts)

set -e

REQUIRED_PKGS=("samba" "smbclient" "gvfs-backends" "avahi-daemon")

echo "=== Linux Mint SMB / Network Discovery Setup ==="
echo

# 1. Check for root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run with sudo or as root."
    echo "Example: sudo $0"
    exit 1
fi

# 2. Confirm
echo "This will:"
echo "  - Update package lists (apt update)"
echo "  - Install: ${REQUIRED_PKGS[*]}"
echo "  - Enable and start: smbd, avahi-daemon"
echo
read -rp "Continue? [y/N]: " CONFIRM
CONFIRM=${CONFIRM,,}  # to lowercase
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "yes" ]]; then
    echo "Aborted by user."
    exit 0
fi

echo
echo ">>> Updating package lists..."
apt update

echo
echo ">>> Installing required packages..."
apt install -y "${REQUIRED_PKGS[@]}"

echo
echo ">>> Enabling and starting services..."
systemctl enable --now smbd
systemctl enable --now avahi-daemon

echo
echo ">>> Checking service status (short)..."
SYSTEMD_FAILED=0

if systemctl is-active --quiet smbd; then
    echo "  [OK] smbd is active."
else
    echo "  [ERROR] smbd is NOT active. Check with: systemctl status smbd"
    SYSTEMD_FAILED=1
fi

if systemctl is-active --quiet avahi-daemon; then
    echo "  [OK] avahi-daemon is active."
else
    echo "  [ERROR] avahi-daemon is NOT active. Check with: systemctl status avahi-daemon"
    SYSTEMD_FAILED=1
fi

echo
echo ">>> Basic Samba test (local share list)..."
if command -v smbclient >/dev/null 2>&1; then
    if smbclient -L localhost -N >/dev/null 2>&1; then
        echo "  [OK] smbclient can talk to localhost (no-auth test)."
    else
        echo "  [WARN] smbclient -L localhost failed (may be normal if no shares or auth needed)."
        echo "        You can test later with: smbclient -L localhost -U youruser"
    fi
else
    echo "  [WARN] smbclient command not found (install should have provided it)."
fi

echo
echo ">>> Firewall note:"
echo "If you use UFW or another firewall, ensure Samba is allowed, e.g.:"
echo "  sudo ufw allow Samba"
echo

if [[ $SYSTEMD_FAILED -eq 0 ]]; then
    echo "=== All done. SMB services should now be running. ==="
    echo "On another machine, try: smbclient -L HOSTNAME_OF_THIS_PC -U youruser"
else
    echo "=== Completed with some service errors. Please check the messages above. ==="
fi
