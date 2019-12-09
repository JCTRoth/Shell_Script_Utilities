#!/bin/bash

# Date
DATE=$(date +"%Y-%m-%d_%H":"%M")


function doBackup() {

mkdir $inputValue;

find /etc/apt/sources.list* -type f -name '*.list' -exec bash -c 'echo -e "\n## $inputValue ";grep "^[[:space:]]*[^#[:space:]]" ${inputValue}' _ {} \; > ./$1/$1.list;

sudo cp /etc/apt/trusted.gpg ./$1/trusted-keys.gpg; 

echo "Backup file written as $inputValue"
}

#Das eingabe menü ist hier:
echo "Do you want to use the current date as backup name?"
read input
if [[ $input == "Y" || $input == "y" || $input == "yes" || $input == "Yes" ]]; 
	then
        doBackup $DATE
else
        read -p "Enter the name of the backup file:  " input
		doBackup $input
fi


