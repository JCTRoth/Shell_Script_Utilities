#!/bin/bash
#Install Program
sudo apt install flameshot
#Create Directory for Screenshots
mkdir ~/Screenshot
#Get Home Dir
homeDir=$(echo $HOME)
bookmarkPath='file:///'"$homeDir"'/Screenshot'
#Set Bookmark Gnome3,Mate,Cinammon...all GTK3 Desk. Env.
echo $bookmarkPath >> ~/.config/gtk-3.0/bookmarks
#Auto. Starter
sudo cp /usr/share/applications/flameshot.desktop /etc/xdg/autostart/
#Ask if keycombination should be added
echo "Should the Print button start FlameShot?"
read answer
if [[ $answer == "Y" || $answer == "y" || $answer == "yes" || $answer == "Yes" || $answer == "ja" ]]
then
echo "Backup of old keybindings"
#Dump Conf as Text File
dconf dump / > ~/Dconf_settings.txt
#Backup Conf. File
cp ~/Dconf_settings.txt ~/Dconf_settings.txt.backup
#Find Old Command
lineText=$(grep -Pn '(^|\s)\Print' dconf-backup.txt)
#Get Number of Line to Replace
lineNumber=$(echo $lineText | grep -o '[0-9]\+')
#Remove old Command
#lineNumber
#sed -e "$lineNumber" foo
#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

#Add new Command
echo "[org/mate/desktop/keybindings/custom0]
action='flameshot gui -p ~/Screenshot'
binding='Print'
name='Screenshot'" >> ~/Dconf_settings.txt

else
############################
fi

#End Of Script
echo "all done - press any key to quit"
read -s
