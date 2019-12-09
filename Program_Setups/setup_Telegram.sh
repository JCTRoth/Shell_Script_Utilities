# Get user Name
userName=$(whoami)
# Login as root
sudo mkdir /opt/Telegram
cd /opt/Telegram
sudo wget https://telegram.org/dl/desktop/linux
sudo mv linux linux.tar.xz #rename
sudo 7z e linux.tar.xz
sudo 7z e linux.tar -y
sudo rm linux.tar.xz
sudo rm linux.tar
# Set LoggedIn User as Owner
sudo chown "$userName" Telegram
sudo chown "$userName" Updater
sudo ln /opt/Telegram/Telegram /usr/bin/telegram
sudo chmod +x /usr/bin/Telegram
chmod +x Telegram
chmod +x Updater
exit;
