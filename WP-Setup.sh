#!/bin/bash

#Run script with the below. Most recent version will always be at that address.
#sudo su
#curl https://raw.githubusercontent.com/zn3zman/AWS-WordPress-Creation/master/WP-Setup.sh > WP-Setup.sh ; chmod 700 WP-Setup.sh ; ./WP-Setup.sh

# Set default variables
wordpressdb=wordpress-db
SQLUser=SQLAdmin
SQLPass=AComplexPassword87
green=`tput setaf 2`
nocolor=`tput sgr0`

# Running as UserData?
if [ -t 1 ]
then
    # If not running as userdata, prompt for veriables.
    clear
    echo -e "\n\nGetting SQL variables. This information and further instructions will be stored in ${green}/root/WordPressSQLInfo.txt${nocolor}"
    read -e -p "\n\nWhat do you want your WordPress database to be named? " -i "wordpress-db" wordpressdb
    read -e -p "\n\nWhat do you want your SQL admin username to be? " -i "SQLAdmin" SQLUser
    read -e -p "\n\nWhat do you want $SQLUser's password to be? " -i "AComplexPassword87" SQLPass
	clear
fi

# Store SQL information, overwriting previous file if exists
echo -e "Your Wordpress database is called: $wordpressdb" > /root/WordPressSQLInfo.txt
echo -e "Your Wordpress Admin account is called: $SQLUser" >> /root/WordPressSQLInfo.txt
echo -e "Your Wordpress admin account's password is: $SQLPass" >> /root/WordPressSQLInfo.txt
echo -e "(this is also SQL root's password for simplification of the script. You should change this)" >> /root/WordPressSQLInfo.txt
chmod 600 /root/WordPressSQLInfo.txt

# Update server (hopefully), install apache, mysql, php, etc depending on OS
# This script handles basic amzn, ubuntu, rhel, suse, 
OS=$(cat /etc/os-release | grep "ID" | grep -v "VERSION" | grep -v "LIKE" | sed 's/ID=//g' | sed 's/["]//g' | awk '{print $1}')
if [ $OS = "amzn" ]
then
	yum upgrade -y && yum update -y
	yum install -y httpd mysql-server php php-mysql wget curl
	service mysqld start
elif [ $OS = "ubuntu" ]
then
	apt-get update && apt-get upgrade -y
	export DEBIAN_FRONTEND=noninteractive
	apt-get install -y apache2 mysql-server php5 php5-mysql wget curl
	service mysql start
elif [ $OS = "rhel" ]
then
	yum upgrade -y && yum update -y
	yum repolist enabled | grep "mysql.*-community.*"
	yum install -y httpd mariadb mariadb-server php php-mysql wget curl
	/bin/systemctl start mariadb.service
elif [ $OS = "sles" ]
then
	echo -e "SUSE runs \"zypper update -y\" on initial boot. It can take up to 8 minutes to finish."
	if zypper update -y --dry-run ; then g2g="yes" ; else g2g="no" ; fi ; while [ $g2g == "no" ]; do echo -e "Zypper is busy (up to 8 minutes). Waiting 5 seconds and retrying..." ; sleep 5 ; if zypper update -y --dry-run ; then g2g="yes" ; else g2g="no" ; fi ; done 
	zypper update -y
	zypper install -y apache2 mariadb php5 php5-mysql apache2-mod_php5 wget curl
	service mysql start
else
	echo -e "I can't find your OS name. Exiting to prevent clutter."
	exit 1
fi

# Automating mysql_secure_installation
# Blatantly borrowed from https://gist.github.com/Mins/4602864
mysqladmin -u root password "$SQLPass"
mysql -u root -p"$SQLPass" -e "UPDATE mysql.user SET Password=PASSWORD('$SQLPass') WHERE User='root'"
mysql -u root -p"$SQLPass" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
mysql -u root -p"$SQLPass" -e "DELETE FROM mysql.user WHERE User=''"
mysql -u root -p"$SQLPass" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'"
mysql -u root -p"$SQLPass" -e "FLUSH PRIVILEGES"
echo -e "SQL Secure"

# Create the wordpress database
mysql -u root -p"$SQLPass" -e "CREATE USER '$SQLUser'@'localhost' IDENTIFIED BY '$SQLPass';"
mysql -u root -p"$SQLPass" -e "CREATE DATABASE \`$wordpressdb\`;"
mysql -u root -p"$SQLPass" -e "GRANT ALL PRIVILEGES ON \`$wordpressdb\`.* TO "$SQLUser"@'localhost';"
mysql -u root -p"$SQLPass" -e "FLUSH PRIVILEGES"

