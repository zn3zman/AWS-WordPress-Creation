#!/bin/bash

# Poorly written by William Klassen - William.Klassen1@gmail.com
# Run script with the below command as root ('sudo -i' or 'sudo su'). Most recent version will always be at that address.
# bash <(curl https://cdn.rawgit.com/zn3zman/AWS-WordPress-Creation/master/WP-Setup.sh)

# Set default variables. The top three are what will be used for your SQL details if the script is run from UserData
wordpressdb=wordpress-db
SQLUser=SQLAdmin
SQLPass=AComplexPassword87
upgrademe=yes
red=`tput setaf 1`
green=`tput setaf 2`
yellow=`tput setaf 3`
nocolor=`tput sgr0`

# If not running as UserData, prompt for veriables.
if [[ -t 1 ]]
then
    # Confirm running as root. After testing, the script breaks if you try to run as a normal user prefixing sudo.  
    if [[ $(id -u) -ne 0 ]]
	then 
		echo "${red}Please run as root ('${green}sudo -i${red}' or '${green}sudo su${red}' before running the script).{nocolor}"
		exit 1
	fi
	clear
    echo -e "\n\nGetting SQL variables. This information and further instructions will be stored in ${green}/root/WordPressSQLInfo.txt${nocolor}\n"
	echo -e "\n" #I can't put linebreaks in the reads, annoyingly
    read -p "What do you want your WordPress database to be named? ${yellow}" -i "wordpress-db" -e wordpressdb
	echo -e "\n"
    read -e -p "${nocolor}What do you want your SQL admin username to be? ${yellow}" -i "SQLAdmin" SQLUser
	echo -e "\n"
    read -e -p "${nocolor}What do you want $SQLUser's password to be? ${yellow}" -i "AComplexPassword87" SQLPass
	echo -e "\n"
	upgrademe="maybe"
	read -e -p "${nocolor}Running an upgrade/update is highly recommended. Do you want to automatically upgrade/update? ('${green}yes${nocolor}' or '${red}no${nocolor}'?) " upgrademe
	echo -e "\n"
	while [[ $upgrademe != "yes" ]] && [[ $upgrademe != "no" ]]
	do 
		echo -e "\nYou entered '$upgrademe'. ${yellow}Please enter exactly '${green}yes${yellow}' or '${red}no${yellow}'${nocolor}\n"
		read -e -p "Upgrading/Updating is highly recommended before proceeding. Update/upgrade? ('${green}yes${nocolor}' or '${red}no${nocolor}'?) " upgrademe
	done
fi

# Store SQL information, overwriting previous file if exists
echo -e "Your Wordpress database is called: $wordpressdb" > /root/WordPressSQLInfo.txt
echo -e "Your SQL Wordpress database's admin account is called: $SQLUser" >> /root/WordPressSQLInfo.txt
echo -e "Your SQL Wordpress database's admin account's password is: $SQLPass" >> /root/WordPressSQLInfo.txt
echo -e "(this is also SQL root's password for simplification of the script. You should change this)" >> /root/WordPressSQLInfo.txt
# Remind the user to change both SQL passwords if the defaults were used
if [[ ! -t 1 ]] || [[ $SQLPass = "AComplexPassword87" ]]
then
	echo -e "--This was installed with the default values for passwords. ${red}YOU SHOULD DEFINITELY CHANGE THESE PASSWORDS${nocolor}." >> /root/WordPressSQLInfo.txt
fi
chmod 600 /root/WordPressSQLInfo.txt

# Update server (hopefully), install apache, mysql, php, etc depending on OS, then updates in case any of those were already installed
# This script handles basic amzn, ubuntu, rhel, suse, and CentOS
OS=$(cat /etc/os-release | grep "ID" | grep -v "VERSION" | grep -v "LIKE" | sed 's/ID=//g' | sed 's/["]//g' | awk '{print $1}') > /dev/null
if [[ $OS = "amzn" ]]
then
	if [[ $upgrademe = "yes" ]]
	then
		yum upgrade -y
	fi
	yum install -y httpd mysql-server php php-mysql wget curl
	yum upgrade -y httpd mysql-server php php-mysql wget curl
	service mysqld start
elif [[ $OS = "ubuntu" ]]
then
	if [[ $upgrademe = "yes" ]]
	then
		yum apt-get update && apt-get upgrade -y
	fi
	# mysql starts immediately after installation and requires user intervention. The debian bit below seems to fix that.
	export DEBIAN_FRONTEND=noninteractive
	apt-get install -y apache2 mysql-server php5 php5-mysql wget curl
	service mysql start
elif [[ $OS = "rhel" ]]
then
	if [[ $upgrademe = "yes" ]]
	then 
		yum upgrade -y
	fi
	yum repolist enabled | grep "mysql.*-community.*"
	yum install -y httpd mariadb mariadb-server php php-mysql wget curl
	yum upgrade -y httpd mariadb mariadb-server php php-mysql wget curl
	/bin/systemctl start mariadb.service
elif [[ $OS = "sles" ]]
then
	if zypper update -y --dry-run
	then 
		g2g="yes" 
	else
		g2g="no"
		echo -e "SUSE runs \"zypper update -y\" on initial boot. It can take up to 8 minutes to finish."
	fi
	# Keep checking every five seconds to see if zypper is done
	while [[ $g2g == "no" ]]
	do 
		echo -e "Zypper is busy (up to 8 minutes). Waiting 5 seconds and retrying..."
		sleep 5
		if zypper update -y --dry-run
		then 
			g2g="yes"
		else
			g2g="no"
		fi
	done 
	if [ $upgrademe = "yes" ]
	then 
		zypper update -y
	fi
	zypper install -y apache2 mariadb php5 php5-mysql apache2-mod_php5 wget curl
	zypper upgrade -y apache2 mariadb php5 php5-mysql apache2-mod_php5 wget curl
	service mysql start
