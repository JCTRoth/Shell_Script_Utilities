#!/bin/bash

#Current date
DATE=$(date +"%Y-%m-%d_%H":"%M")



#doBackup, backups folder as tar or folder
#doBackup is used by menu
function doBackup(){
read -p "Backup the Folder as Archive File? " archive;


if [[ $archive == "Y" || $archive == "y" || $archive == "yes" || $archive == "Yes" || $archive == "ja" ]]
then 
tar -cjpf ./backup-$DATE.tar.bz2 $path;
else
cp -r --preserve=all $path ./$DATE/
fi }


#reads input from keyboard
read -p "Input Path of the Folder to backup: " path
echo "Wanne use the DATE as name for backup? "
read filename
if [[ $filename == "Y" || $filename == "y" || $filename == "yes" || $filename == "Yes" || $filename == "ja" ]]
then
doBackup $DATE

else
        read -p "Input Backup's name: " filename
		doBackup $filename

fi