# Lazy way to allow WordPress access to .htaccess files
# Also restart services, ensure services start on boot
if [ $OS = "amzn" ]
then
	sed -i -e 's/AllowOverride None/AllowOverride All/g' /etc/httpd/conf/httpd.conf
	service httpd start
	service mysqld restart
	chkconfig httpd on
	chkconfig mysqld on
elif [ $OS = "ubuntu" ]
then
	sed -i -e 's/AllowOverride None/AllowOverride All/g' /etc/apache2/apache2.conf
	service apache2 start
	service mysql restart
elif [ $OS = "rhel" ]
then
	sed -i -e 's/AllowOverride None/AllowOverride All/g' /etc/httpd/conf/httpd.conf
	service httpd start
	service mariadb restart
	chkconfig httpd on
	chkconfig mariadb on
elif [ $OS = "sles" ]
then
	sed -i -e 's/AllowOverride None/AllowOverride All/' /etc/apache2/default-server.conf
	sed -i -e 's/DirectoryIndex index.html index.html.var/DirectoryIndex index.html index.html.var index.php/' /etc/apache2/httpd.conf
	sed -i -e 's/APACHE_MODULES="/APACHE_MODULES="php5 /' /etc/sysconfig/apache2
	sed -i -e 's/FW_CONFIGURATIONS_EXT=""/FW_CONFIGURATIONS_EXT="apache2"/' /etc/sysconfig/SuSEfirewall2
	systemctl restart SuSEfirewall2
	service apache2 start
	service mysql restart
	chkconfig apache2 on
	chkconfig mysql on
else
	echo -e "This script shouldn't have made it this far with your configuration. I have no idea how you did that. Exiting..."
	exit 1
fi

# Download the latest version of wordpress and move to /var/www/html
if [ $OS = "sles" ]
then
	cd /srv/www/htdocs/
else
	cd /var/www/html
fi
wget http://wordpress.org/latest.tar.gz
tar -xzvf latest.tar.gz
cd wordpress
mv -f * ../
cd ..
rm -f latest.tar.gz
rm -rf ./wordpress
rm index.html -f

# Create wp-config.php and give it some salt. Normal comments are removed because I'm lazy
WPSalts=$(curl https://api.wordpress.org/secret-key/1.1/salt/)
cat > ./wp-config.php <<-EOF
<?php
define('DB_NAME', '$wordpressdb');
define('DB_USER', '$SQLUser');
define('DB_PASSWORD', '$SQLPass');
define('DB_HOST', 'localhost');
define('DB_CHARSET', 'utf8');
define('DB_COLLATE', '');
$WPSalts
\$table_prefix  = 'wp_';
define('WP_DEBUG', false);
if ( !defined('ABSPATH') )
        define('ABSPATH', dirname(__FILE__) . '/');
require_once(ABSPATH . 'wp-settings.php');
EOF

# Create www group, add apache to that group, and set permissions on /var/www/html to let WordPress access and update itself
echo -e "\n\nUpdating permissions. This may take a few minutes...\n\n"
if [ $OS = "amzn" ] || [ $OS = "rhel" ]
then
	groupadd www
	usermod -a -G www apache
	chown -R apache /var/www
	chgrp -R www /var/www
	chmod 2775 /var/www
	find /var/www -type d -exec sudo chmod 2775 {} \;
	find /var/www -type f -exec sudo chmod 0664 {} \;
fi

# SUSE's groups are weird. This might let WordPress access and update itself. It also won't accept SSH connections until it's rebooted, for some reason.
if [ $OS = "sles" ]
then
	chown -R root /srv/www
	chgrp -R www /srv/www
	chmod 2775 /srv/www
	find /srv/www -type d -exec sudo chmod 2775 {} \;
	find /srv/www -type f -exec sudo chmod 0664 {} \;
	echo -e "\n\nNow go to http://$(curl --silent http://bot.whatismyipaddress.com/) in your browser to set up your site." | tee -a /root/WordPressSQLInfo.txt
	echo -e "\nRebooting in ten seconds to finalize..."
	for n in {10..1}; do
		printf "\r%s " $n
		sleep 1
	done
	shutdown -r now	
fi
echo -e "\n\nNow go to${green} http://$(curl --silent http://bot.whatismyipaddress.com/) ${nocolor}in your browser to set up your site.\n" | tee -a /root/WordPressSQLInfo.txt
