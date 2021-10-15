#!/bin/bash
sudo apt-get install unattended-upgrades --force --unseen-only

sudo dpkg-reconfigure -plow unattended-upgrades
