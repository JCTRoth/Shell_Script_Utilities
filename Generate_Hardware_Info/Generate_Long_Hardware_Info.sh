#!/bin/bash

sudo apt-get install discus

DATE=$(date +"%d-%m-%Y")

name=$(sudo hostname)"_"$DATE".txt"

echo '\\\\\\' >> $name
echo $(sudo hostname) >> $name
lsb_release -i -c >> $name
echo "Kernel:" $(uname --kernel-version) >> $name

echo '\\\\\\' >> $name
sudo lshw -businfo >> $name


echo '\\\\\\' >> $name
echo 'USB Ports' >> $name
echo '\\\\\\' >> $name
lsusb 


echo '      ' >> $name
echo '\\\\\\' >> $name
echo 'Disk Usage' >> $name
echo '\\\\\\' >> $name
discus >> $name

