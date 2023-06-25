rm -rf /var/www/valexclient
echo "What is your Valex Client Database Name?"
read -r DEL_DB
mysql -u root -D $DEL_DB -e "DROP DATABASE $DEL_DB"
echo "Uninstallation Complete!"