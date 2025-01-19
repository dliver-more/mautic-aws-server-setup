#!/bin/bash

###-----------------------------------###
### Fully Automatic Mautic 5.2.1 Installer ###
###-----------------------------------###
#
# This script installs Mautic 5.2.1 on Ubuntu 24.04 in an AWS EC2 instance.
# It configures Apache 2, PHP 8.2, MariaDB 11.4, Snap, Certbot, and enables SSL.
#
# Optimized for a clean and secure setup.

### Variables ###
MAUTIC_DOMAIN=""  # Domain for the Mautic instance
CERTBOT_EMAIL=""  # Email for Let's Encrypt notifications

MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)  # Secure root password
MYSQL_MAUTIC_USER="mautic_user"
MYSQL_MAUTIC_PASSWORD=$(openssl rand -base64 32)  # Secure Mautic user password

MAUTIC_ADMIN_USER="admin"  # Default Mautic admin username
MAUTIC_ADMIN_PASSWORD=$(openssl rand -base64 16)  # Secure admin password

MAUTIC_VERSION="5.2.1"
PHP_VERSION="8.2"
MARIADB_VERSION="11.4"

TIMEZONE="UTC"  # Default timezone, can be customized

### Helper Functions ###
function pause_for_credentials {
    echo "\nGenerated credentials:"
    echo "MySQL Root User: root"
    echo "MySQL Root Password: $MYSQL_ROOT_PASSWORD"
    echo "Mautic Database User: $MYSQL_MAUTIC_USER"
    echo "Mautic Database Password: $MYSQL_MAUTIC_PASSWORD"
    echo "Mautic Admin User: $MAUTIC_ADMIN_USER"
    echo "Mautic Admin Password: $MAUTIC_ADMIN_PASSWORD"
    echo "\nPlease save these credentials securely before continuing."
    read -p "Press ENTER to continue..."
}

function check_requirements {
    echo "\nChecking server requirements..."

    REQUIRED_DISK_SPACE=20  # GB
    REQUIRED_RAM=2  # GB
    REQUIRED_VCPUS=2

    echo "Checking disk space..."
    FREE_DISK=$(df --output=avail -m / | tail -1)
    GB_DISK=$((FREE_DISK/1000))
    if [ $GB_DISK -lt $REQUIRED_DISK_SPACE ]; then
        echo "Warning: At least $REQUIRED_DISK_SPACE GB of free disk space is recommended."
        read -p "Do you want to continue anyway? (y/N): " CONTINUE_DISK
        if [[ ! $CONTINUE_DISK =~ ^[Yy]$ ]]; then
            echo "Exiting installation."
            exit 1
        fi
    fi

    echo "Checking CPU threads..."
    VCPUS=$(nproc)
    if [ $VCPUS -lt $REQUIRED_VCPUS ]; then
        echo "Warning: At least $REQUIRED_VCPUS vCPUs are recommended."
        read -p "Do you want to continue anyway? (y/N): " CONTINUE_CPU
        if [[ ! $CONTINUE_CPU =~ ^[Yy]$ ]]; then
            echo "Exiting installation."
            exit 1
        fi
    fi

    echo "Checking RAM..."
    ALL_RAM=$(($(getconf _PHYS_PAGES) * $(getconf PAGE_SIZE) / (1024 * 1024000)))
    if [ $ALL_RAM -lt $REQUIRED_RAM ]; then
        echo "Warning: At least $REQUIRED_RAM GB of RAM is recommended."
        read -p "Do you want to continue anyway? (y/N): " CONTINUE_RAM
        if [[ ! $CONTINUE_RAM =~ ^[Yy]$ ]]; then
            echo "Exiting installation."
            exit 1
        fi
    fi

    echo "All checks completed.\n"
}

function configure_apache {
    echo "Configuring Apache..."

    # Ensure Apache is installed
    sudo apt install apache2 -y

    # Create Virtual Host Configuration
    sudo bash -c "cat <<EOF > /etc/apache2/sites-available/mautic.conf
<VirtualHost *:80>
    ServerName $MAUTIC_DOMAIN
    ServerAlias www.$MAUTIC_DOMAIN
    DocumentRoot /var/www/html

    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/mautic_error.log
    CustomLog \${APACHE_LOG_DIR}/mautic_access.log combined

    RewriteEngine On
    RewriteCond %{HTTPS} !=on
    RewriteRule ^/?(.*) https://%{SERVER_NAME}/$1 [R,L]
</VirtualHost>
EOF"

    sudo a2ensite mautic.conf
    sudo a2enmod rewrite
    sudo apachectl configtest
    sudo systemctl restart apache2
}

