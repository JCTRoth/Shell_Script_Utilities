#!/bin/bash

# Get sure zenity is installed
sudo apt-get install zenity

# Error Messages not shown
exec 2>/dev/null # Uncomment for debugging

# Window Size
h=100 # height
w=300 # width

# Question Box
if $(`zenity --height $h --width 200 --question --title "Question Box" --text "Start the tour?"`); then
	zenity --height $h --width $w --info --text "You selected <big>Ok</big>"; # Open Window showing result
else
	exit;
fi

# Entry Text Selector  - No Input End Program
if ! name=`zenity --height $h --width $w --title  "Your Name" --entry --text "Whats your name?"`; then
	name="Ash Ketchum"; # User Selected Cancel
fi

# Case: Empty Name
if [ -z $name ]; then
name="Nobody"; # User klicked Ok without input
fi

# List Directory Selector in text mode
if ! file1=`ls |  zenity  --height 400 --width $w --list  --title "Hallo $name: ls |  zenity  --list" --text "Contents of directory" --column "Files"`; then
exit;
fi

# Using Variable open file-selection
if ! file2=`zenity --height 400 --width $w --title="Hallo $name, select a file!" --file-selection`; then
exit;
fi

# Checklist with column Definitions
if ! choice=`zenity --height 300 --width 400 --list --title "$name, does this look right?" --checklist --text "" --column "Install" --column "File" TRUE $file1 TRUE $file2`;  then
exit;
fi

# Present result of Selection 
if ! zenity --height $h --width $w --info --text "You selected: $choice"; then
exit;
fi

# Password Input
if ! PASS=$(zenity --height $h --width $w --entry --hide-text --text "Don't enter your password." --title "PW"); then
exit;
fi

# Show Password
zenity --height $h --width $w --info --text "$name\n your password is: $PASS" --title "O-o";
exit;