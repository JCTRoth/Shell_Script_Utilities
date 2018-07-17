#!/bin/bash

#empty initialization
package=" ";

#read in keyboard
read -p "Input package list path: " pl;


while [ ! "quit" == "$package" ]
do
echo "Add additional packages"
read -p "Enter a single package: " package
chache=$(apt list $package)
echo $chache | if grep --only-matching $package;
then 
echo "found"
echo $package >> $pl

else echo "not found"
fi
 
done

