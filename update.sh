#!/bin/bash

channel=$1
channel="${channel#--}"

if [ $channel = "release" ]; then
echo "Checking for Updates.."
VERSION=$(curl --silent "https://raw.githubusercontent.com/valexcloud/valexclient/main/$channel")
if [ $VERSION = "none" ]; then
echo "No Updates Available"
else
channel_formatted=$(echo "$channel" | sed -E 's/(^| )(.)/\U\2/g; s/ /_/g')
echo "Updating Valex Client to: V$VERSION ($channel_formatted)"
apt -y update
apt -y upgrade
rm -f /var/www/.env
cp -f /var/www/valexclient/.env /var/www/.env
rm -rf /var/www/valexclient
wget https://raw.githubusercontent.com/valexcloud/valexclient/main/ValexClient-$channel_formatted-V$VERSION.zip
unzip ValexClient-$channel_formatted-V$VERSION.zip
rm -f ValexClient-$channel_formatted-V$VERSION.zip
rm -f /var/www/valexclient/.env
cp -f /var/www/.env /var/www/valexclient/.env
rm -f /var/www/.env
cd /var/www/valexclient
npm install
node /var/www/valexclient/update.js
echo "Update Finished!"
fi
elif [ $channel = "release_candidate" ]; then
echo "Checking for Updates.."
VERSION=$(curl --silent "https://raw.githubusercontent.com/valexcloud/valexclient/main/$channel")
if [ $VERSION = "none" ]; then
echo "No Updates Available"
else
channel_formatted=$(echo "$channel" | sed -E 's/(^| )(.)/\U\2/g; s/ /_/g')
echo "Updating Valex Client to: V$VERSION ($channel_formatted)"
apt -y update
apt -y upgrade
rm -f /var/www/.env
cp -f /var/www/valexclient/.env /var/www/.env
rm -rf /var/www/valexclient
wget https://raw.githubusercontent.com/valexcloud/valexclient/main/ValexClient-$channel_formatted-V$VERSION.zip
unzip ValexClient-$channel_formatted-V$VERSION.zipp
rm -f ValexClient-$channel_formatted-V$VERSION.zip
rm -f /var/www/valexclient/.env
cp -f /var/www/.env /var/www/valexclient/.env
rm -f /var/www/.env
cd /var/www/valexclient
npm install
node /var/www/valexclient/update.js
echo "Update Finished!"
fi
elif [ $channel = "beta" ]; then
echo "Checking for Updates.."
VERSION=$(curl --silent "https://raw.githubusercontent.com/valexcloud/valexclient/main/$channel")
if [ $VERSION = "none" ]; then
echo "No Updates Available"
else
channel_formatted=$(echo "$channel" | sed -E 's/(^| )(.)/\U\2/g; s/ /_/g')
echo "Updating Valex Client to: V$VERSION ($channel_formatted)"
apt -y update
apt -y upgrade
rm -f /var/www/.env
cp -f -f /var/www/valexclient/.env /var/www/.env
rm -rf /var/www/valexclient
wget https://raw.githubusercontent.com/valexcloud/valexclient/main/ValexClient-$channel_formatted-V$VERSION.zip
unzip ValexClient-$channel_formatted-V$VERSION.zipp
rm -f ValexClient-$channel_formatted-V$VERSION.zip
rm -f /var/www/valexclient/.env
cp -f /var/www/.env /var/www/valexclient/.env
rm -f /var/www/.env
cd /var/www/valexclient
npm install
node /var/www/valexclient/update.js
echo "Update Finished!"
fi
else
echo "No Updates Available"
fi