#!/bin/bash

read -p "Backup must be extracted."
read -p "Input Backup's name: " path


sudo cp ./$path/$path.list /etc/apt/

#backup old key
sudo cp /etc/apt/trusted.gpg /etc/apt/trusted.gpg.backup

# Schlüsselbund importieren
sudo apt-key add ./$path/trusted-keys.gpg  
