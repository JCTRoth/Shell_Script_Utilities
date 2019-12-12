#!/bin/bash

sudo cp 51-android.rules /etc/udev/rules.d/
sudo chmod 755 /etc/udev/rules.d/51-android.rules

#End Of Script
echo "all done - press any key to quit"
read -s
