#!/bin/bash

# Get sure zenity is installed
sudo apt-get install zenity

# Error Messages not shown
exec 2>/dev/null # Uncomment for debugging

# Question Box
if $(`zenity  --question --title "Question Box"   --text  "Start the tour?"`); then
	zenity --info --text "You selected <big>Ok</big>";
else
	exit;
fi

# Entry Text Selector  - No Input End Program
if ! name=`zenity --title  "Your Name" --entry --text "Whats your name?"`; then
	name="Ash Ketchum"; # User Selected Cancle
fi

# Case: Empty Name
if [ -z $name ]; then
name="Nobody"; # User Selected Cancle
fi

# List Directory Selector - text
if ! file1=`ls |  zenity  --list  --title "Hallo $name: ls |  zenity  --list" --text "Contents of directory" --column "Files"`; then
exit;
fi


# Using Variable of Name and open file-selection
if ! file2=`zenity --title="Hallo $name, select a file!" --file-selection`; then
exit;
fi

# Checklist with column Definitions
if ! choice=`zenity  --list --title "$name, does this look right?" --checklist --text "" --column "Install" --column "File" TRUE $file1 TRUE $file2`;  then
exit;
fi

# Present result of Selection 
if ! zenity --info --text "You selected: $choice"; then
exit;
fi

# Password Input
if ! PASS=$(zenity --entry --hide-text --text "Don't enter your password." --title "PW"); then
exit;
fi

# Show Password
zenity --info --text "$name\n your password is: $PASS" --title "O-o";
exit;