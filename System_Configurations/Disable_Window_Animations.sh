#!/bin/bash

# --- Disable Compositing & Animations for All Supported DEs ---

# Function to silently run gsettings (ignore errors if schema doesn't exist)
run_gsetting() {
    gsettings set "$1" "$2" "$3" 2>/dev/null
}

# Disable compositing for MATE
run_gsetting org.mate.Marco.general compositing-manager false

# Disable animations for MATE, Cinnamon, and GNOME
run_gsetting org.mate.interface enable-animations false
run_gsetting org.cinnamon.desktop.interface enable-animations false
run_gsetting org.gnome.desktop.interface enable-animations false

# Disable sound preview for MATE, Cinnamon, and GNOME
run_gsetting org.mate.caja.preferences preview-sound 'never'
run_gsetting org.cinnamon.desktop.sound preview-sound 'never'
run_gsetting org.gnome.desktop.sound preview-sound 'never'

# --- Plasma-specific section ---
if grep -q "Fedora" /etc/os-release && ([ "$XDG_CURRENT_DESKTOP" = "KDE" ] || [ "$XDG_SESSION_DESKTOP" = "plasma" ]); then
    # Install qt5-qttools if qdbus is missing
    if ! command -v qdbus &> /dev/null; then
        echo "Installing qt5-qttools for qdbus..."
        sudo dnf install -y qt5-qttools
    fi

    # Disable compositing for KDE Plasma
    kwriteconfig5 --file kwinrc --group Compositing --key Enabled false 2>/dev/null

    # Disable animations for KDE Plasma
    kwriteconfig5 --file kwinrc --group Effect-Blur --key Enabled false 2>/dev/null
    kwriteconfig5 --file kwinrc --group Effect-DesktopGrid --key Enabled false 2>/dev/null
    kwriteconfig5 --file kwinrc --group Effect-MagicLamp --key Enabled false 2>/dev/null
    kwriteconfig5 --file kwinrc --group Effect-Slide --key Enabled false 2>/dev/null
    kwriteconfig5 --file kwinrc --group Effect-Zoom --key Enabled false 2>/dev/null

    # Detect session type (X11 or Wayland) and restart KWin
    if [ "$XDG_SESSION_TYPE" = "x11" ]; then
        kwin_x11 --replace &
    elif [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        kwin_wayland --replace &
    else
        echo "Could not detect session type. Please restart KWin manually."
    fi
fi

echo "Compositing, animations, and sound preview disabled for supported desktop environments."