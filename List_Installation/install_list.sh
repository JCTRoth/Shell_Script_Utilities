#!/bin/bash
if [ ! $1 ];
then echo "kein input geben sie datei path hinter script an"

else
echo "Install list: " $1
xargs -a $1 sudo apt-get -y install 
fi
