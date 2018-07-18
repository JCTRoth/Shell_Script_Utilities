#!/bin/bash

DATE=$(date +"%d-%m-%Y")

name=$(sudo hostname)"_"$DATE".txt"

echo '\\\\\\' >> $name
echo $(sudo hostname) >> $name
lsb_release -i -c >> $name
echo "Kernel:" $(uname --kernel-version) >> $name

echo '\\\\\\' >> $name
echo 'Main System Info' >> $name
echo '\\\\\\' >> $name
sudo lshw -businfo >> $name

echo '      ' >> $name
echo '\\\\\\' >> $name
echo 'USB Ports' >> $name
echo '\\\\\\' >> $name
lsusb >> $name


echo '      ' >> $name
echo '\\\\\\' >> $name
echo 'I/O Usage' >> $name
echo '\\\\\\' >> $name
sudo iostat -pxd >> $name

echo '      ' >> $name
echo '\\\\\\' >> $name
echo 'Disk Space Usage' >> $name
echo '\\\\\\' >> $name
df -H >> $name

echo '      ' >> $name
echo '\\\\\\' >> $name
echo 'RAM/Swap Usage' >> $name
echo '\\\\\\' >> $name
free -h >> $name


echo '      ' >> $name
echo '\\\\\\' >> $name
echo 'Network Activity' >> $name
echo '\\\\\\' >> $name
sudo ifconfig -s >> $name

echo '      ' >> $name
echo '\\\\\\' >> $name
echo 'Open Network Ports' >> $name
echo '\\\\\\' >> $name
netstat -lntu >> $name

echo '      ' >> $name
echo '\\\\\\' >> $name
echo 'Running Tasks' >> $name
echo '\\\\\\' >> $name
top -n 1 -b  >> $name

echo '      ' >> $name
echo '\\\\\\' >> $name
echo 'Running Services' >> $name
echo '\\\\\\' >> $name
service --status-all >> $name


echo '\\\\\\\\' >> $name
echo '\\\\\\\\' >> $name

