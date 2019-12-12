#!/bin/bash

wget https://raw.githubusercontent.com/platformio/platformio-core/master/scripts/99-platformio-udev.rules

sudo cp 99-platformio-udev.rules /etc/udev/rules.d/ #Copy to Destination

sudo chmod 755 /etc/udev/rules.d/99-platformio-udev.rules

rm 99-platformio-udev.rules #Delete Downloaded File

sudo service udev restart #Restart Service

#End Of Script
echo "all done - now reconnect USB"

