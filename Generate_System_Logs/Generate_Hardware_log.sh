#!/bin/bash

sudo apt-get install inxi

name=$(sudo hostname)"_"$DATE".txt"

echo '\\\\\\' >> $name
echo $(sudo hostname) >> $name
lsb_release -i -c >> $name
echo "Kernel:" $(uname --kernel-version) >> $name

echo '\\\\\\' >> $name

inxi -Fxzd >> $name

echo '\\\\\\' >> $name
echo '\\\\\\' >> $name