else
	# CentOS doesn't have /etc/os-release, so we need to use /etc/issue
	OS=$(cat /etc/issue | awk '{print $1}')
	OS=$(echo $OS | cut -d " " -f 1)
	if [[ $OS = "CentOS" ]]
	then
		if [[ $upgrademe = "yes" ]]
		then 
			yum upgrade -y
		fi
		yum install -y httpd mysql-server php php-mysql wget curl
		yum upgrade -y httpd mysql-server php php-mysql wget curl
		/sbin/service mysqld start
	else
		echo -e "Your distro is not supported by this script. Exiting to prevent clutter."
		rm -f /root/WordPressSQLInfo.txt
		exit 1
	fi
fi

# Automating mysql_secure_installation
# Blatantly borrowed from https://gist.github.com/Mins/4602864
mysqladmin -u root password "$SQLPass"
mysql -u root -p"$SQLPass" -e "UPDATE mysql.user SET Password=PASSWORD('$SQLPass') WHERE User='root'"
mysql -u root -p"$SQLPass" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
mysql -u root -p"$SQLPass" -e "DELETE FROM mysql.user WHERE User=''"
mysql -u root -p"$SQLPass" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'"
mysql -u root -p"$SQLPass" -e "FLUSH PRIVILEGES"

# Create the wordpress database
mysql -u root -p"$SQLPass" -e "CREATE USER '$SQLUser'@'localhost' IDENTIFIED BY '$SQLPass';"
mysql -u root -p"$SQLPass" -e "CREATE DATABASE \`$wordpressdb\`;"
mysql -u root -p"$SQLPass" -e "GRANT ALL PRIVILEGES ON \`$wordpressdb\`.* TO "$SQLUser"@'localhost';"
mysql -u root -p"$SQLPass" -e "FLUSH PRIVILEGES"

# Lazy way to allow WordPress access to .htaccess files
# Also restart services, ensure services start on boot, and changes any other needed settings for php to run correctly
if [[ $OS = "amzn" ]]
then
	sed -i -e 's/AllowOverride None/AllowOverride All/g' /etc/httpd/conf/httpd.conf
	service httpd start
	service mysqld restart
	chkconfig httpd on
	chkconfig mysqld on
elif [[ $OS = "ubuntu" ]]
then
	sed -i -e 's/AllowOverride None/AllowOverride All/g' /etc/apache2/apache2.conf
	service apache2 start
	service mysql restart
elif [[ $OS = "rhel" ]]
then
	sed -i -e 's/AllowOverride None/AllowOverride All/g' /etc/httpd/conf/httpd.conf
	service httpd start
	service mariadb restart
	chkconfig httpd on
	chkconfig mariadb on
elif [[ $OS = "sles" ]]
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
elif [[ $OS = "CentOS" ]]
then
	sed -i -e 's/AllowOverride None/AllowOverride All/g' /etc/httpd/conf/httpd.conf
	/sbin/service httpd start
	/sbin/service mysqld restart
	/sbin/chkconfig httpd on
	/sbin/chkconfig mysqld on
else
	echo -e "This script shouldn't have made it this far with your configuration. I have no idea how you did that. But we'll still give it a shot."
fi

# Move to the www directory, wherever it is
if [[ $OS = "sles" ]]
then
	cd /srv/www/htdocs/
else
	cd /var/www/html
fi

# Use wget to download the latest wordpress tar
if wget https://wordpress.org/latest.tar.gz
then 
	echo -e "\n"
else 
	# Older versions of wget won't download from sites using HTTPS with wildcard certs (*.wordpress.org). This checks for that.
	wget --no-check-certificate https://wordpress.org/latest.tar.gz
fi 
tar -xzvf latest.tar.gz
cd wordpress
mv -f * ../
cd ..
rm -f latest.tar.gz
rm -rf ./wordpress
rm -f index.html

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

# Create www group, add apache to that group, and set permissions on /var/www/html to let WordPress access and update itself. Not needed for Ubuntu?
echo -e "\n\nUpdating permissions. This may take a few minutes...\n\n"
if [[ $OS = "amzn" ]] || [[ $OS = "rhel" ]] || [[ $OS = "CentOS" ]]
then
	if ! groupadd www
	then 
		/usr/sbin/groupadd www
	fi
	usermod -a -G www apache
	chown -R apache /var/www
	chgrp -R www /var/www
	chmod 2775 /var/www
	find /var/www -type d -exec sudo chmod 2775 {} \;
	find /var/www -type f -exec sudo chmod 0664 {} \;
fi

# SUSE's groups are weird. This might let WordPress access and update itself.
if [[ $OS = "sles" ]]
then
	chown -R root /srv/www
	chgrp -R www /srv/www
	chmod 2775 /srv/www
	find /srv/www -type d -exec sudo chmod 2775 {} \;
	find /srv/www -type f -exec sudo chmod 0664 {} \;
	#If this script is run from UserData, SUSE won't accept SSH sessions until it's rebooted. I have no idea why. Restarts if running from UserData
	if [[ ! -t 1 ]]
	then
		shutdown -r now
	fi
fi
echo -e "\nNow go to${green} http://$(curl --silent http://bot.whatismyipaddress.com/) ${nocolor}in your browser to set up your site." | tee -a /root/WordPressSQLInfo.txt
# You're welcome
