#!/bin/bash

# Disable compositing for MATE
gsettings set org.mate.Marco.general compositing-manager false

# Disable animations for MATE, Cinnamon, and GNOME
gsettings set org.mate.interface enable-animations false
gsettings set org.cinnamon.desktop.interface enable-animations false
gsettings set org.gnome.desktop.interface enable-animations false

# Disable sound preview for MATE, Cinnamon, and GNOME
gsettings set org.mate.caja.preferences preview-sound 'never'
gsettings set org.cinnamon.desktop.sound preview-sound 'never'
gsettings set org.gnome.desktop.sound preview-sound 'never'

echo "Compositing, animations, and sound preview disabled for MATE, Cinnamon, and GNOME."