function install_dependencies {
    echo "Updating and installing dependencies..."

    sudo apt update && sudo apt upgrade -y

    # Add PHP repository for 8.2
    sudo add-apt-repository ppa:ondrej/php -y
    sudo apt update

    # Install PHP, MariaDB, and other necessary tools
    sudo apt install -y mariadb-server mariadb-client apache2 snapd \
                   php$PHP_VERSION php$PHP_VERSION-{bcmath,curl,gd,mbstring,mysql,xml,zip,cli,intl,soap} \
                   curl unzip software-properties-common

    # Install and link Certbot
    sudo snap install --classic certbot
    sudo ln -s /snap/bin/certbot /usr/bin/certbot

    # Ensure necessary directories exist
    sudo mkdir -p /var/www/html
    sudo chown -R www-data:www-data /var/www/html
    sudo chmod -R 755 /var/www/html
}

function configure_mariadb {
    echo "Configuring MariaDB..."

    sudo systemctl start mariadb
    sudo systemctl enable mariadb

    sudo mariadb -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';"
    sudo mariadb -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE mautic CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
    sudo mariadb -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE USER '$MYSQL_MAUTIC_USER'@'localhost' IDENTIFIED BY '$MYSQL_MAUTIC_PASSWORD';"
    sudo mariadb -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON mautic.* TO '$MYSQL_MAUTIC_USER'@'localhost';"
    sudo mariadb -u root -p$MYSQL_ROOT_PASSWORD -e "FLUSH PRIVILEGES;"
}

function install_mautic {
    echo "Installing Mautic..."

    sudo wget -q https://github.com/mautic/mautic/releases/download/$MAUTIC_VERSION/$MAUTIC_VERSION.zip
    sudo unzip -q $MAUTIC_VERSION.zip -d /var/www/html
    sudo rm $MAUTIC_VERSION.zip
    sudo chown -R www-data:www-data /var/www/html
    sudo chmod -R 755 /var/www/html

    # Create default admin user
    sudo -u www-data php /var/www/html/bin/console mautic:admin:create \
        --username=$MAUTIC_ADMIN_USER \
        --password=$MAUTIC_ADMIN_PASSWORD \
        --email=$CERTBOT_EMAIL
}

function setup_ssl {
    echo "Setting up SSL with Certbot..."

    sudo certbot --apache -d $MAUTIC_DOMAIN -d www.$MAUTIC_DOMAIN --non-interactive --agree-tos --email $CERTBOT_EMAIL --no-redirect
}

function configure_timezone {
    echo "Configuring server timezone..."
    sudo timedatectl set-timezone $TIMEZONE
}

function configure_firewall {
    echo "Configuring UFW firewall..."
    sudo apt install ufw -y
    sudo ufw allow OpenSSH
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw enable
}

function setup_cron_jobs {
    echo "Setting up cron jobs for database backups..."

    # Backup database daily and keep last 7 backups
    sudo mkdir -p /var/backups/mautic_db
    echo "0 2 * * * root mysqldump -u root -p$MYSQL_ROOT_PASSWORD mautic > /var/backups/mautic_db/mautic_\$(date +\%F).sql && find /var/backups/mautic_db -type f -mtime +7 -exec rm {} \;" | sudo tee /etc/cron.d/mautic-backups > /dev/null
    sudo chmod 644 /etc/cron.d/mautic-backups
    sudo systemctl restart cron
}

function display_post_installation_notes {
    echo "\nMautic installation is complete! Here are the details:"
    echo "URL: https://$MAUTIC_DOMAIN"
    echo "Admin Username: $MAUTIC_ADMIN_USER"
    echo "Admin Password: $MAUTIC_ADMIN_PASSWORD"
    echo "MySQL Root Password: $MYSQL_ROOT_PASSWORD"
    echo "Mautic Database Username: $MYSQL_MAUTIC_USER"
    echo "Mautic Database Password: $MYSQL_MAUTIC_PASSWORD"
    echo "\nPlease save these details securely."
}

### Main Execution ###
pause_for_credentials
check_requirements
install_dependencies
configure_apache
configure_mariadb
install_mautic
setup_ssl
configure_timezone
configure_fire
